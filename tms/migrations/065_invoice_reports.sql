-- Update 069 (undelivered Invoice Update 067). Requires migration 062. No existing invoice data is rewritten.
BEGIN;
CREATE OR REPLACE FUNCTION public.invoice_document_validate_066(p_details jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path=public AS $$
DECLARE k text; v jsonb; d date;
BEGIN
 IF p_details IS NULL OR jsonb_typeof(p_details)<>'object' THEN RAISE EXCEPTION 'Document details must be an object'; END IF;
 FOR k,v IN SELECT * FROM jsonb_each(p_details) LOOP
  IF k='bulgarian_enabled' THEN
   IF jsonb_typeof(v)<>'boolean' THEN RAISE EXCEPTION 'Bulgarian version option must be boolean'; END IF;
   CONTINUE;
  END IF;
  IF k NOT IN ('tax_event_date','payment_method','recipient','recipient_bg','prepared_by','prepared_by_bg') THEN RAISE EXCEPTION 'Unknown document detail: %',k; END IF;
  IF jsonb_typeof(v) NOT IN ('string','null') OR length(p_details->>k)>500 THEN RAISE EXCEPTION 'Invalid document detail: %',k; END IF;
 END LOOP;
 IF nullif(p_details->>'tax_event_date','') IS NOT NULL THEN
  IF (p_details->>'tax_event_date') !~ '^\d{4}-\d{2}-\d{2}$' THEN RAISE EXCEPTION 'Invalid tax event date'; END IF;
  d:=(p_details->>'tax_event_date')::date;
 END IF;
 IF nullif(p_details->>'payment_method','') IS NOT NULL AND p_details->>'payment_method' NOT IN ('bank','cash') THEN RAISE EXCEPTION 'Invalid payment method'; END IF;
 RETURN p_details;
END $$;

CREATE OR REPLACE FUNCTION public.invoice_report_067(p_filters jsonb DEFAULT '{}',p_offset integer DEFAULT 0,p_limit integer DEFAULT 50,p_sort text DEFAULT 'issue_date',p_desc boolean DEFAULT true) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE result jsonb; v_client uuid; v_from date; v_to date; v_basis text; v_balance text; k text; v_today date:=(now() AT TIME ZONE 'Europe/Sofia')::date;
BEGIN
 PERFORM invoice_assert_access_061();
 IF p_offset IS NULL OR p_offset<0 OR p_limit IS NULL OR p_limit<1 OR p_limit>10000 THEN RAISE EXCEPTION 'Invalid report pagination'; END IF;
 IF p_sort IS NULL OR p_sort NOT IN ('number','client','issue_date','due_date','status','currency','total','paid','balance') THEN RAISE EXCEPTION 'Invalid report sort'; END IF;
 IF p_filters IS NULL OR jsonb_typeof(p_filters)<>'object' THEN RAISE EXCEPTION 'Report filters must be an object'; END IF;
 FOR k IN SELECT jsonb_object_keys(p_filters) LOOP
  IF k NOT IN ('search','client_id','currency','statuses','date_basis','from','to','balance') THEN RAISE EXCEPTION 'Unknown report filter: %',k; END IF;
  IF k<>'statuses' AND jsonb_typeof(p_filters->k) NOT IN ('string','null') THEN RAISE EXCEPTION 'Invalid report filter: %',k; END IF;
 END LOOP;
 IF p_filters ? 'statuses' THEN
  IF jsonb_typeof(p_filters->'statuses')<>'array' THEN RAISE EXCEPTION 'Statuses must be an array'; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_filters->'statuses') s WHERE jsonb_typeof(s)<>'string' OR (s#>>'{}') NOT IN ('Draft','Issued','Partially Paid','Paid','Overdue','Disputed','Cancelled','Annulled')) THEN RAISE EXCEPTION 'Invalid invoice status'; END IF;
 END IF;
 IF length(p_filters->>'search')>500 THEN RAISE EXCEPTION 'Search is too long'; END IF;
 v_client:=NULLIF(p_filters->>'client_id','')::uuid;
 v_from:=NULLIF(p_filters->>'from','')::date;v_to:=NULLIF(p_filters->>'to','')::date;
 IF v_from>v_to THEN RAISE EXCEPTION 'From date must be on or before Through date'; END IF;
 v_basis:=COALESCE(NULLIF(p_filters->>'date_basis',''),'issue_date');v_balance:=COALESCE(NULLIF(p_filters->>'balance',''),'all');
 IF v_basis NOT IN ('issue_date','due_date') OR v_balance NOT IN ('all','open','overdue') THEN RAISE EXCEPTION 'Invalid date or balance filter'; END IF;
 WITH amounts AS MATERIALIZED (
  SELECT i.id,i.revision,i.client_id,c.name client,COALESCE(NULLIF(i.billing_snapshot->>'legal_name',''),b.legal_name,'') billing_entity,
   i.invoice_number,i.draft_reference,COALESCE(i.invoice_number,i.draft_reference) number,i.status,i.currency,i.issue_date,i.due_date,i.subtotal,i.tax_amount,i.total,
   COALESCE(p.paid,0) paid,p.last_payment_date,COALESCE(p.payment_count,0) payment_count,
   i.status IN ('Issued','Partially Paid','Paid','Overdue','Disputed') is_official,
   CASE WHEN i.status IN ('Issued','Partially Paid','Paid','Overdue','Disputed') THEN i.total-COALESCE(p.paid,0) ELSE 0 END balance
  FROM client_invoices i JOIN clients c ON c.id=i.client_id LEFT JOIN client_billing_entities b ON b.id=i.billing_entity_id
  LEFT JOIN (SELECT client_invoice_id,sum(amount) paid,max(payment_date) last_payment_date,count(*) payment_count FROM payments WHERE client_invoice_id IS NOT NULL GROUP BY client_invoice_id) p ON p.client_invoice_id=i.id
 ), facts AS (
  SELECT a.*,a.is_official AND a.balance>0 AND a.due_date<v_today is_overdue,
   a.status IN ('Issued','Partially Paid','Overdue','Disputed') AND a.balance>0 payable FROM amounts a
 ), filtered AS MATERIALIZED (
  SELECT f.* FROM facts f WHERE (v_client IS NULL OR f.client_id=v_client)
   AND (NULLIF(p_filters->>'currency','') IS NULL OR f.currency=p_filters->>'currency')
   AND (COALESCE(p_filters->>'search','')='' OR strpos(lower(concat_ws(' ',f.number,f.client,f.billing_entity)),lower(p_filters->>'search'))>0)
   AND (COALESCE(jsonb_array_length(p_filters->'statuses'),0)=0 OR (p_filters->'statuses') ? f.status OR (f.is_overdue AND (p_filters->'statuses') ? 'Overdue'))
   AND (v_from IS NULL OR CASE WHEN v_basis='issue_date' THEN f.issue_date ELSE f.due_date END>=v_from)
   AND (v_to IS NULL OR CASE WHEN v_basis='issue_date' THEN f.issue_date ELSE f.due_date END<=v_to)
   AND (v_balance='all' OR v_balance='open' AND f.balance>0 OR v_balance='overdue' AND f.is_overdue)
 ), ordered AS (
  SELECT f.*,row_number() OVER (ORDER BY
   CASE WHEN NOT COALESCE(p_desc,false) THEN CASE p_sort WHEN 'number' THEN f.number WHEN 'client' THEN f.client WHEN 'status' THEN f.status WHEN 'currency' THEN f.currency END END ASC NULLS LAST,
   CASE WHEN COALESCE(p_desc,false) THEN CASE p_sort WHEN 'number' THEN f.number WHEN 'client' THEN f.client WHEN 'status' THEN f.status WHEN 'currency' THEN f.currency END END DESC NULLS LAST,
   CASE WHEN NOT COALESCE(p_desc,false) THEN CASE p_sort WHEN 'issue_date' THEN f.issue_date WHEN 'due_date' THEN f.due_date END END ASC NULLS LAST,
   CASE WHEN COALESCE(p_desc,false) THEN CASE p_sort WHEN 'issue_date' THEN f.issue_date WHEN 'due_date' THEN f.due_date END END DESC NULLS LAST,
   CASE WHEN NOT COALESCE(p_desc,false) THEN CASE p_sort WHEN 'total' THEN f.total WHEN 'paid' THEN f.paid WHEN 'balance' THEN f.balance END END ASC NULLS LAST,
   CASE WHEN COALESCE(p_desc,false) THEN CASE p_sort WHEN 'total' THEN f.total WHEN 'paid' THEN f.paid WHEN 'balance' THEN f.balance END END DESC NULLS LAST,f.id) report_order FROM filtered f
 )
 SELECT jsonb_build_object('api_version','067','report_type','invoices','generated_at',now(),'as_of',v_today,'date_basis',v_basis,'filters',p_filters,'can_record_payment',is_admin(),
  'total_count',(SELECT count(*) FROM filtered),'overdue_count',(SELECT count(*) FROM filtered WHERE is_overdue),'draft_count',(SELECT count(*) FROM filtered WHERE status='Draft'),
  'next_offset',CASE WHEN (SELECT count(*) FROM filtered)>p_offset+p_limit THEN p_offset+p_limit END,
  'rows',COALESCE((SELECT jsonb_agg(to_jsonb(x)-'report_order' ORDER BY x.report_order) FROM (SELECT * FROM ordered ORDER BY report_order OFFSET p_offset LIMIT p_limit)x),'[]'),
  'summary_by_currency',COALESCE((SELECT jsonb_agg(to_jsonb(s) ORDER BY s.currency) FROM (SELECT currency,count(*) invoice_count,
   COALESCE(sum(total) FILTER(WHERE is_official),0) issued_total,COALESCE(sum(paid) FILTER(WHERE is_official),0) received,
   COALESCE(sum(balance),0) outstanding,COALESCE(sum(balance) FILTER(WHERE is_overdue),0) overdue,
   COALESCE(sum(total) FILTER(WHERE status='Draft'),0) draft_total FROM filtered GROUP BY currency)s),'[]'),
  'clients',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',id,'name',name) ORDER BY name,id) FROM clients),'[]'),
  'currencies',COALESCE((SELECT jsonb_agg(currency ORDER BY currency) FROM (SELECT DISTINCT currency FROM client_invoices WHERE currency IS NOT NULL)c),'[]')) INTO result;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.invoice_document_validate_066(jsonb) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.invoice_report_067(jsonb,integer,integer,text,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.invoice_report_067(jsonb,integer,integer,text,boolean) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;

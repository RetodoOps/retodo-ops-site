-- Update 061: client invoicing from selected approved Scoops. Requires 054.
-- No existing business records are changed. All new writes are authenticated RPCs.
BEGIN;
ALTER TABLE public.client_invoices
 ADD COLUMN IF NOT EXISTS revision integer NOT NULL DEFAULT 1,
 ADD COLUMN IF NOT EXISTS payment_terms_days integer,
 ADD COLUMN IF NOT EXISTS issuer_snapshot jsonb NOT NULL DEFAULT '{}',
 ADD COLUMN IF NOT EXISTS tax_rate numeric(8,4) NOT NULL DEFAULT 0,
 ADD COLUMN IF NOT EXISTS tax_note text,
 ADD COLUMN IF NOT EXISTS fx_date date;
ALTER TABLE public.client_invoice_lines
 ADD COLUMN IF NOT EXISTS scoop_id uuid REFERENCES public.project_scoops(id),
 ADD COLUMN IF NOT EXISTS source_snapshot jsonb NOT NULL DEFAULT '{}',
 ADD COLUMN IF NOT EXISTS adjustment_reason text;
CREATE TABLE IF NOT EXISTS public.invoice_scoop_allocations_061(
 scoop_id uuid PRIMARY KEY REFERENCES public.project_scoops(id),
 invoice_id uuid NOT NULL REFERENCES public.client_invoices(id),created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS invoice_allocations_invoice_idx_061 ON public.invoice_scoop_allocations_061(invoice_id);
CREATE INDEX IF NOT EXISTS invoice_lines_scoop_idx_061 ON public.client_invoice_lines(scoop_id);
CREATE TABLE IF NOT EXISTS public.invoice_settings_061(
 id boolean PRIMARY KEY DEFAULT true CHECK(id),issuer jsonb NOT NULL DEFAULT '{}',next_number bigint CHECK(next_number BETWEEN 1 AND 9999999999),updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public.invoice_settings_061(id) VALUES(true) ON CONFLICT DO NOTHING;
CREATE TABLE IF NOT EXISTS public.invoice_events_061(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),invoice_id uuid REFERENCES public.client_invoices(id),actor_id uuid NOT NULL REFERENCES public.profiles(id),action text NOT NULL,detail jsonb NOT NULL,created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.invoice_settings_061 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoice_scoop_allocations_061 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoice_events_061 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.invoice_settings_061,public.invoice_scoop_allocations_061,public.invoice_events_061 FROM PUBLIC,anon,authenticated;
-- Remove direct client finance mutation paths. Existing company SELECT policies remain.
REVOKE INSERT,UPDATE,DELETE,TRUNCATE ON public.client_invoices,public.client_invoice_lines,public.payments FROM authenticated,anon;

CREATE OR REPLACE FUNCTION public.invoice_assert_access_061(p_write boolean DEFAULT false,p_admin boolean DEFAULT false) RETURNS void
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public AS $$
BEGIN
 IF NOT COALESCE(is_company_user(),false) OR NOT COALESCE(current_user_access_enabled(),false)
    OR (p_write AND NOT COALESCE(can_manage_operations(),false)) OR (p_admin AND NOT COALESCE(is_admin(),false))
 THEN RAISE EXCEPTION 'Invoice access denied' USING ERRCODE='42501'; END IF;
END $$;

CREATE OR REPLACE FUNCTION public.invoice_workspace_061(p_client uuid DEFAULT NULL,p_search text DEFAULT '',p_offset integer DEFAULT 0,p_limit integer DEFAULT 50,p_invoice uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE result jsonb;
BEGIN
 PERFORM invoice_assert_access_061();
 IF p_offset<0 OR p_limit<1 OR p_limit>250 THEN RAISE EXCEPTION 'Invalid pagination'; END IF;
 WITH eligible AS MATERIALIZED (
  SELECT s.id,s.project_id,s.scoop_number,p.project_number,COALESCE(p.display_name,p.project_number) project_name,
   s.source_language,s.target_language,s.status,s.price,p.currency,p.po_number client_po,
   p.client_id,p.account_id,c.name client,a.name account,c.default_payment_days payment_terms_days,
   (SELECT units_per_eur FROM report_fx_rates WHERE currency=p.currency ORDER BY rate_date DESC LIMIT 1) fx_units,
   al.invoice_id reserved_invoice
  FROM project_scoops s JOIN projects p ON p.id=s.project_id JOIN clients c ON c.id=p.client_id
  LEFT JOIN client_accounts a ON a.id=p.account_id LEFT JOIN invoice_scoop_allocations_061 al ON al.scoop_id=s.id
  WHERE s.active AND s.status='Approved' AND p.status<>'Cancelled'
   AND (p_client IS NULL OR p.client_id=p_client)
   AND (al.invoice_id IS NULL OR al.invoice_id=p_invoice)
   AND NOT EXISTS(SELECT 1 FROM client_invoice_lines l JOIN client_invoices i ON i.id=l.invoice_id WHERE l.project_id=p.id AND l.scoop_id IS NULL AND i.status NOT IN ('Cancelled','Annulled') AND i.id IS DISTINCT FROM p_invoice)
   AND (COALESCE(p_search,'')='' OR concat_ws(' ',s.scoop_number,p.project_number,p.display_name,p.po_number,c.name,a.name,s.source_language,s.target_language) ILIKE '%'||p_search||'%')
 )
 SELECT jsonb_build_object('api_version','061','role',current_app_role(),
  'clients',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',id,'name',name,'currency',default_currency,'payment_terms_days',default_payment_days) ORDER BY name) FROM clients),'[]'),
  'billing_entities',COALESCE((SELECT jsonb_agg(to_jsonb(b) ORDER BY b.name) FROM client_billing_entities b WHERE b.active AND (p_client IS NULL OR b.client_id=p_client)),'[]'),
  'rows',COALESCE((SELECT jsonb_agg(to_jsonb(e)) FROM (SELECT * FROM eligible ORDER BY project_number,scoop_number,id OFFSET p_offset LIMIT p_limit)e),'[]'),
  'total_count',(SELECT count(*) FROM eligible),
  'invoices',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT i.*,c.name client,COALESCE((SELECT sum(amount) FROM payments WHERE client_invoice_id=i.id),0) paid FROM client_invoices i JOIN clients c ON c.id=i.client_id WHERE (p_client IS NULL OR i.client_id=p_client) ORDER BY i.created_at DESC LIMIT 250)x),'[]'),
  'settings',(SELECT to_jsonb(st) FROM invoice_settings_061 st WHERE id),
  'fx_date',(SELECT max(rate_date) FROM report_fx_rates WHERE rate_date<=CURRENT_DATE AND rate_date>=CURRENT_DATE-7),
  'fx_rates',COALESCE((SELECT jsonb_object_agg(currency,units_per_eur) FROM report_fx_rates WHERE rate_date=(SELECT max(rate_date) FROM report_fx_rates WHERE rate_date<=CURRENT_DATE AND rate_date>=CURRENT_DATE-7)),'{}')) INTO result;
 RETURN result;
END $$;

CREATE OR REPLACE FUNCTION public.invoice_get_061(p_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
BEGIN
 PERFORM invoice_assert_access_061();
 RETURN (SELECT jsonb_build_object('invoice',to_jsonb(i),'lines',COALESCE((SELECT jsonb_agg(to_jsonb(l) ORDER BY sort_order,id) FROM client_invoice_lines l WHERE l.invoice_id=i.id),'[]'),
 'payments',COALESCE((SELECT jsonb_agg(to_jsonb(p) ORDER BY payment_date,id) FROM payments p WHERE p.client_invoice_id=i.id),'[]'),
 'history',COALESCE((SELECT jsonb_agg(to_jsonb(e) ORDER BY created_at DESC) FROM invoice_events_061 e WHERE e.invoice_id=i.id),'[]')) FROM client_invoices i WHERE i.id=p_id);
END $$;

CREATE OR REPLACE FUNCTION public.invoice_save_061(p_payload jsonb,p_id uuid DEFAULT NULL,p_revision integer DEFAULT NULL) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE inv client_invoices%ROWTYPE; c clients%ROWTYPE; r jsonb; sc record; item record;
 v_id uuid:=COALESCE(p_id,gen_random_uuid()); v_scoop uuid; v_client uuid; v_currency text; v_date date; v_fx date;
 v_amount numeric; v_original numeric; v_subtotal numeric:=0; v_tax numeric; v_rate numeric; v_snapshot jsonb; v_n integer:=0; v_seen uuid[]:='{}';
BEGIN
 PERFORM invoice_assert_access_061(true);
 IF p_payload IS NULL OR jsonb_typeof(p_payload)<>'object' OR jsonb_typeof(p_payload->'lines') IS DISTINCT FROM 'array' OR jsonb_array_length(p_payload->'lines')>500 THEN RAISE EXCEPTION 'Invalid invoice payload (maximum 500 rows)'; END IF;
 v_client:=(p_payload->>'client_id')::uuid;SELECT * INTO c FROM clients WHERE id=v_client FOR SHARE;
 IF c.id IS NULL THEN RAISE EXCEPTION 'Choose a Client'; END IF;
 v_currency:=COALESCE(NULLIF(p_payload->>'currency',''),c.default_currency);
 IF v_currency !~ '^[A-Z]{3}$' THEN RAISE EXCEPTION 'Choose a currency'; END IF;
 v_date:=(p_payload->>'issue_date')::date;IF v_date IS NULL THEN RAISE EXCEPTION 'Enter the planned issue date'; END IF;
 v_rate:=COALESCE((p_payload->>'tax_rate')::numeric,0);IF v_rate<0 OR v_rate>100 OR v_rate::text IN ('NaN','Infinity','-Infinity') THEN RAISE EXCEPTION 'Invalid tax rate'; END IF;
 IF NULLIF(p_payload->>'proposed_number','') IS NOT NULL AND (p_payload->>'proposed_number')::bigint NOT BETWEEN 1 AND 9999999999 THEN RAISE EXCEPTION 'Invoice number must be between 1 and 9999999999'; END IF;
 IF c.default_payment_days<0 THEN RAISE EXCEPTION 'Correct the Client payment terms'; END IF;
 SELECT max(rate_date) INTO v_fx FROM report_fx_rates WHERE rate_date<=CURRENT_DATE AND rate_date>=CURRENT_DATE-7;
 IF report_eur_units_061(v_currency,v_fx) IS NULL THEN RAISE EXCEPTION 'No current EUR conversion rate for this invoice currency. Refresh rates first'; END IF;
 IF p_id IS NOT NULL THEN
  SELECT * INTO inv FROM client_invoices WHERE id=p_id FOR UPDATE;
  IF inv.id IS NULL OR inv.status<>'Draft' THEN RAISE EXCEPTION 'Only Draft invoices can be edited'; END IF;
  IF p_revision IS DISTINCT FROM inv.revision THEN RAISE EXCEPTION 'This draft changed in another window. Reopen it before saving'; END IF;
  IF inv.client_id<>v_client THEN RAISE EXCEPTION 'The draft Client cannot be changed'; END IF;
 ELSE
  INSERT INTO client_invoices(id,draft_reference,client_id,currency,created_by) VALUES(v_id,'DRAFT-'||v_id::text,v_client,v_currency,auth.uid());
 END IF;
 IF NULLIF(p_payload->>'billing_entity_id','') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM client_billing_entities WHERE id=(p_payload->>'billing_entity_id')::uuid AND client_id=v_client AND active) THEN RAISE EXCEPTION 'Billing entity must belong to this Client'; END IF;
 -- Lock source Projects as well: client PO/currency cannot change while saving this snapshot.
 PERFORM p.id FROM projects p WHERE p.id IN (SELECT s.project_id FROM project_scoops s WHERE s.id IN (SELECT NULLIF(value->>'scoop_id','')::uuid FROM jsonb_array_elements(p_payload->'lines'))) ORDER BY p.id FOR SHARE;
 -- Lock source Scoops in deterministic order before reserving; a unique allocation is the final concurrency barrier.
 PERFORM s.id FROM project_scoops s WHERE s.id IN (SELECT NULLIF(value->>'scoop_id','')::uuid FROM jsonb_array_elements(p_payload->'lines')) ORDER BY s.id FOR UPDATE;
 DELETE FROM invoice_scoop_allocations_061 WHERE invoice_id=v_id;
 DELETE FROM client_invoice_lines WHERE invoice_id=v_id;
 FOR r IN SELECT value FROM jsonb_array_elements(p_payload->'lines') LOOP
  v_n:=v_n+1;v_scoop:=NULLIF(r->>'scoop_id','')::uuid;v_snapshot:='{}';
  v_amount:=round((r->>'amount')::numeric,2);
  IF v_amount IS NULL OR v_amount::text IN ('NaN','Infinity','-Infinity') OR abs(v_amount)>999999999999 THEN RAISE EXCEPTION 'Invalid row amount'; END IF;
  IF NULLIF(btrim(r->>'description'),'') IS NULL THEN RAISE EXCEPTION 'Every row needs a description'; END IF;
  IF v_scoop IS NOT NULL THEN
   IF v_scoop=ANY(v_seen) THEN RAISE EXCEPTION 'A Scoop can appear only once in an invoice'; END IF;v_seen:=array_append(v_seen,v_scoop);
   SELECT s.*,p.client_id,p.currency,p.project_number,p.po_number,p.status project_status INTO sc FROM project_scoops s JOIN projects p ON p.id=s.project_id WHERE s.id=v_scoop;
   IF sc.id IS NULL OR NOT sc.active OR sc.status<>'Approved' OR sc.project_status='Cancelled' OR sc.client_id<>v_client THEN RAISE EXCEPTION 'Select an active approved Scoop belonging to the invoice Client'; END IF;
   IF v_amount<0 THEN RAISE EXCEPTION 'A Scoop amount cannot be negative. Use a separate adjustment row'; END IF;
   IF EXISTS(SELECT 1 FROM client_invoice_lines l JOIN client_invoices i ON i.id=l.invoice_id WHERE l.project_id=sc.project_id AND l.scoop_id IS NULL AND i.status NOT IN ('Cancelled','Annulled') AND i.id<>v_id) THEN RAISE EXCEPTION 'This Project already has a legacy invoice allocation; review it before billing a Scoop'; END IF;
   v_original:=CASE WHEN sc.currency=v_currency THEN sc.price ELSE round(sc.price/report_eur_units_061(sc.currency,v_fx)*report_eur_units_061(v_currency,v_fx),2) END;
   IF v_original IS NULL THEN RAISE EXCEPTION 'A required exchange rate is missing. Refresh rates before adding this Scoop'; END IF;
   IF v_amount<>v_original AND NULLIF(btrim(r->>'adjustment_reason'),'') IS NULL THEN RAISE EXCEPTION 'Enter a reason when changing a Scoop amount'; END IF;
   v_snapshot:=jsonb_build_object('scoop_number',sc.scoop_number,'project_number',sc.project_number,'project_id',sc.project_id,'client_po',sc.po_number,'source_language',sc.source_language,'target_language',sc.target_language,'source_currency',sc.currency,'source_amount',sc.price,'converted_amount',v_original,'fx_date',CASE WHEN sc.currency<>v_currency THEN v_fx END,'source_units_per_eur',report_eur_units_061(sc.currency,v_fx),'invoice_units_per_eur',report_eur_units_061(v_currency,v_fx));
   BEGIN INSERT INTO invoice_scoop_allocations_061(scoop_id,invoice_id) VALUES(v_scoop,v_id);
   EXCEPTION WHEN unique_violation THEN RAISE EXCEPTION 'This Scoop is already reserved or invoiced. Refresh the queue'; END;
  END IF;
  INSERT INTO client_invoice_lines(invoice_id,project_id,scoop_id,description,quantity,unit,unit_price,amount,sort_order,source_snapshot,adjustment_reason)
  VALUES(v_id,CASE WHEN v_scoop IS NOT NULL THEN sc.project_id END,v_scoop,btrim(r->>'description'),1,CASE WHEN v_scoop IS NULL THEN 'Adjustment' ELSE 'Scoop' END,v_amount,v_amount,v_n,v_snapshot,NULLIF(btrim(r->>'adjustment_reason'),''));
  v_subtotal:=v_subtotal+v_amount;
 END LOOP;
 IF v_subtotal<0 THEN RAISE EXCEPTION 'Invoice subtotal cannot be negative'; END IF;
 v_tax:=round(v_subtotal*v_rate/100,2);
 UPDATE client_invoices SET billing_entity_id=NULLIF(p_payload->>'billing_entity_id','')::uuid,currency=v_currency,issue_date=v_date,
  payment_terms_days=c.default_payment_days,due_date=CASE WHEN c.default_payment_days IS NOT NULL THEN v_date+c.default_payment_days END,
  tax_rate=v_rate,tax_note=NULLIF(btrim(p_payload->>'tax_note'),''),subtotal=v_subtotal,tax_amount=v_tax,total=v_subtotal+v_tax,
  exchange_rate_to_eur=CASE WHEN v_currency='EUR' THEN 1 ELSE 1/report_eur_units_061(v_currency,v_fx) END,
  total_eur=CASE WHEN v_currency='EUR' THEN v_subtotal+v_tax ELSE round((v_subtotal+v_tax)/report_eur_units_061(v_currency,v_fx),2) END,
  fx_date=v_fx,notes=NULLIF(btrim(p_payload->>'notes'),''),proposed_number=CASE WHEN NULLIF(p_payload->>'proposed_number','') IS NOT NULL THEN lpad((p_payload->>'proposed_number')::bigint::text,10,'0') END,revision=CASE WHEN p_id IS NULL THEN 1 ELSE revision+1 END WHERE id=v_id;
 INSERT INTO invoice_events_061(invoice_id,actor_id,action,detail) VALUES(v_id,auth.uid(),'Draft saved',jsonb_build_object('rows',v_n,'subtotal',v_subtotal,'tax',v_tax,'currency',v_currency,'scoops',v_seen));
 RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION public.invoice_settings_save_061(p_issuer jsonb,p_next bigint) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
 PERFORM invoice_assert_access_061(true,true);
 IF jsonb_typeof(p_issuer) IS DISTINCT FROM 'object' OR p_next IS NULL OR p_next NOT BETWEEN 1 AND 9999999999 THEN RAISE EXCEPTION 'Invalid invoice settings'; END IF;
 UPDATE invoice_settings_061 SET issuer=p_issuer,next_number=p_next,updated_at=now() WHERE id;
 INSERT INTO invoice_events_061(actor_id,action,detail) VALUES(auth.uid(),'Invoice settings updated',jsonb_build_object('issuer',p_issuer,'next_number',p_next));
END $$;

CREATE OR REPLACE FUNCTION public.invoice_issue_061(p_id uuid,p_revision integer) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE inv client_invoices%ROWTYPE; settings invoice_settings_061%ROWTYPE; n bigint; bill jsonb; terms integer; currency_units numeric;
BEGIN
 PERFORM invoice_assert_access_061(true,true);
 SELECT * INTO inv FROM client_invoices WHERE id=p_id FOR UPDATE;
 IF inv.id IS NULL OR inv.status<>'Draft' OR inv.revision IS DISTINCT FROM p_revision THEN RAISE EXCEPTION 'Reopen the current Draft before issuing'; END IF;
 SELECT * INTO settings FROM invoice_settings_061 WHERE id FOR UPDATE;
 IF NULLIF(settings.issuer->>'legal_name','') IS NULL OR NULLIF(settings.issuer->>'address','') IS NULL OR NULLIF(settings.issuer->>'registration_number','') IS NULL OR NULLIF(settings.issuer->>'iban','') IS NULL THEN RAISE EXCEPTION 'Complete issuer legal name, registration number, address and IBAN in Invoice settings'; END IF;
 SELECT default_payment_days INTO terms FROM clients WHERE id=inv.client_id FOR SHARE;
 IF terms IS NULL OR terms<0 THEN RAISE EXCEPTION 'Set payment terms in the Client profile'; END IF;
 IF terms IS DISTINCT FROM inv.payment_terms_days THEN RAISE EXCEPTION 'Client payment terms changed. Save the draft again to recalculate the due date'; END IF;
 SELECT to_jsonb(b) INTO bill FROM client_billing_entities b WHERE id=inv.billing_entity_id AND client_id=inv.client_id AND active;
 IF bill IS NULL OR NULLIF(bill->>'legal_name','') IS NULL OR NULLIF(bill->>'address_line_1','') IS NULL OR NULLIF(bill->>'country_code','') IS NULL THEN RAISE EXCEPTION 'Choose a complete legal Billing entity in the Client profile'; END IF;
 IF inv.tax_note IS NULL THEN RAISE EXCEPTION 'Record the tax treatment / basis before issuing'; END IF;
 IF NOT EXISTS(SELECT 1 FROM client_invoice_lines WHERE invoice_id=p_id) THEN RAISE EXCEPTION 'An invoice needs at least one row'; END IF;
 PERFORM p.id FROM projects p WHERE p.id IN (SELECT project_id FROM client_invoice_lines WHERE invoice_id=p_id) ORDER BY p.id FOR SHARE;
 PERFORM s.id FROM project_scoops s JOIN client_invoice_lines l ON l.scoop_id=s.id WHERE l.invoice_id=p_id ORDER BY s.id FOR UPDATE;
 IF EXISTS(SELECT 1 FROM client_invoice_lines l JOIN project_scoops s ON s.id=l.scoop_id JOIN projects p ON p.id=s.project_id WHERE l.invoice_id=p_id AND (NOT s.active OR s.status<>'Approved' OR p.status='Cancelled' OR p.client_id<>inv.client_id)) THEN RAISE EXCEPTION 'A selected Scoop is no longer eligible'; END IF;
 IF EXISTS(SELECT 1 FROM client_invoice_lines l JOIN project_scoops s ON s.id=l.scoop_id JOIN projects p ON p.id=s.project_id WHERE l.invoice_id=p_id AND (s.price IS DISTINCT FROM (l.source_snapshot->>'source_amount')::numeric OR p.currency IS DISTINCT FROM l.source_snapshot->>'source_currency' OR p.po_number IS DISTINCT FROM l.source_snapshot->>'client_po')) THEN RAISE EXCEPTION 'Source price, currency or PO changed. Review and save the draft again'; END IF;
 n:=COALESCE(inv.proposed_number::bigint,settings.next_number);
 IF n IS NULL OR n NOT BETWEEN 1 AND 9999999999 THEN RAISE EXCEPTION 'Set the first invoice number or enter a valid proposed number'; END IF;
 IF EXISTS(SELECT 1 FROM client_invoices WHERE invoice_number=lpad(n::text,10,'0')) THEN RAISE EXCEPTION 'Invoice number already exists'; END IF;
 currency_units:=report_eur_units_061(inv.currency,inv.fx_date);
 IF currency_units IS NULL THEN RAISE EXCEPTION 'Save a draft with a valid currency rate before issue'; END IF;
 UPDATE client_invoices SET status='Issued',invoice_number=lpad(n::text,10,'0'),issuer_snapshot=settings.issuer,billing_snapshot=bill,
  issued_by=auth.uid(),issued_at=now(),revision=revision+1 WHERE id=p_id;
 UPDATE invoice_settings_061 SET next_number=CASE WHEN n<9999999999 THEN n+1 END,updated_at=now() WHERE id;
 INSERT INTO invoice_events_061(invoice_id,actor_id,action,detail) VALUES(p_id,auth.uid(),'Invoice issued',jsonb_build_object('number',lpad(n::text,10,'0'),'total',inv.total,'currency',inv.currency));
 PERFORM invoice_sync_projects_061(p_id);
 RETURN invoice_get_061(p_id);
END $$;

CREATE OR REPLACE FUNCTION public.invoice_cancel_draft_061(p_id uuid,p_revision integer) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE inv client_invoices%ROWTYPE;
BEGIN
 PERFORM invoice_assert_access_061(true);
 SELECT * INTO inv FROM client_invoices WHERE id=p_id FOR UPDATE;
 IF inv.id IS NULL OR inv.status<>'Draft' OR inv.revision IS DISTINCT FROM p_revision THEN RAISE EXCEPTION 'Only the current Draft can be cancelled'; END IF;
 UPDATE client_invoices SET status='Cancelled',revision=revision+1 WHERE id=p_id;
 DELETE FROM invoice_scoop_allocations_061 WHERE invoice_id=p_id;
 INSERT INTO invoice_events_061(invoice_id,actor_id,action,detail) VALUES(p_id,auth.uid(),'Draft cancelled','{}');
END $$;

CREATE OR REPLACE FUNCTION public.invoice_record_payment_061(p_id uuid,p_amount numeric,p_date date,p_reference text,p_currency text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE inv client_invoices%ROWTYPE; paid numeric;
BEGIN
 PERFORM invoice_assert_access_061(true,true);
 SELECT * INTO inv FROM client_invoices WHERE id=p_id FOR UPDATE;
 IF inv.id IS NULL OR inv.status NOT IN ('Issued','Partially Paid','Overdue','Disputed') THEN RAISE EXCEPTION 'Invoice is not open for payment'; END IF;
 IF p_amount IS NULL OR p_amount<=0 OR p_amount<>round(p_amount,2) OR p_amount::text IN ('NaN','Infinity','-Infinity') OR p_date IS NULL OR p_date>CURRENT_DATE OR p_currency IS DISTINCT FROM inv.currency OR NULLIF(btrim(p_reference),'') IS NULL THEN RAISE EXCEPTION 'Enter a valid payment date, positive amount, matching currency and reference'; END IF;
 IF EXISTS(SELECT 1 FROM payments WHERE client_invoice_id=p_id AND reference=btrim(p_reference) AND payment_date=p_date AND amount=p_amount) THEN RAISE EXCEPTION 'This payment is already recorded'; END IF;
 SELECT COALESCE(sum(amount),0) INTO paid FROM payments WHERE client_invoice_id=p_id;
 IF paid+p_amount>inv.total THEN RAISE EXCEPTION 'Payment exceeds the remaining balance'; END IF;
 INSERT INTO payments(direction,client_invoice_id,payment_date,amount,currency,reference,approved_by) VALUES('Receivable',p_id,p_date,p_amount,p_currency,btrim(p_reference),auth.uid());
 UPDATE client_invoices SET status=CASE WHEN paid+p_amount=total THEN 'Paid' ELSE 'Partially Paid' END,revision=revision+1 WHERE id=p_id;
 INSERT INTO invoice_events_061(invoice_id,actor_id,action,detail) VALUES(p_id,auth.uid(),'Payment recorded',jsonb_build_object('amount',p_amount,'currency',p_currency,'date',p_date,'reference',p_reference));
 PERFORM invoice_sync_projects_061(p_id);
 RETURN invoice_get_061(p_id);
END $$;

-- Preserve issued facts even if another SQL/RPC path is added later.
CREATE OR REPLACE FUNCTION public.invoice_immutable_061() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_status text;
BEGIN
 IF TG_TABLE_NAME='client_invoice_lines' THEN
  SELECT status INTO v_status FROM client_invoices WHERE id=CASE WHEN TG_OP='DELETE' THEN OLD.invoice_id ELSE NEW.invoice_id END;
  IF v_status<>'Draft' THEN RAISE EXCEPTION 'Issued or cancelled invoice rows cannot be changed'; END IF;
  IF TG_OP='UPDATE' AND OLD.invoice_id IS DISTINCT FROM NEW.invoice_id THEN RAISE EXCEPTION 'Invoice rows cannot be moved'; END IF;
 ELSE
  IF OLD.status NOT IN ('Draft','Cancelled') THEN
   IF TG_OP='DELETE' THEN RAISE EXCEPTION 'Issued invoices cannot be deleted'; END IF;
   IF (to_jsonb(NEW)-ARRAY['status','revision','updated_at','annulled_at','replacement_invoice_id']) IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['status','revision','updated_at','annulled_at','replacement_invoice_id']) THEN RAISE EXCEPTION 'Issued invoice facts are frozen'; END IF;
   IF NEW.status IN ('Draft','Cancelled') THEN RAISE EXCEPTION 'An issued invoice cannot return to Draft or Cancelled'; END IF;
  END IF;
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS invoice_lines_immutable_061 ON public.client_invoice_lines;
CREATE TRIGGER invoice_lines_immutable_061 BEFORE INSERT OR UPDATE OR DELETE ON public.client_invoice_lines FOR EACH ROW EXECUTE FUNCTION public.invoice_immutable_061();
DROP TRIGGER IF EXISTS invoices_immutable_061 ON public.client_invoices;
CREATE TRIGGER invoices_immutable_061 BEFORE UPDATE OR DELETE ON public.client_invoices FOR EACH ROW EXECUTE FUNCTION public.invoice_immutable_061();

-- Only mark an entire Project billed once every active Scoop has an issued invoice.
CREATE OR REPLACE FUNCTION public.invoice_sync_projects_061(p_invoice uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
 WITH affected AS (SELECT DISTINCT project_id FROM client_invoice_lines WHERE invoice_id=p_invoice AND project_id IS NOT NULL),
 states AS (SELECT s.project_id,count(*) all_scoops,
  count(*) FILTER(WHERE i.status IN ('Issued','Partially Paid','Paid','Overdue','Disputed')) billed,
  count(*) FILTER(WHERE i.status='Paid') fully_paid,
  count(*) FILTER(WHERE i.status IN ('Paid','Partially Paid')) has_paid
  FROM project_scoops s JOIN affected a ON a.project_id=s.project_id
  LEFT JOIN invoice_scoop_allocations_061 al ON al.scoop_id=s.id LEFT JOIN client_invoices i ON i.id=al.invoice_id WHERE s.active GROUP BY s.project_id)
 UPDATE projects p SET financial_status=CASE WHEN st.fully_paid=st.all_scoops THEN 'Paid' WHEN st.has_paid>0 THEN 'Partially Paid' ELSE 'Invoiced' END
 FROM states st WHERE p.id=st.project_id AND st.billed=st.all_scoops AND st.all_scoops>0
 AND p.financial_status IN ('Not Ready','Ready to Invoice','Invoiced','Partially Paid','Paid');
END $$;
REVOKE ALL ON FUNCTION public.invoice_immutable_061(),public.invoice_sync_projects_061(uuid) FROM PUBLIC,anon,authenticated;

-- RPCs are the only ordinary-user mutation path. No service key is exposed to the browser.
REVOKE ALL ON FUNCTION public.invoice_assert_access_061(boolean,boolean),public.invoice_workspace_061(uuid,text,integer,integer,uuid),public.invoice_get_061(uuid),public.invoice_save_061(jsonb,uuid,integer),public.invoice_settings_save_061(jsonb,bigint),public.invoice_issue_061(uuid,integer),public.invoice_cancel_draft_061(uuid,integer),public.invoice_record_payment_061(uuid,numeric,date,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.invoice_workspace_061(uuid,text,integer,integer,uuid),public.invoice_get_061(uuid),public.invoice_save_061(jsonb,uuid,integer),public.invoice_settings_save_061(jsonb,bigint),public.invoice_issue_061(uuid,integer),public.invoice_cancel_draft_061(uuid,integer),public.invoice_record_payment_061(uuid,numeric,date,text,text) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;

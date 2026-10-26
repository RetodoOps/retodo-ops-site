-- Update 069: manual rows must not access an unassigned Scoop RECORD.
-- Compatible with installed invoice Update 066; does not require invoice Reports.
-- No stored invoices, receipts, snapshots, numbering or source data are rewritten.
BEGIN;
CREATE OR REPLACE FUNCTION public.invoice_save_061(p_payload jsonb,p_id uuid DEFAULT NULL,p_revision integer DEFAULT NULL) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE inv client_invoices%ROWTYPE; c clients%ROWTYPE; r jsonb; sc record; item record;
 v_id uuid:=COALESCE(p_id,gen_random_uuid()); v_scoop uuid; v_project_id uuid; v_client uuid; v_currency text; v_date date; v_fx date;
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
  v_project_id:=NULL;v_n:=v_n+1;v_scoop:=NULLIF(r->>'scoop_id','')::uuid;v_snapshot:='{}';
  v_amount:=round((r->>'amount')::numeric,2);
  IF v_amount IS NULL OR v_amount::text IN ('NaN','Infinity','-Infinity') OR abs(v_amount)>999999999999 THEN RAISE EXCEPTION 'Invalid row amount'; END IF;
  IF NULLIF(btrim(r->>'description'),'') IS NULL THEN RAISE EXCEPTION 'Every row needs a description'; END IF;
  IF v_scoop IS NOT NULL THEN
   IF v_scoop=ANY(v_seen) THEN RAISE EXCEPTION 'A Scoop can appear only once in an invoice'; END IF;v_seen:=array_append(v_seen,v_scoop);
   SELECT s.*,p.client_id,p.currency,p.project_number,p.po_number,p.status project_status INTO sc FROM project_scoops s JOIN projects p ON p.id=s.project_id WHERE s.id=v_scoop;
   IF sc.id IS NULL OR NOT sc.active OR sc.status<>'Approved' OR sc.project_status='Cancelled' OR sc.client_id<>v_client THEN RAISE EXCEPTION 'Select an active approved Scoop belonging to the invoice Client'; END IF;
   v_project_id:=sc.project_id;
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
  VALUES(v_id,v_project_id,v_scoop,btrim(r->>'description'),1,CASE WHEN v_scoop IS NULL THEN 'Adjustment' ELSE 'Scoop' END,v_amount,v_amount,v_n,v_snapshot,NULLIF(btrim(r->>'adjustment_reason'),''));
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

REVOKE ALL ON FUNCTION public.invoice_save_061(jsonb,uuid,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.invoice_save_061(jsonb,uuid,integer) TO authenticated;
NOTIFY pgrst, 'reload schema';
COMMIT;

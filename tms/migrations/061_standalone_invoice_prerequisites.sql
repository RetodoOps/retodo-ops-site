-- Update 065 invoice prerequisites. Requires installed 054/055/056.
-- Recovers invoice-only 064 fixes; does not overwrite Sales 058 or Reports.
-- Safe to reapply if the separately delivered invoice 058 was already installed.
-- No production data is deleted on installation; deletion requires an explicit admin RPC.
BEGIN;
CREATE OR REPLACE FUNCTION public.invoice_immutable_061() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_status text;
BEGIN
 -- Explicit scoped exceptions, independent of source line endings (repair 056).
 IF public.is_admin() AND (
   nullif(current_setting('retodo.invoice_revision_062',true),'') = CASE WHEN TG_TABLE_NAME='client_invoice_lines' THEN COALESCE(to_jsonb(NEW)->>'invoice_id',to_jsonb(OLD)->>'invoice_id') ELSE COALESCE(to_jsonb(NEW)->>'id',to_jsonb(OLD)->>'id') END
   OR (TG_OP='DELETE' AND nullif(current_setting('retodo.invoice_delete_064',true),'') = CASE WHEN TG_TABLE_NAME='client_invoice_lines' THEN to_jsonb(OLD)->>'invoice_id' ELSE to_jsonb(OLD)->>'id' END)
 ) THEN IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF; END IF;
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


-- A request key makes payment retries idempotent even after a lost response.
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS receipt_key_064 uuid;
CREATE UNIQUE INDEX IF NOT EXISTS payments_receipt_key_064 ON public.payments(receipt_key_064) WHERE receipt_key_064 IS NOT NULL;
CREATE OR REPLACE FUNCTION public.invoice_receive_payment_064(p_id uuid,p_revision integer,p_mode text,p_amount numeric,p_date date,p_reference text,p_request uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE inv client_invoices%ROWTYPE; existing payments%ROWTYPE; paid numeric; v_amount numeric; ref text;
BEGIN
 PERFORM invoice_assert_access_061(true,true);
 IF p_request IS NULL THEN RAISE EXCEPTION 'Payment request key is required. Reopen the payment dialog'; END IF;
 SELECT * INTO inv FROM client_invoices WHERE id=p_id FOR UPDATE;
 IF inv.id IS NULL THEN RAISE EXCEPTION 'Invoice not found'; END IF;
 IF p_mode IS NULL OR p_mode NOT IN ('full','partial') THEN RAISE EXCEPTION 'Choose full or partial payment'; END IF;
 IF p_date IS NULL THEN RAISE EXCEPTION 'Choose the payment date'; END IF;
 IF p_date>(now() AT TIME ZONE 'Europe/Sofia')::date THEN RAISE EXCEPTION 'Payment date cannot be in the future'; END IF;
 ref:=COALESCE(NULLIF(btrim(p_reference),''),'Receipt '||inv.invoice_number||' / '||p_request::text);
 SELECT * INTO existing FROM payments WHERE receipt_key_064=p_request;
 IF existing.id IS NOT NULL THEN
  IF existing.client_invoice_id<>p_id OR existing.payment_date<>p_date OR existing.reference<>ref OR (p_mode='partial' AND existing.amount IS DISTINCT FROM p_amount) THEN RAISE EXCEPTION 'Payment request already used with different details'; END IF;
  RETURN invoice_get_061(p_id);
 END IF;
 IF inv.status NOT IN ('Issued','Partially Paid','Overdue','Disputed') THEN RAISE EXCEPTION 'Invoice is not open for payment'; END IF;
 IF inv.revision IS DISTINCT FROM p_revision THEN RAISE EXCEPTION 'Invoice changed. Reopen it before recording payment'; END IF;
 SELECT COALESCE(sum(p.amount),0) INTO paid FROM payments p WHERE client_invoice_id=p_id;
 v_amount:=CASE WHEN p_mode='full' THEN inv.total-paid ELSE p_amount END;
 IF v_amount IS NULL OR v_amount<=0 OR v_amount::text IN ('NaN','Infinity','-Infinity') OR v_amount<>round(v_amount,2) THEN RAISE EXCEPTION 'Enter a positive amount with at most two decimal places'; END IF;
 IF v_amount>inv.total-paid THEN RAISE EXCEPTION 'Payment exceeds the remaining balance'; END IF;
 IF EXISTS(SELECT 1 FROM payments p WHERE p.client_invoice_id=p_id AND p.reference=ref AND p.payment_date=p_date AND p.amount=v_amount) THEN RAISE EXCEPTION 'This payment is already recorded'; END IF;
 INSERT INTO payments(direction,client_invoice_id,payment_date,amount,currency,reference,approved_by,receipt_key_064) VALUES('Receivable',p_id,p_date,v_amount,inv.currency,ref,auth.uid(),p_request);
 UPDATE client_invoices SET status=CASE WHEN paid+v_amount=total THEN 'Paid' ELSE 'Partially Paid' END,revision=revision+1 WHERE id=p_id;
 INSERT INTO invoice_events_061(invoice_id,actor_id,action,detail) VALUES(p_id,auth.uid(),'Payment recorded',jsonb_build_object('amount',v_amount,'currency',inv.currency,'date',p_date,'reference',ref,'mode',p_mode));
 PERFORM invoice_sync_projects_061(p_id);
 RETURN invoice_get_061(p_id);
END $$;

CREATE OR REPLACE FUNCTION public.invoice_delete_064(p_id uuid,p_revision integer,p_confirmation text,p_delete_receipts boolean DEFAULT false) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE inv client_invoices%ROWTYPE; scoops uuid[]; projects_affected uuid[];
BEGIN
 PERFORM invoice_assert_access_061(true,true);
 SELECT * INTO inv FROM client_invoices WHERE id=p_id FOR UPDATE;
 IF inv.id IS NULL OR inv.revision IS DISTINCT FROM p_revision THEN RAISE EXCEPTION 'Invoice changed or no longer exists. Reopen it before deleting'; END IF;
 IF p_confirmation IS DISTINCT FROM COALESCE(inv.invoice_number,inv.draft_reference) THEN RAISE EXCEPTION 'Type the exact invoice number or draft reference to confirm deletion'; END IF;
 IF EXISTS(SELECT 1 FROM payments WHERE client_invoice_id=p_id) AND p_delete_receipts IS DISTINCT FROM true THEN RAISE EXCEPTION 'Confirm removal of this invoice’s recorded payments'; END IF;
 SELECT array_agg(DISTINCT scoop_id),array_agg(DISTINCT project_id) INTO scoops,projects_affected FROM client_invoice_lines WHERE invoice_id=p_id;
 PERFORM id FROM project_scoops WHERE id=ANY(scoops) ORDER BY id FOR UPDATE;
 PERFORM set_config('retodo.invoice_delete_064',p_id::text,true);
 DELETE FROM invoice_scoop_allocations_061 WHERE invoice_id=p_id;
 DELETE FROM invoice_numbers_062 WHERE invoice_id=p_id;
 DELETE FROM invoice_revisions_062 WHERE invoice_id=p_id;
 DELETE FROM invoice_events_061 WHERE invoice_id=p_id;
 DELETE FROM payments WHERE client_invoice_id=p_id;
 DELETE FROM client_invoice_lines WHERE invoice_id=p_id;
 DELETE FROM client_invoices WHERE id=p_id;
 -- Scoops retain their approved operational status during billing. Explicitly restore
 -- only released billed Scoops; deleting an unissued draft does not change operations.
 UPDATE project_scoops s SET financial_status='Not Invoiced',
  status=CASE WHEN inv.invoice_number IS NOT NULL THEN 'Approved' ELSE s.status END,
  status_manual=CASE WHEN inv.invoice_number IS NOT NULL THEN true ELSE s.status_manual END
 WHERE s.id=ANY(scoops) AND NOT EXISTS(SELECT 1 FROM invoice_scoop_allocations_061 a WHERE a.scoop_id=s.id);
 -- Recompute affected project finance without changing unrelated Projects or Jobs.
 WITH states AS (
  SELECT s.project_id,count(*) total,count(*) FILTER(WHERE i.status IN ('Issued','Partially Paid','Paid','Overdue','Disputed')) billed,
   count(*) FILTER(WHERE i.status='Paid') fully_paid,count(*) FILTER(WHERE i.status IN ('Partially Paid','Paid')) any_paid
  FROM project_scoops s LEFT JOIN invoice_scoop_allocations_061 a ON a.scoop_id=s.id LEFT JOIN client_invoices i ON i.id=a.invoice_id
  WHERE s.active AND s.project_id=ANY(projects_affected) GROUP BY s.project_id)
 UPDATE projects p SET financial_status=CASE WHEN st.fully_paid=st.total THEN 'Paid' WHEN st.billed=st.total AND st.any_paid>0 THEN 'Partially Paid' WHEN st.billed=st.total THEN 'Invoiced' ELSE 'Ready to Invoice' END
 FROM states st WHERE p.id=st.project_id AND p.financial_status IN ('Not Ready','Ready to Invoice','Invoiced','Partially Paid','Paid');
 -- Release number ownership without rewinding the global next-number counter.
 PERFORM set_config('retodo.invoice_delete_064','',true);
END $$;
REVOKE ALL ON FUNCTION public.invoice_receive_payment_064(uuid,integer,text,numeric,date,text,uuid), public.invoice_delete_064(uuid,integer,text,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.invoice_receive_payment_064(uuid,integer,text,numeric,date,text,uuid), public.invoice_delete_064(uuid,integer,text,boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.invoice_immutable_061() FROM PUBLIC,anon,authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;

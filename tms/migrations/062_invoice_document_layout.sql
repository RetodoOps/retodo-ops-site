-- Update 066. Forward-only; requires Update 065 migration 061.
BEGIN;
ALTER TABLE public.client_invoices ADD COLUMN IF NOT EXISTS document_details_066 jsonb NOT NULL DEFAULT '{}'::jsonb;

CREATE OR REPLACE FUNCTION public.invoice_document_validate_066(p_details jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path=public AS $$
DECLARE k text; v jsonb; d date;
BEGIN
 IF p_details IS NULL OR jsonb_typeof(p_details)<>'object' THEN RAISE EXCEPTION 'Document details must be an object'; END IF;
 FOR k,v IN SELECT * FROM jsonb_each(p_details) LOOP
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

CREATE OR REPLACE FUNCTION public.invoice_save_066(p_payload jsonb,p_id uuid DEFAULT NULL,p_revision integer DEFAULT NULL) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE result_id uuid; details jsonb;
BEGIN
 PERFORM invoice_assert_access_061(true);
 IF p_payload ? 'document_details_066' THEN details:=invoice_document_validate_066(p_payload->'document_details_066'); END IF;
 result_id:=invoice_save_061(p_payload,p_id,p_revision);
 IF details IS NOT NULL THEN UPDATE client_invoices SET document_details_066=details WHERE id=result_id; END IF;
 RETURN result_id;
END $$;

CREATE OR REPLACE FUNCTION public.invoice_revise_066(p_id uuid,p_revision integer,p_payload jsonb,p_reason text,p_use_current_issuer_bg boolean DEFAULT false) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE inv client_invoices%ROWTYPE; issuer jsonb; bg jsonb; details jsonb;
BEGIN
 PERFORM invoice_assert_access_061(true,true);
 SELECT * INTO inv FROM client_invoices WHERE id=p_id FOR UPDATE;
 IF p_payload ? 'document_details_066' THEN details:=invoice_document_validate_066(p_payload->'document_details_066'); END IF;
 IF p_use_current_issuer_bg THEN
  SELECT s.issuer INTO issuer FROM invoice_settings_061 s WHERE id FOR UPDATE;
  IF nullif(btrim(issuer->>'registration_number'),'') IS NULL OR btrim(issuer->>'registration_number') IS DISTINCT FROM btrim(inv.issuer_snapshot->>'registration_number') THEN RAISE EXCEPTION 'Bulgarian issuer details must belong to the same registration number'; END IF;
  IF nullif(btrim(issuer->>'legal_name_bg'),'') IS NULL OR nullif(btrim(issuer->>'address_bg'),'') IS NULL THEN RAISE EXCEPTION 'Configure Bulgarian issuer name and address first'; END IF;
  bg:=jsonb_build_object('legal_name_bg',issuer->>'legal_name_bg','address_bg',issuer->>'address_bg','bank_bg',issuer->>'bank_bg','prepared_by_bg',issuer->>'prepared_by_bg');
 END IF;
 -- Existing RPC records the complete previous snapshot, checks revision, currency,
 -- number ownership and payments, then restores the original English issuer facts.
 PERFORM invoice_revise_062(p_id,p_revision,p_payload,p_reason);
 PERFORM set_config('retodo.invoice_revision_062',p_id::text,true);
 UPDATE client_invoices SET document_details_066=COALESCE(details,document_details_066),issuer_snapshot=CASE WHEN bg IS NULL THEN issuer_snapshot ELSE issuer_snapshot||bg END WHERE id=p_id;
 PERFORM set_config('retodo.invoice_revision_062','',true);
 INSERT INTO invoice_events_061(invoice_id,actor_id,action,detail) VALUES(p_id,auth.uid(),'Invoice document details revised',jsonb_build_object('reason',btrim(p_reason),'copied_bulgarian_issuer',COALESCE(p_use_current_issuer_bg,false)));
 RETURN invoice_get_061(p_id);
END $$;
REVOKE ALL ON FUNCTION public.invoice_document_validate_066(jsonb) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.invoice_save_066(jsonb,uuid,integer),public.invoice_revise_066(uuid,integer,jsonb,text,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.invoice_save_066(jsonb,uuid,integer),public.invoice_revise_066(uuid,integer,jsonb,text,boolean) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;

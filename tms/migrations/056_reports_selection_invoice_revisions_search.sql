-- Update 062. Run after 055. Forward-only changes; issued edits keep prior snapshots.
BEGIN;
ALTER TABLE public.project_scoops ADD COLUMN IF NOT EXISTS financial_status text NOT NULL DEFAULT 'Not Invoiced' CHECK(financial_status IN ('Not Invoiced','Invoiced','Paid'));
CREATE OR REPLACE FUNCTION public.protect_scoop_financial_state_062() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=public AS $$
BEGIN
 IF current_user IN ('authenticated','anon') AND NEW.financial_status IS DISTINCT FROM OLD.financial_status THEN RAISE EXCEPTION 'Scoop financial status is managed by invoices'; END IF;
 RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS scoop_financial_state_guard_062 ON public.project_scoops;
CREATE TRIGGER scoop_financial_state_guard_062 BEFORE UPDATE OF financial_status ON public.project_scoops FOR EACH ROW EXECUTE FUNCTION public.protect_scoop_financial_state_062();
REVOKE ALL ON FUNCTION public.protect_scoop_financial_state_062() FROM PUBLIC,anon,authenticated;
CREATE TABLE IF NOT EXISTS public.invoice_revisions_062(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),invoice_id uuid NOT NULL REFERENCES public.client_invoices(id),
 revision integer NOT NULL,reason text NOT NULL,actor_id uuid NOT NULL REFERENCES public.profiles(id),
 snapshot jsonb NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),UNIQUE(invoice_id,revision)
);
ALTER TABLE public.invoice_revisions_062 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.invoice_revisions_062 FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.invoice_revisions_062 TO authenticated;
DROP POLICY IF EXISTS company_read ON public.invoice_revisions_062;
CREATE POLICY company_read ON public.invoice_revisions_062 FOR SELECT TO authenticated USING(is_company_user() AND current_user_access_enabled());

CREATE OR REPLACE FUNCTION public.sync_scoop_invoice_state_062() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
 UPDATE project_scoops s SET financial_status=COALESCE((SELECT CASE WHEN i.status='Paid' THEN 'Paid' ELSE 'Invoiced' END
 FROM invoice_scoop_allocations_061 a JOIN client_invoices i ON i.id=a.invoice_id WHERE a.scoop_id=s.id
 AND i.status IN ('Issued','Partially Paid','Paid','Overdue','Disputed')),'Not Invoiced')
 WHERE s.id IN (SELECT scoop_id FROM client_invoice_lines WHERE invoice_id=NEW.id AND scoop_id IS NOT NULL);
 RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS invoice_scoop_state_062 ON client_invoices;
CREATE TRIGGER invoice_scoop_state_062 AFTER UPDATE OF status ON client_invoices FOR EACH ROW EXECUTE FUNCTION sync_scoop_invoice_state_062();
-- Reconcile already-issued 061 Scoops too; source operational approval is preserved.
UPDATE project_scoops s SET financial_status=CASE WHEN i.status='Paid' THEN 'Paid' ELSE 'Invoiced' END
FROM invoice_scoop_allocations_061 a JOIN client_invoices i ON i.id=a.invoice_id WHERE s.id=a.scoop_id AND i.status IN ('Issued','Partially Paid','Paid','Overdue','Disputed');

CREATE OR REPLACE FUNCTION public.report_bulk_status_062(p_type text,p_ids uuid[],p_status text) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE n integer;
BEGIN
 PERFORM invoice_assert_access_061(true);
 IF p_type IS NULL OR p_type NOT IN ('projects','margin','jobs') OR p_ids IS NULL OR cardinality(p_ids) NOT BETWEEN 1 AND 500 OR array_position(p_ids,NULL) IS NOT NULL THEN RAISE EXCEPTION 'Select between 1 and 500 records'; END IF;
 IF p_status IS NULL OR (p_type='jobs' AND p_status NOT IN ('Unassigned','Assigned','In Progress','Delivered','Revision Required','Approved','Cancelled')) OR (p_type<>'jobs' AND p_status NOT IN ('Assign','Ongoing','Ready for QA','Waiting','Ready to Deliver','Delivered to Client','Approved','Cancelled')) THEN RAISE EXCEPTION 'Choose an operational status. Invoiced/Paid come from invoices'; END IF;
 IF p_type='jobs' THEN
  PERFORM id FROM project_jobs WHERE id=ANY(p_ids) ORDER BY id FOR UPDATE;
  SELECT count(*) INTO n FROM project_jobs WHERE id=ANY(p_ids);
 ELSE
  PERFORM id FROM project_scoops WHERE id=ANY(p_ids) ORDER BY id FOR UPDATE;
  SELECT count(*) INTO n FROM project_scoops WHERE id=ANY(p_ids);
 END IF;
 IF n<>(SELECT count(DISTINCT x) FROM unnest(p_ids)x) THEN RAISE EXCEPTION 'One or more selected records no longer exist. Refresh'; END IF;
 IF p_type='jobs' THEN UPDATE project_jobs SET status=p_status WHERE id=ANY(p_ids);
 ELSE
  IF EXISTS(SELECT 1 FROM project_scoops WHERE id=ANY(p_ids) AND financial_status IN ('Invoiced','Paid')) THEN RAISE EXCEPTION 'Invoiced/Paid Scoops retain their operational approval. Revise the invoice to change its contents'; END IF;
  UPDATE project_scoops SET status=p_status,status_manual=true WHERE id=ANY(p_ids);
 END IF;
 RETURN n;
END $$;

-- Retain ownership of every official number, including numbers changed by a revision.
CREATE TABLE IF NOT EXISTS public.invoice_numbers_062(number text PRIMARY KEY,invoice_id uuid NOT NULL REFERENCES public.client_invoices(id));
ALTER TABLE public.invoice_numbers_062 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.invoice_numbers_062 FROM PUBLIC,anon,authenticated;
INSERT INTO invoice_numbers_062 SELECT invoice_number,id FROM client_invoices WHERE invoice_number IS NOT NULL ON CONFLICT DO NOTHING;
CREATE OR REPLACE FUNCTION public.reserve_invoice_number_062() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
 IF NEW.invoice_number IS NOT NULL THEN
  INSERT INTO invoice_numbers_062 VALUES(NEW.invoice_number,NEW.id) ON CONFLICT DO NOTHING;
  IF EXISTS(SELECT 1 FROM invoice_numbers_062 WHERE number=NEW.invoice_number AND invoice_id<>NEW.id) THEN RAISE EXCEPTION 'Invoice number already belongs to another invoice or its revision'; END IF;
 END IF;
 RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS invoice_number_reserve_062 ON client_invoices;
CREATE TRIGGER invoice_number_reserve_062 AFTER INSERT OR UPDATE OF invoice_number ON client_invoices FOR EACH ROW EXECUTE FUNCTION reserve_invoice_number_062();
REVOKE ALL ON FUNCTION reserve_invoice_number_062() FROM PUBLIC,anon,authenticated;

-- Narrow audited revision exception, usable only by admin through guarded RPC writes.
-- Existing table mutation grants remain revoked. All other financial guards are retained.
DO $$ DECLARE def text; sig text; BEGIN
 FOREACH sig IN ARRAY ARRAY['public.enforce_admin_only_changes()','public.invoice_immutable_061()'] LOOP
  SELECT pg_get_functiondef(to_regprocedure(sig)) INTO def;
  IF position('retodo.invoice_revision_062' IN def)=0 THEN
   def:=regexp_replace(def,E'BEGIN\\n',E'BEGIN\n    IF TG_TABLE_NAME IN (\'client_invoices\',\'client_invoice_lines\') AND public.is_admin() AND nullif(current_setting(\'retodo.invoice_revision_062\',true),\'\') = COALESCE(to_jsonb(NEW)->>\'invoice_id\',to_jsonb(NEW)->>\'id\',to_jsonb(OLD)->>\'invoice_id\',to_jsonb(OLD)->>\'id\') THEN IF TG_OP=\'DELETE\' THEN RETURN OLD; ELSE RETURN NEW; END IF; END IF;\n');
   EXECUTE def;
  END IF;
 END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.invoice_revise_062(p_id uuid,p_revision integer,p_payload jsonb,p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE inv client_invoices%ROWTYPE; before_snapshot jsonb; paid numeric; revised client_invoices%ROWTYPE; n bigint; old_scoops uuid[];
BEGIN
 PERFORM invoice_assert_access_061(true,true);
 SELECT * INTO inv FROM client_invoices WHERE id=p_id FOR UPDATE;
 IF inv.id IS NULL OR inv.status NOT IN ('Issued','Partially Paid','Paid','Overdue','Disputed') OR inv.revision IS DISTINCT FROM p_revision THEN RAISE EXCEPTION 'Reopen the current official invoice before editing'; END IF;
 IF NULLIF(btrim(p_reason),'') IS NULL THEN RAISE EXCEPTION 'Enter a revision reason'; END IF;
 IF p_payload->>'currency' IS DISTINCT FROM inv.currency THEN RAISE EXCEPTION 'Keep the issued invoice currency'; END IF;
 SELECT COALESCE(sum(amount),0) INTO paid FROM payments WHERE client_invoice_id=p_id;
 SELECT array_agg(scoop_id) INTO old_scoops FROM client_invoice_lines WHERE invoice_id=p_id AND scoop_id IS NOT NULL;
 before_snapshot:=invoice_get_061(p_id);
 INSERT INTO invoice_revisions_062(invoice_id,revision,reason,actor_id,snapshot) VALUES(p_id,inv.revision,btrim(p_reason),auth.uid(),before_snapshot);
 PERFORM set_config('retodo.invoice_revision_062',p_id::text,true);
 UPDATE client_invoices SET status='Draft' WHERE id=p_id;
 PERFORM invoice_save_061(p_payload,p_id,p_revision);
 SELECT * INTO revised FROM client_invoices WHERE id=p_id;
 IF revised.total<paid THEN RAISE EXCEPTION 'Revised total cannot be less than recorded payments'; END IF;
 IF revised.billing_entity_id IS NULL OR revised.tax_note IS NULL OR revised.payment_terms_days IS NULL OR NOT EXISTS(SELECT 1 FROM client_invoice_lines WHERE invoice_id=p_id) THEN RAISE EXCEPTION 'Official invoice needs rows, billing entity, payment terms and tax basis'; END IF;
 IF NOT EXISTS(SELECT 1 FROM client_billing_entities b WHERE b.id=revised.billing_entity_id AND b.client_id=inv.client_id AND b.active AND b.legal_name<>'' AND b.address_line_1<>'' AND b.country_code<>'') THEN RAISE EXCEPTION 'Choose a complete active billing entity'; END IF;
 n:=COALESCE(revised.proposed_number,inv.invoice_number)::bigint;
 PERFORM id FROM invoice_settings_061 WHERE id FOR UPDATE;
 IF EXISTS(SELECT 1 FROM client_invoices WHERE invoice_number=lpad(n::text,10,'0') AND id<>p_id) THEN RAISE EXCEPTION 'Invoice number already exists'; END IF;
 UPDATE client_invoices SET invoice_number=lpad(n::text,10,'0'),status=CASE WHEN paid>0 AND total=paid THEN 'Paid' WHEN paid>0 THEN 'Partially Paid' ELSE 'Issued' END,
 issuer_snapshot=inv.issuer_snapshot,billing_snapshot=(SELECT to_jsonb(b) FROM client_billing_entities b WHERE b.id=revised.billing_entity_id),issued_by=inv.issued_by,issued_at=inv.issued_at WHERE id=p_id;
 IF lpad(n::text,10,'0')<>inv.invoice_number THEN UPDATE invoice_settings_061 SET next_number=CASE WHEN n<9999999999 THEN n+1 END,updated_at=now() WHERE id; END IF;
 -- Removed Scoops are released, including when an invoice with payments is revised.
 UPDATE project_scoops SET financial_status='Not Invoiced' WHERE id=ANY(old_scoops) AND NOT EXISTS(SELECT 1 FROM invoice_scoop_allocations_061 a WHERE a.scoop_id=project_scoops.id);
 UPDATE projects p SET financial_status='Ready to Invoice' WHERE p.id IN(SELECT project_id FROM project_scoops WHERE id=ANY(old_scoops)) AND p.financial_status IN ('Invoiced','Partially Paid','Paid') AND EXISTS(SELECT 1 FROM project_scoops s WHERE s.project_id=p.id AND s.active AND s.financial_status='Not Invoiced');
 PERFORM invoice_sync_projects_061(p_id);
 INSERT INTO invoice_events_061(invoice_id,actor_id,action,detail) VALUES(p_id,auth.uid(),'Official invoice revised',jsonb_build_object('reason',btrim(p_reason),'previous_revision',p_revision,'previous_total',inv.total,'total',revised.total));
 PERFORM set_config('retodo.invoice_revision_062','',true);
 RETURN invoice_get_061(p_id);
END $$;

CREATE OR REPLACE FUNCTION public.tms_search_062(p_query text,p_limit integer DEFAULT 30) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public AS $$
DECLARE q text; result jsonb;
BEGIN
 PERFORM invoice_assert_access_061();
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'Invalid search limit'; END IF;
 IF length(btrim(COALESCE(p_query,'')))<2 THEN RETURN '[]'::jsonb; END IF;
 q:='%'||replace(replace(replace(btrim(p_query),'\','\\'),'%','\%'),'_','\_')||'%';
 WITH matches AS (
 SELECT 'Scoop' kind,s.id,s.scoop_number label,concat_ws(' · ',p.display_name,p.project_number,p.po_number,CASE WHEN s.financial_status<>'Not Invoiced' THEN s.financial_status ELSE s.status END) meta,'project.html?id='||s.project_id||'&scoop='||s.id href,0 priority
 FROM project_scoops s JOIN projects p ON p.id=s.project_id WHERE concat_ws(' ',s.scoop_number,p.display_name,p.project_number,p.po_number) ILIKE q
 UNION ALL SELECT 'Project',id,COALESCE(display_name,project_number),concat_ws(' · ',project_number,po_number,status),'project.html?id='||id,1 FROM projects WHERE concat_ws(' ',display_name,project_number,client_reference,po_number) ILIKE q
 UNION ALL SELECT 'Job',j.id,j.job_number,concat_ws(' · ',p.project_number,j.service_type,j.status),'job.html?id='||j.id,2 FROM project_jobs j JOIN projects p ON p.id=j.project_id WHERE concat_ws(' ',j.job_number,p.project_number,p.display_name) ILIKE q
 UNION ALL SELECT 'Client',id,name,'Client','client.html?id='||id,3 FROM clients WHERE name ILIKE q
 UNION ALL SELECT 'Resource',id,COALESCE(legal_name,company_name,internal_number),internal_number,'resource.html?id='||id,4 FROM resources WHERE concat_ws(' ',legal_name,company_name,internal_number) ILIKE q
 UNION ALL SELECT 'Invoice',i.id,COALESCE(i.invoice_number,i.draft_reference),concat_ws(' · ',c.name,i.status),'invoice.html?type=client&id='||i.id,5 FROM client_invoices i JOIN clients c ON c.id=i.client_id WHERE concat_ws(' ',i.invoice_number,i.draft_reference,c.name) ILIKE q
 ) SELECT COALESCE(jsonb_agg(to_jsonb(r)-'priority'),'[]') INTO result FROM (SELECT * FROM matches ORDER BY CASE WHEN lower(label)=lower(btrim(p_query)) THEN -1 ELSE priority END,label,id LIMIT p_limit)r;
 RETURN result;
END $$;
-- Shared access assertion is safe to invoke directly: it returns no data and always checks the caller.
GRANT EXECUTE ON FUNCTION invoice_assert_access_061(boolean,boolean) TO authenticated;
REVOKE ALL ON FUNCTION sync_scoop_invoice_state_062(),report_bulk_status_062(text,uuid[],text),invoice_revise_062(uuid,integer,jsonb,text),tms_search_062(text,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION report_bulk_status_062(text,uuid[],text),invoice_revise_062(uuid,integer,jsonb,text),tms_search_062(text,integer) TO authenticated;
-- Preserve 061 report calculations, exposing the derived financial status for filters and exports.
DO $$ DECLARE def text; BEGIN
 SELECT pg_get_functiondef('public.tms_report_061(text,jsonb,integer,integer,text,boolean)'::regprocedure) INTO def;
 def:=replace(def,'s.scoop_number name, s.status,','s.scoop_number name, CASE WHEN s.financial_status IN (''Invoiced'',''Paid'') THEN s.financial_status ELSE s.status END status,');EXECUTE def;
END $$;
NOTIFY pgrst,'reload schema';
COMMIT;

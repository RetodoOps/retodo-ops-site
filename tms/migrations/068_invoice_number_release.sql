-- Update 071: a corrected number belongs only to the current invoice.
-- Historical numbers remain in immutable revision snapshots and issue events.
BEGIN;
LOCK TABLE public.client_invoices, public.invoice_numbers_062 IN SHARE ROW EXCLUSIVE MODE;

-- Repair existing stale reservations (including the reported 20 -> 21 case).
-- Keep every number still on an invoice, regardless of its lifecycle status.
DELETE FROM public.invoice_numbers_062 r
WHERE NOT EXISTS (
 SELECT 1 FROM public.client_invoices i
 WHERE i.id=r.invoice_id AND i.invoice_number=r.number
);
INSERT INTO public.invoice_numbers_062(number,invoice_id)
SELECT invoice_number,id FROM public.client_invoices WHERE invoice_number IS NOT NULL
ON CONFLICT (number) DO NOTHING;

CREATE OR REPLACE FUNCTION public.reserve_invoice_number_062() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
 IF NEW.invoice_number IS NOT NULL THEN
  INSERT INTO invoice_numbers_062(number,invoice_id) VALUES(NEW.invoice_number,NEW.id) ON CONFLICT DO NOTHING;
  IF EXISTS(SELECT 1 FROM invoice_numbers_062 WHERE number=NEW.invoice_number AND invoice_id<>NEW.id) THEN
   RAISE EXCEPTION 'Invoice number already belongs to another invoice';
  END IF;
 END IF;
 -- Reserve the replacement before releasing the old number, in the same transaction.
 -- A failed revision rolls back both operations together with the invoice changes.
 IF TG_OP='UPDATE' THEN
  IF OLD.invoice_number IS DISTINCT FROM NEW.invoice_number THEN
   DELETE FROM invoice_numbers_062 WHERE number=OLD.invoice_number AND invoice_id=NEW.id;
  END IF;
 END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.reserve_invoice_number_062() FROM PUBLIC,anon,authenticated;
-- After issuing a freed earlier number, suggest the next unused current number.
-- Candidate gaps avoid scanning all ten billion possible numbers.
CREATE OR REPLACE FUNCTION public.invoice_next_free_number_071(p_start bigint) RETURNS bigint
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
 SELECT min(candidate) FROM (
  SELECT p_start candidate
  UNION
  SELECT invoice_number::bigint+1 FROM client_invoices
  WHERE invoice_number ~ '^[0-9]{10}$' AND invoice_number::bigint>=p_start
 ) candidates
 WHERE candidate BETWEEN 1 AND 9999999999
 AND NOT EXISTS(SELECT 1 FROM client_invoices i WHERE i.invoice_number=lpad(candidate::text,10,'0'))
$$;
REVOKE ALL ON FUNCTION public.invoice_next_free_number_071(bigint) FROM PUBLIC,anon,authenticated;

-- Preserve the existing guarded RPC bodies; change only next-number selection.
DO $$ DECLARE signature text; definition text; old_expression text := 'CASE WHEN n<9999999999 THEN n+1 END';
BEGIN
 FOREACH signature IN ARRAY ARRAY['public.invoice_issue_061(uuid,integer)','public.invoice_revise_062(uuid,integer,jsonb,text)'] LOOP
  SELECT pg_get_functiondef(to_regprocedure(signature)) INTO definition;
  IF definition IS NULL THEN RAISE EXCEPTION 'Missing prerequisite %',signature; END IF;
  IF position('public.invoice_next_free_number_071(n+1)' IN definition)=0 THEN
   IF position(old_expression IN definition)=0 THEN RAISE EXCEPTION 'Unexpected numbering function body: %',signature; END IF;
   EXECUTE replace(definition,old_expression,'public.invoice_next_free_number_071(n+1)');
  END IF;
 END LOOP;
END $$;
COMMIT;

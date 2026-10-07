-- Update 063B. Correct the Sales worker's conversation polling alias.
-- Requires Update 063 / migration 057. Preserves all rows, approvals and settings.
-- The only worker-logic change is the qualified alias in the threads branch.
BEGIN;

DO $$ BEGIN
 IF to_regprocedure('public.sales_system_063(text,jsonb)') IS NULL THEN
  RAISE EXCEPTION 'Install Update 063 / migration 057 before this correction';
 END IF;
END $$;

CREATE OR REPLACE FUNCTION public.sales_system_063(p_action text,p_data jsonb DEFAULT '{}') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE s sales_settings%ROWTYPE; r sales_runtime%ROWTYPE; m sales_messages%ROWTYPE; c sales_conversations%ROWTYPE;
 j sales_ai_jobs%ROWTYPE; item jsonb; contact jsonb; v_prospect_id uuid; imported integer:=0; v_id uuid; v_lease uuid; v_cost numeric; used numeric; v_state text; snap jsonb; initial_at timestamptz; result jsonb;
BEGIN
 IF auth.role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'Server access required' USING ERRCODE='42501'; END IF;
 SELECT * INTO s FROM sales_settings WHERE id FOR UPDATE;
 IF p_action='config' THEN RETURN to_jsonb(s);
 ELSIF p_action='lock' THEN
  SELECT * INTO r FROM sales_runtime WHERE id FOR UPDATE;
  IF r.lease_until>now() THEN RETURN NULL; END IF;
  v_lease:=gen_random_uuid(); UPDATE sales_runtime SET lease_id=v_lease,lease_until=now()+interval '5 minutes',worker_at=now(),worker_error=NULL WHERE id;
  -- A send whose process disappeared is ambiguous; it is never re-queued.
  UPDATE sales_messages SET state='uncertain',last_error='Worker ended during send; reconcile with Gmail before further action' WHERE state='sending' AND lease_until<now();
  UPDATE sales_messages SET state='approved',lease_id=NULL,lease_until=NULL WHERE state='checking' AND lease_until<now();
  UPDATE sales_ai_jobs SET state='uncertain',error='Worker ended; reserved cost retained. No automatic retry.' WHERE state='running' AND created_at<now()-interval '10 minutes';
  RETURN jsonb_build_object('lease_id',v_lease);
 ELSIF p_action='unlock' THEN UPDATE sales_runtime SET lease_until=now(),worker_error=left(p_data->>'error',500) WHERE id AND lease_id=(p_data->>'lease_id')::uuid; RETURN '{}'::jsonb;
 ELSIF p_action='mailbox' THEN
  UPDATE sales_runtime SET mailbox_checked_at=now(),mailbox_ok=coalesce((p_data->>'ok')::boolean,false),mailbox_error=left(p_data->>'error',500) WHERE id;
 ELSIF p_action='threads' THEN
  -- Use an alias distinct from the local conversation record c.
  RETURN coalesce((SELECT jsonb_agg(thread_row) FROM (
   SELECT thread_conversation.*
   FROM public.sales_conversations AS thread_conversation
   WHERE thread_conversation.thread_id IS NOT NULL
    AND thread_conversation.state NOT IN('closed','suppressed')
   ORDER BY thread_conversation.synced_at NULLS FIRST LIMIT 20
  ) AS thread_row),'[]'::jsonb);
 ELSIF p_action='sync' THEN
  SELECT * INTO c FROM sales_conversations WHERE id=(p_data->>'conversation_id')::uuid FOR UPDATE;
  IF c.id IS NULL THEN RAISE EXCEPTION 'Conversation missing'; END IF;
  IF p_data->>'error' IS NOT NULL THEN
   UPDATE sales_conversations SET last_sync_error=left(p_data->>'error',500) WHERE id=c.id; RETURN '{}'::jsonb;
  END IF;
  FOR item IN SELECT value FROM jsonb_array_elements(coalesce(p_data->'messages','[]')) LOOP
   IF EXISTS(SELECT 1 FROM sales_messages WHERE gmail_id=item->>'gmail_id' OR rfc_id=item->>'rfc_id') THEN CONTINUE; END IF;
   INSERT INTO sales_messages(conversation_id,direction,kind,step,subject,body,state,gmail_id,rfc_id,sent_at)
   VALUES(c.id,CASE WHEN item->>'classification'='outbound' THEN 'outbound' ELSE 'inbound' END,'external',
    (SELECT coalesce(max(step),0)+1 FROM sales_messages WHERE conversation_id=c.id),left(coalesce(nullif(item->>'subject',''),'(No subject)'),200),left(coalesce(nullif(item->>'body',''),'(No text body)'),20000),
    CASE WHEN item->>'classification'='outbound' THEN 'sent' ELSE 'received' END,item->>'gmail_id',nullif(item->>'rfc_id',''),(item->>'sent_at')::timestamptz);
   v_state:=CASE WHEN item->>'classification'='optout' THEN 'suppressed' WHEN item->>'classification' IN('outbound','ooo','bounce') THEN 'paused' ELSE 'replied' END;
   UPDATE sales_conversations SET state=CASE WHEN state IN('suppressed','closed') THEN state ELSE v_state END,pause_reason='Mailbox: '||(item->>'classification'),updated_at=now() WHERE id=c.id;
   UPDATE sales_messages SET state='cancelled',version=version+1,last_error='Stopped after mailbox activity; review before any new message' WHERE conversation_id=c.id AND state IN('draft','approved','checking');
   IF item->>'classification' IN('optout','bounce') THEN INSERT INTO sales_suppressions(target,reason) VALUES(c.recipient,'Mailbox: '||(item->>'classification')) ON CONFLICT DO NOTHING; END IF;
   UPDATE sales_prospects SET stage=CASE WHEN v_state='suppressed' THEN 'suppressed' WHEN v_state='replied' THEN 'replied' ELSE stage END,updated_at=now(),version=version+1 WHERE id=c.prospect_id;
   INSERT INTO sales_events(conversation_id,event,detail) VALUES(c.id,'mailbox_activity',jsonb_build_object('classification',item->>'classification','gmail_id',item->>'gmail_id'));
  END LOOP;
  UPDATE sales_conversations SET synced_at=now(),last_sync_error=NULL WHERE id=c.id;
 ELSIF p_action='uncertain' THEN
  RETURN coalesce((SELECT jsonb_agg(x) FROM(SELECT qm.*,qc.recipient,qc.thread_id FROM sales_messages qm JOIN sales_conversations qc ON qc.id=qm.conversation_id WHERE qm.state='uncertain' ORDER BY qm.created_at LIMIT 10)x),'[]');
 ELSIF p_action='claim' THEN
  IF NOT s.sending_enabled OR NOT EXISTS(SELECT 1 FROM sales_runtime WHERE id AND mailbox_ok AND mailbox_checked_at>now()-interval '5 minutes') THEN RETURN NULL; END IF;
  IF (SELECT count(*) FROM sales_messages WHERE direction='outbound' AND state IN('sent','sending','uncertain') AND coalesce(sent_at,attempted_at)>date_trunc('day',now() AT TIME ZONE 'Europe/Sofia') AT TIME ZONE 'Europe/Sofia')>=s.daily_limit THEN RETURN NULL; END IF;
  SELECT m1.* INTO m FROM sales_messages m1 JOIN sales_conversations c1 ON c1.id=m1.conversation_id JOIN sales_contacts k ON k.id=c1.contact_id JOIN sales_prospects p ON p.id=c1.prospect_id
   WHERE m1.state='approved' AND m1.due_at<=now() AND (c1.state='active' OR (m1.kind='reply' AND c1.state IN('replied','paused')))
   AND NOT public.sales_blocked_063(c1.recipient,p.domain) AND p.stage<>'suppressed' AND k.verified_at>now()-interval '90 days' AND k.email=c1.recipient
   AND NOT EXISTS(SELECT 1 FROM sales_messages other WHERE other.conversation_id=c1.id AND other.state IN('checking','sending','uncertain'))
   AND (m1.kind IN('initial','reply') OR EXISTS(SELECT 1 FROM sales_messages first WHERE first.conversation_id=c1.id AND first.kind='initial' AND first.state='sent' AND public.sales_business_due_063(first.sent_at,m1.delay_days)<=now()))
   AND NOT EXISTS(SELECT 1 FROM sales_messages earlier WHERE earlier.conversation_id=c1.id AND earlier.step<m1.step AND earlier.state IN('draft','approved','checking','sending','uncertain'))
   AND (m1.kind<>'followup' OR NOT EXISTS(SELECT 1 FROM sales_messages today WHERE today.conversation_id=c1.id AND today.direction='outbound' AND today.sent_at>now()-interval '1 day'))
   ORDER BY m1.due_at,m1.created_at FOR UPDATE OF m1 SKIP LOCKED LIMIT 1;
  IF m.id IS NULL THEN RETURN NULL; END IF;
  v_lease:=gen_random_uuid();
  UPDATE sales_messages SET state='checking',lease_id=v_lease,lease_until=now()+interval '3 minutes',rfc_id=coalesce(rfc_id,'<sales.'||id||'@retodo-ops.com>') WHERE id=m.id RETURNING * INTO m;
  SELECT * INTO c FROM sales_conversations WHERE id=m.conversation_id;
  RETURN jsonb_build_object('message',to_jsonb(m),'conversation',to_jsonb(c));
 ELSIF p_action='begin_send' THEN
  SELECT * INTO m FROM sales_messages WHERE id=(p_data->>'id')::uuid FOR UPDATE;
  SELECT * INTO c FROM sales_conversations WHERE id=m.conversation_id;
  IF NOT s.sending_enabled OR m.state<>'checking' OR m.lease_id IS DISTINCT FROM (p_data->>'lease_id')::uuid OR m.lease_until<now() THEN RETURN NULL; END IF;
  IF NOT EXISTS(SELECT 1 FROM sales_runtime WHERE id AND mailbox_ok AND mailbox_checked_at>now()-interval '5 minutes') OR (c.thread_id IS NOT NULL AND (c.synced_at IS NULL OR c.synced_at<now()-interval '60 seconds' OR c.last_sync_error IS NOT NULL)) THEN RAISE EXCEPTION 'Mailbox check is stale or failed'; END IF;
  IF NOT (c.state='active' OR (m.kind='reply' AND c.state IN('replied','paused'))) OR EXISTS(SELECT 1 FROM sales_prospects p WHERE p.id=c.prospect_id AND (p.stage='suppressed' OR public.sales_blocked_063(c.recipient,p.domain))) THEN RETURN NULL; END IF;
  SELECT elem INTO snap FROM sales_approvals a CROSS JOIN LATERAL jsonb_array_elements(a.snapshot) elem WHERE a.id=m.approval_id AND elem->'message'->>'id'=m.id::text LIMIT 1;
  IF snap IS NULL OR snap->'message'->>'version'<>m.version::text OR snap->>'recipient'<>c.recipient OR snap->>'sender'<>c.sender OR snap->>'reply_to'<>c.reply_to THEN RAISE EXCEPTION 'Approval snapshot does not match'; END IF;
  IF NOT EXISTS(SELECT 1 FROM sales_contacts WHERE id=c.contact_id AND verified_at>now()-interval '90 days' AND version=(snap->>'contact_version')::integer AND email=c.recipient) THEN RAISE EXCEPTION 'Contact evidence changed'; END IF;
  UPDATE sales_messages SET state='sending',attempted_at=now() WHERE id=m.id;
  RETURN jsonb_build_object('message',to_jsonb(m),'conversation',to_jsonb(c));
 ELSIF p_action='finish_send' THEN
  SELECT * INTO m FROM sales_messages WHERE id=(p_data->>'id')::uuid FOR UPDATE;
  IF m.state NOT IN('sending','uncertain') OR m.lease_id IS DISTINCT FROM (p_data->>'lease_id')::uuid THEN RAISE EXCEPTION 'Send claim no longer matches'; END IF;
  IF nullif(p_data->>'gmail_id','') IS NULL OR nullif(p_data->>'thread_id','') IS NULL THEN RAISE EXCEPTION 'Gmail confirmation required'; END IF;
  UPDATE sales_messages SET state='sent',gmail_id=p_data->>'gmail_id',sent_at=coalesce((p_data->>'sent_at')::timestamptz,now()),last_error=NULL WHERE id=m.id;
  UPDATE sales_conversations SET thread_id=coalesce(thread_id,p_data->>'thread_id'),updated_at=now() WHERE id=m.conversation_id AND (thread_id IS NULL OR thread_id=p_data->>'thread_id');
  IF NOT FOUND THEN RAISE EXCEPTION 'Gmail thread mismatch; reconcile before continuing'; END IF;
  UPDATE sales_prospects SET stage=CASE WHEN stage IN('research','qualified') THEN 'contacted' ELSE stage END,version=version+1,updated_at=now() WHERE id=(SELECT prospect_id FROM sales_conversations WHERE id=m.conversation_id);
  INSERT INTO sales_events(conversation_id,event,detail) VALUES(m.conversation_id,'sent',jsonb_build_object('message_id',m.id,'gmail_id',p_data->>'gmail_id'));
 ELSIF p_action='send_error' THEN
  UPDATE sales_messages SET state=CASE WHEN state='sending' THEN 'uncertain' WHEN state='checking' THEN 'failed' ELSE state END,last_error=left(p_data->>'error',500) WHERE id=(p_data->>'id')::uuid AND lease_id=(p_data->>'lease_id')::uuid;
 ELSIF p_action='reserve_ai' THEN
  v_id:=(p_data->>'id')::uuid;
  SELECT * INTO j FROM sales_ai_jobs WHERE id=v_id;
  IF FOUND THEN RETURN to_jsonb(j); END IF;
  IF coalesce((p_data->>'scheduled')::boolean,false) AND (NOT s.research_enabled OR s.next_research_at>now() OR length(btrim(s.target_brief))<5) THEN RETURN NULL; END IF;
  IF s.budget_hold THEN RAISE EXCEPTION 'AI spending is on hold after a usage estimate was exceeded. Review provider pricing before resetting the hold'; END IF;
  IF EXISTS(SELECT 1 FROM sales_ai_jobs WHERE state IN('queued','running')) THEN RAISE EXCEPTION 'A research or writing task is already queued. Wait for its result'; END IF;
  v_cost:=(p_data->>'reserved_eur')::numeric;
  SELECT coalesce(sum(coalesce(cost_eur,reserved_eur)),0) INTO used FROM sales_ai_jobs WHERE accounting_month=date_trunc('month',now() AT TIME ZONE 'UTC')::date;
  IF v_cost IS NULL OR v_cost<=0 OR used+v_cost+s.recurring_eur+s.reserve_eur>s.monthly_cap THEN RAISE EXCEPTION 'Sales budget limit reached; this task has not started'; END IF;
  INSERT INTO sales_ai_jobs(id,kind,payload,reserved_eur,cost_config,created_by) VALUES(v_id,p_data->>'kind',p_data->'payload',v_cost,p_data->'cost_config',nullif(p_data->>'created_by','')::uuid) RETURNING * INTO j;
  IF coalesce((p_data->>'scheduled')::boolean,false) THEN UPDATE sales_settings SET next_research_at=now()+make_interval(days=>research_interval_days) WHERE id; END IF;
  RETURN to_jsonb(j);
 ELSIF p_action='claim_ai' THEN
  SELECT * INTO j FROM sales_ai_jobs WHERE state='queued' ORDER BY created_at FOR UPDATE SKIP LOCKED LIMIT 1;
  IF j.id IS NULL THEN RETURN NULL; END IF;
  UPDATE sales_ai_jobs SET state='running' WHERE id=j.id RETURNING * INTO j; RETURN to_jsonb(j);
 ELSIF p_action='finish_ai' THEN
  SELECT * INTO j FROM sales_ai_jobs WHERE id=(p_data->>'id')::uuid FOR UPDATE;
  IF j.id IS NULL OR j.state NOT IN('running','queued') THEN RAISE EXCEPTION 'AI task already finalized'; END IF;
  IF p_data->>'state' NOT IN('completed','failed','uncertain') THEN RAISE EXCEPTION 'Invalid AI completion state'; END IF;
  IF p_data->>'state'='completed' AND j.kind='research' THEN
   FOR item IN SELECT value FROM jsonb_array_elements(coalesce(p_data->'result'->'prospects','[]')) LOOP
    IF EXISTS(SELECT 1 FROM sales_prospects WHERE domain=lower(item->>'domain') OR regexp_replace(lower(name),'[^a-z0-9]','','g')=regexp_replace(lower(item->>'name'),'[^a-z0-9]','','g')) THEN CONTINUE; END IF;
    IF EXISTS(SELECT 1 FROM sales_suppressions WHERE target=lower(item->>'domain')) THEN CONTINUE; END IF;
    INSERT INTO sales_prospects(name,domain,country,sector,fit_note,source_url,researched_at)
    VALUES(item->>'name',lower(item->>'domain'),coalesce(item->>'country',''),coalesce(item->>'sector',''),coalesce(item->>'fit_note',''),coalesce(item->>'source_url',''),now())
    ON CONFLICT(domain) DO NOTHING RETURNING id INTO v_prospect_id;
    IF v_prospect_id IS NULL THEN CONTINUE; END IF;
    imported:=imported+1;
    FOR contact IN SELECT value FROM jsonb_array_elements(coalesce(item->'contacts','[]')) LOOP
     INSERT INTO sales_contacts(prospect_id,name,role_title,email,linkedin_url,source_url)
     VALUES(v_prospect_id,coalesce(contact->>'name',''),coalesce(contact->>'role_title',''),nullif(lower(contact->>'email'),''),coalesce(contact->>'linkedin_url',''),coalesce(contact->>'source_url','')) ON CONFLICT(email) DO NOTHING;
    END LOOP;
   END LOOP;
  ELSIF p_data->>'state'='completed' AND j.kind='materials' THEN
   INSERT INTO sales_materials(prospect_id,title,content,created_by) VALUES(nullif(j.payload->'prospect'->>'id','')::uuid,p_data->'result'->>'title',p_data->'result'->>'content',j.created_by);
  END IF;
  v_cost:=(p_data->>'cost_eur')::numeric;
  IF v_cost IS NOT NULL AND v_cost<0 THEN RAISE EXCEPTION 'Invalid usage cost'; END IF;
  UPDATE sales_ai_jobs SET state=p_data->>'state',cost_eur=v_cost,result=CASE WHEN j.kind='research' THEN coalesce(p_data->'result','{}')||jsonb_build_object('imported',imported) ELSE p_data->'result' END,error=left(p_data->>'error',500),provider_id=p_data->>'provider_id',finished_at=now() WHERE id=j.id;
  IF v_cost>j.reserved_eur THEN UPDATE sales_settings SET research_enabled=false,budget_hold=true WHERE id; INSERT INTO sales_events(event,detail) VALUES('budget_estimate_exceeded',jsonb_build_object('job_id',j.id)); END IF;
 ELSE RAISE EXCEPTION 'Unknown server action';
 END IF;
 RETURN jsonb_build_object('ok',true);
END $$;

REVOKE ALL ON FUNCTION public.sales_system_063(text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.sales_system_063(text,jsonb) TO service_role;
NOTIFY pgrst,'reload schema';
COMMIT;

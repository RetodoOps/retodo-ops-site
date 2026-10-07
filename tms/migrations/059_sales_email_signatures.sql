-- Update 064. Sales-only signatures, captured on each draft before approval.
-- Requires migrations 057 and 058. Does not retrofit existing messages or approvals.
BEGIN;
DO $$ BEGIN
 IF to_regprocedure('public.sales_command_063(text,jsonb)') IS NULL THEN
  RAISE EXCEPTION 'Install Sales migration 057 and worker correction 058 first';
 END IF;
END $$;

CREATE OR REPLACE FUNCTION public.sales_signature_valid_064(s jsonb,allow_empty boolean DEFAULT false) RETURNS boolean
LANGUAGE plpgsql IMMUTABLE SET search_path=public AS $$
DECLARE field text; lo integer; hi integer;
BEGIN
 IF s IS NULL OR jsonb_typeof(s)<>'object' THEN RETURN false; END IF;
 IF s='{}'::jsonb THEN RETURN coalesce(allow_empty,false); END IF;
 IF NOT s ?& ARRAY['version','closing','name','position','website_url','linkedin_url','confidentiality','show_logo']
  OR s - ARRAY['version','closing','name','position','website_url','linkedin_url','confidentiality','show_logo'] <> '{}'::jsonb
  OR s->'version'<>'1'::jsonb OR s->'name' IS DISTINCT FROM '"Eli Stoyanova"'::jsonb OR jsonb_typeof(s->'show_logo')<>'boolean' THEN RETURN false; END IF;
 FOR field,lo,hi IN SELECT * FROM (VALUES ('closing',1,80),('position',1,160),('website_url',1,500),('linkedin_url',0,500),('confidentiality',0,300)) limits LOOP
  IF jsonb_typeof(s->field)<>'string' OR length(s->>field) NOT BETWEEN lo AND hi OR s->>field ~ '[[:cntrl:]]' OR (lo>0 AND btrim(s->>field)='') THEN RETURN false; END IF;
 END LOOP;
 RETURN coalesce(s->>'website_url' ~ '^https://[a-z0-9][a-z0-9.-]*\.[a-z]{2,}(/[A-Za-z0-9._~/%-]*)?$'
  AND (s->>'linkedin_url'='' OR s->>'linkedin_url' ~ '^https://(www\.)?linkedin\.com/(in|company)/[A-Za-z0-9_%.-]+/?$'),false);
END $$;

ALTER TABLE public.sales_settings ADD COLUMN IF NOT EXISTS signature_enabled boolean NOT NULL DEFAULT true;
ALTER TABLE public.sales_settings ADD COLUMN IF NOT EXISTS email_signature jsonb NOT NULL DEFAULT '{"version":1,"closing":"Best Regards,","name":"Eli Stoyanova","position":"Business Development & Client Relations Coordinator","website_url":"https://retodo-ops.com/","linkedin_url":"https://www.linkedin.com/in/eli-stoyanova-667831410/","confidentiality":"This email and any attachments are confidential. If received in error, please notify the sender and delete them.","show_logo":true}'::jsonb;
ALTER TABLE public.sales_messages ADD COLUMN IF NOT EXISTS signature jsonb NOT NULL DEFAULT '{}'::jsonb;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.sales_settings'::regclass AND conname='sales_settings_signature_valid_064') THEN
  ALTER TABLE public.sales_settings ADD CONSTRAINT sales_settings_signature_valid_064 CHECK(public.sales_signature_valid_064(email_signature));
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.sales_messages'::regclass AND conname='sales_messages_signature_valid_064') THEN
  ALTER TABLE public.sales_messages ADD CONSTRAINT sales_messages_signature_valid_064 CHECK(public.sales_signature_valid_064(signature,true));
 END IF;
END $$;

-- Retain the established RPC and all non-signature actions/permission checks.
CREATE OR REPLACE FUNCTION public.sales_command_063(p_action text,p_data jsonb DEFAULT '{}') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid uuid:=auth.uid(); pid uuid; cid uuid; mid uuid; aid uuid; v integer; item jsonb; snap jsonb:='[]';
 p sales_prospects%ROWTYPE; c sales_conversations%ROWTYPE; k sales_contacts%ROWTYPE; m sales_messages%ROWTYPE;
 s sales_settings%ROWTYPE; txt text; dom text; num integer; client uuid; sig jsonb; signature_mode text;
BEGIN
 IF NOT public.sales_is_admin_063() THEN RAISE EXCEPTION 'Sales administrator access required' USING ERRCODE='42501'; END IF;
 IF octet_length(p_data::text)>2000000 THEN RAISE EXCEPTION 'Request too large'; END IF;
 -- Consistent first lock across approval, suppression, sending and reservations.
 SELECT * INTO s FROM sales_settings WHERE id FOR UPDATE;
 IF p_action='settings' THEN
  IF p_data ? 'email_signature' AND NOT public.sales_signature_valid_064(p_data->'email_signature') THEN RAISE EXCEPTION 'Invalid Sales signature. Check the text and HTTPS website/LinkedIn links'; END IF;
  IF coalesce((p_data->>'monthly_cap')::numeric,0) < coalesce((p_data->>'reserve_eur')::numeric,0) + coalesce((p_data->>'recurring_eur')::numeric,0) + (SELECT coalesce(sum(coalesce(cost_eur,reserved_eur)),0) FROM sales_ai_jobs WHERE accounting_month=date_trunc('month',now() AT TIME ZONE 'UTC')::date) THEN
   RAISE EXCEPTION 'Budget cannot fall below committed usage, outstanding reservations and the chosen allowances';
  END IF;
  IF coalesce((p_data->>'sending_enabled')::boolean,false) AND NOT EXISTS(SELECT 1 FROM sales_runtime WHERE id AND mailbox_ok AND mailbox_checked_at>now()-interval '15 minutes') THEN
   RAISE EXCEPTION 'Check the Sales mailbox connection before enabling sending';
  END IF;
  UPDATE sales_settings SET email_signature=CASE WHEN p_data ? 'email_signature' THEN p_data->'email_signature' ELSE email_signature END,signature_enabled=coalesce((p_data->>'signature_enabled')::boolean,signature_enabled),sending_enabled=coalesce((p_data->>'sending_enabled')::boolean,false),research_enabled=coalesce((p_data->>'research_enabled')::boolean,false),
   monthly_cap=(p_data->>'monthly_cap')::numeric,reserve_eur=(p_data->>'reserve_eur')::numeric,recurring_eur=(p_data->>'recurring_eur')::numeric,
   daily_limit=(p_data->>'daily_limit')::integer,approved_facts=coalesce(p_data->>'approved_facts',''),target_brief=coalesce(p_data->>'target_brief',''),
   research_interval_days=coalesce((p_data->>'research_interval_days')::integer,7),next_research_at=coalesce(next_research_at,now()),updated_at=now() WHERE id;
 ELSIF p_action='prospect' THEN
  dom:=regexp_replace(lower(btrim(coalesce(p_data->>'domain',''))),'^(https?://)?(www\.)?',''); dom:=split_part(dom,'/',1);
  pid:=nullif(p_data->>'id','')::uuid;
  IF pid IS NULL THEN
   IF EXISTS(SELECT 1 FROM sales_prospects WHERE regexp_replace(lower(name),'[^a-z0-9]','','g')=regexp_replace(lower(btrim(p_data->>'name')),'[^a-z0-9]','','g')) THEN RAISE EXCEPTION 'A prospect with this company name already exists'; END IF;
   INSERT INTO sales_prospects(name,domain,country,sector,fit_note,source_url,researched_at,notes)
   VALUES(btrim(p_data->>'name'),dom,left(coalesce(p_data->>'country',''),100),left(coalesce(p_data->>'sector',''),200),left(coalesce(p_data->>'fit_note',''),4000),left(coalesce(p_data->>'source_url',''),2000),now(),left(coalesce(p_data->>'notes',''),6000)) RETURNING id INTO pid;
  ELSE
   UPDATE sales_prospects SET name=btrim(p_data->>'name'),domain=dom,country=left(coalesce(p_data->>'country',''),100),sector=left(coalesce(p_data->>'sector',''),200),
    fit_note=left(coalesce(p_data->>'fit_note',''),4000),source_url=left(coalesce(p_data->>'source_url',''),2000),notes=left(coalesce(p_data->>'notes',''),6000),
    stage=coalesce(p_data->>'stage',stage),version=version+1,updated_at=now()
    WHERE id=pid AND version=(p_data->>'version')::integer;
   IF NOT FOUND THEN RAISE EXCEPTION 'Prospect changed. Refresh and review'; END IF;
  END IF;
  RETURN jsonb_build_object('id',pid);
 ELSIF p_action='contact' THEN
  pid:=(p_data->>'prospect_id')::uuid; cid:=nullif(p_data->>'id','')::uuid;
  txt:=nullif(lower(btrim(p_data->>'email')),'');
  IF coalesce((p_data->>'verified')::boolean,false) AND (txt IS NULL OR length(btrim(coalesce(p_data->>'source_url','')))=0 OR length(btrim(coalesce(p_data->>'outreach_basis','')))<5) THEN
   RAISE EXCEPTION 'Email, evidence source and outreach basis are required to verify a contact';
  END IF;
  IF cid IS NULL THEN
   INSERT INTO sales_contacts(prospect_id,name,role_title,email,linkedin_url,source_url,outreach_basis,verified_at,verified_by)
   VALUES(pid,left(coalesce(p_data->>'name',''),200),left(coalesce(p_data->>'role_title',''),200),txt,left(coalesce(p_data->>'linkedin_url',''),2000),left(coalesce(p_data->>'source_url',''),2000),left(coalesce(p_data->>'outreach_basis',''),2000),
    CASE WHEN (p_data->>'verified')::boolean THEN now() END,CASE WHEN (p_data->>'verified')::boolean THEN uid END) RETURNING id INTO cid;
  ELSE
   IF EXISTS(SELECT 1 FROM sales_messages qm JOIN sales_conversations qc ON qc.id=qm.conversation_id WHERE qc.contact_id=cid AND qm.state IN('checking','sending','uncertain')) THEN RAISE EXCEPTION 'Resolve the in-flight or uncertain message before editing this contact'; END IF;
   SELECT * INTO k FROM sales_contacts WHERE id=cid AND prospect_id=pid FOR UPDATE;
   IF k.id IS NULL OR k.version IS DISTINCT FROM (p_data->>'version')::integer THEN RAISE EXCEPTION 'Contact changed. Refresh and review'; END IF;
   IF k.email IS DISTINCT FROM txt AND EXISTS(SELECT 1 FROM sales_conversations WHERE contact_id=cid) THEN RAISE EXCEPTION 'A conversation keeps its original recipient. Add a separate contact for a new address'; END IF;
   UPDATE sales_contacts SET name=left(coalesce(p_data->>'name',''),200),role_title=left(coalesce(p_data->>'role_title',''),200),email=txt,linkedin_url=left(coalesce(p_data->>'linkedin_url',''),2000),source_url=left(coalesce(p_data->>'source_url',''),2000),outreach_basis=left(coalesce(p_data->>'outreach_basis',''),2000),
    verified_at=CASE WHEN (p_data->>'verified')::boolean THEN now() END,verified_by=CASE WHEN (p_data->>'verified')::boolean THEN uid END,version=version+1 WHERE id=cid;
   UPDATE sales_messages SET state='draft',version=version+1,approval_id=NULL WHERE conversation_id IN(SELECT id FROM sales_conversations WHERE contact_id=cid) AND state='approved';
  END IF;
  RETURN jsonb_build_object('id',cid);
 ELSIF p_action='sequence' THEN
  SELECT * INTO k FROM sales_contacts WHERE id=(p_data->>'contact_id')::uuid;
  IF k.email IS NULL THEN RAISE EXCEPTION 'Add a contact email first'; END IF;
  SELECT * INTO p FROM sales_prospects WHERE id=k.prospect_id;
  IF public.sales_blocked_063(k.email,p.domain) OR p.stage='suppressed' THEN RAISE EXCEPTION 'Contact or company is suppressed'; END IF;
  INSERT INTO sales_conversations(prospect_id,contact_id,recipient) VALUES(k.prospect_id,k.id,k.email) RETURNING id INTO cid;
  IF jsonb_array_length(p_data->'messages') NOT BETWEEN 1 AND 3 THEN RAISE EXCEPTION 'A pilot sequence needs 1 to 3 messages'; END IF;
  num:=0;
  FOR item IN SELECT value FROM jsonb_array_elements(p_data->'messages') LOOP
   IF num>0 AND (item->>'delay_days')::integer<=v THEN RAISE EXCEPTION 'Follow-up days must increase'; END IF;
   v:=CASE WHEN num=0 THEN 0 ELSE (item->>'delay_days')::integer END;
   sig:=CASE WHEN coalesce((item->>'include_signature')::boolean,s.signature_enabled) THEN s.email_signature ELSE '{}'::jsonb END;
   INSERT INTO sales_messages(conversation_id,step,kind,subject,body,attachments,delay_days,due_at,signature)
   VALUES(cid,num,CASE WHEN num=0 THEN 'initial' ELSE 'followup' END,btrim(item->>'subject'),btrim(item->>'body'),coalesce(item->'attachments','[]'),v,coalesce((p_data->>'due_at')::timestamptz,now()),sig);
   num:=num+1;
  END LOOP;
  RETURN jsonb_build_object('id',cid);
 ELSIF p_action='message' THEN
  SELECT * INTO m FROM sales_messages WHERE id=(p_data->>'id')::uuid FOR UPDATE;
  IF m.id IS NULL OR m.version IS DISTINCT FROM (p_data->>'version')::integer THEN RAISE EXCEPTION 'Message changed. Refresh and review'; END IF;
  IF m.state NOT IN('draft','approved','failed','cancelled') THEN RAISE EXCEPTION 'This message cannot be edited'; END IF;
  signature_mode:=coalesce(p_data->>'signature_mode','keep');
  IF signature_mode NOT IN('keep','current','none') THEN RAISE EXCEPTION 'Choose whether to keep, update or remove this signature'; END IF;
  sig:=CASE signature_mode WHEN 'current' THEN s.email_signature WHEN 'none' THEN '{}'::jsonb ELSE m.signature END;
  UPDATE sales_messages SET signature=sig,subject=btrim(p_data->>'subject'),body=btrim(p_data->>'body'),attachments=coalesce(p_data->'attachments','[]'),
   delay_days=coalesce((p_data->>'delay_days')::integer,delay_days),due_at=coalesce((p_data->>'due_at')::timestamptz,due_at),state='draft',approval_id=NULL,version=version+1,last_error=NULL WHERE id=m.id;
  IF m.kind='initial' THEN
   UPDATE sales_messages SET state='draft',approval_id=NULL,version=version+1 WHERE conversation_id=m.conversation_id AND id<>m.id AND state='approved';
  END IF;
 ELSIF p_action='reply' THEN
  SELECT * INTO c FROM sales_conversations WHERE id=(p_data->>'conversation_id')::uuid FOR UPDATE;
  IF c.id IS NULL OR c.thread_id IS NULL OR c.state IN('suppressed','closed') THEN RAISE EXCEPTION 'An open sent conversation is required'; END IF;
  SELECT coalesce(max(step),0)+1 INTO num FROM sales_messages WHERE conversation_id=c.id;
  sig:=CASE WHEN coalesce((p_data->>'include_signature')::boolean,s.signature_enabled) THEN s.email_signature ELSE '{}'::jsonb END;
  INSERT INTO sales_messages(conversation_id,step,kind,subject,body,attachments,signature) VALUES(c.id,num,'reply',btrim(p_data->>'subject'),btrim(p_data->>'body'),coalesce(p_data->'attachments','[]'),sig) RETURNING id INTO mid;
  RETURN jsonb_build_object('id',mid);
 ELSIF p_action='approve' THEN
  IF jsonb_typeof(p_data->'messages')<>'array' OR jsonb_array_length(p_data->'messages') NOT BETWEEN 1 AND 50 THEN RAISE EXCEPTION 'Select 1 to 50 messages'; END IF;
  FOR item IN SELECT value FROM jsonb_array_elements(p_data->'messages') LOOP
   SELECT * INTO m FROM sales_messages WHERE id=(item->>'id')::uuid FOR UPDATE;
   IF m.id IS NULL OR m.state<>'draft' OR m.version IS DISTINCT FROM (item->>'version')::integer THEN RAISE EXCEPTION 'A selected draft changed. Refresh and review the whole batch'; END IF;
   IF m.signature<>'{}'::jsonb AND p_data->>'signature_preview_version' IS DISTINCT FROM '1' THEN RAISE EXCEPTION 'Refresh Sales and review the signature before approving this batch'; END IF;
   SELECT * INTO c FROM sales_conversations WHERE id=m.conversation_id;
   SELECT * INTO k FROM sales_contacts WHERE id=c.contact_id;
   SELECT * INTO p FROM sales_prospects WHERE id=c.prospect_id;
   IF k.verified_at IS NULL OR k.verified_at<now()-interval '90 days' OR c.recipient<>k.email OR public.sales_blocked_063(c.recipient,p.domain) OR p.stage='suppressed' OR c.state IN('closed','suppressed') OR (m.kind<>'reply' AND c.state IN('paused','replied')) THEN
    RAISE EXCEPTION 'Verify current contact evidence and check suppression/conversation status before approval';
   END IF;
   -- Thread subjects are pinned by the initial message for Gmail threading.
   IF m.kind<>'initial' AND regexp_replace(m.subject,'^(Re: *)+','','i') IS DISTINCT FROM (SELECT subject FROM sales_messages WHERE conversation_id=c.id AND kind='initial') THEN RAISE EXCEPTION 'Keep the initial subject for replies and follow-ups'; END IF;
   snap:=snap||jsonb_build_array(jsonb_build_object('message',to_jsonb(m),'recipient',c.recipient,'sender',c.sender,'reply_to',c.reply_to,'contact_version',k.version,'verified_at',k.verified_at,'outreach_basis',k.outreach_basis));
  END LOOP;
  INSERT INTO sales_approvals(approved_by,snapshot) VALUES(uid,snap) RETURNING id INTO aid;
  FOR item IN SELECT value FROM jsonb_array_elements(p_data->'messages') LOOP
   UPDATE sales_messages SET state='approved',approval_id=aid WHERE id=(item->>'id')::uuid RETURNING conversation_id INTO cid;
   UPDATE sales_conversations SET state=CASE WHEN state='draft' THEN 'active' ELSE state END,updated_at=now() WHERE id=cid;
  END LOOP;
  INSERT INTO sales_events(actor,event,detail) VALUES(uid,'batch_approved',jsonb_build_object('approval_id',aid,'count',jsonb_array_length(snap)));
  RETURN jsonb_build_object('id',aid);
 ELSIF p_action='resume' THEN
  SELECT * INTO c FROM sales_conversations WHERE id=(p_data->>'conversation_id')::uuid FOR UPDATE;
  SELECT * INTO p FROM sales_prospects WHERE id=c.prospect_id;
  IF c.id IS NULL OR c.state NOT IN('paused','replied') OR p.stage='suppressed' OR public.sales_blocked_063(c.recipient,p.domain) THEN RAISE EXCEPTION 'This conversation cannot resume'; END IF;
  IF EXISTS(SELECT 1 FROM sales_messages WHERE conversation_id=c.id AND state IN('sending','checking','uncertain')) THEN RAISE EXCEPTION 'Resolve delivery uncertainty before resuming'; END IF;
  UPDATE sales_conversations SET state='active',pause_reason='Reopened for administrator review',updated_at=now() WHERE id=c.id;
  cid:=c.id;
 ELSIF p_action='resolve_unsent' THEN
  SELECT * INTO m FROM sales_messages WHERE id=(p_data->>'id')::uuid FOR UPDATE;
  IF m.id IS NULL OR m.state<>'uncertain' OR m.attempted_at>now()-interval '10 minutes' THEN RAISE EXCEPTION 'Only uncertain sends older than 10 minutes can be reviewed'; END IF;
  IF coalesce((p_data->>'confirmed')::boolean,false) IS NOT TRUE OR length(btrim(coalesce(p_data->>'reason','')))<20 THEN RAISE EXCEPTION 'Record how you confirmed in Gmail that no message was sent'; END IF;
  UPDATE sales_messages SET state='failed',version=version+1,approval_id=NULL,last_error='Administrator confirmed not sent: '||left(p_data->>'reason',400),lease_id=NULL,lease_until=NULL WHERE id=m.id;
  INSERT INTO sales_events(conversation_id,actor,event,detail) VALUES(m.conversation_id,uid,'uncertain_send_manually_resolved',jsonb_build_object('message_id',m.id,'reason',p_data->>'reason'));
  RETURN jsonb_build_object('ok',true);
 ELSIF p_action='pause' OR p_action='close' THEN
  cid:=(p_data->>'conversation_id')::uuid;
  UPDATE sales_conversations SET state=CASE WHEN p_action='close' THEN 'closed' ELSE 'paused' END,pause_reason=left(coalesce(p_data->>'reason','Paused by administrator'),500),updated_at=now() WHERE id=cid;
  UPDATE sales_messages SET state='cancelled',version=version+1 WHERE conversation_id=cid AND state IN('draft','approved','checking');
 ELSIF p_action='suppress' THEN
  txt:=lower(btrim(p_data->>'target'));
  IF coalesce(length(txt),0)<3 OR length(btrim(coalesce(p_data->>'reason','')))<3 THEN RAISE EXCEPTION 'Enter an email or domain and a reason'; END IF;
  INSERT INTO sales_suppressions(target,reason,created_by) VALUES(txt,left(p_data->>'reason',500),uid) ON CONFLICT(target) DO NOTHING;
  UPDATE sales_conversations sc SET state='suppressed',pause_reason='Do not contact',updated_at=now() FROM sales_prospects sp WHERE sc.prospect_id=sp.id AND public.sales_blocked_063(sc.recipient,sp.domain);
  UPDATE sales_messages SET state='cancelled',version=version+1 WHERE conversation_id IN(SELECT id FROM sales_conversations WHERE state='suppressed') AND state IN('draft','approved','checking');
  UPDATE sales_prospects SET stage='suppressed',version=version+1 WHERE domain=txt;
 ELSIF p_action='convert' THEN
  SELECT * INTO p FROM sales_prospects WHERE id=(p_data->>'prospect_id')::uuid FOR UPDATE;
  IF p.id IS NULL THEN RAISE EXCEPTION 'Prospect not found'; END IF;
  IF p.client_id IS NOT NULL THEN RETURN jsonb_build_object('id',p.client_id,'existing',true); END IF;
  client:=nullif(p_data->>'client_id','')::uuid;
  IF client IS NOT NULL THEN
   IF NOT EXISTS(SELECT 1 FROM clients WHERE id=client) THEN RAISE EXCEPTION 'Client not found'; END IF;
  ELSE
   IF EXISTS(SELECT 1 FROM clients WHERE lower(name)=lower(p.name) OR lower(website) LIKE '%'||p.domain||'%') THEN RAISE EXCEPTION 'Possible existing Client. Link it before creating another'; END IF;
   txt:=upper(btrim(coalesce(p_data->>'code','')));
   IF txt !~ '^[A-Z0-9_-]{2,12}$' THEN RAISE EXCEPTION 'Enter a unique 2 to 12 character Client code'; END IF;
   INSERT INTO clients(name,code,website,client_type,default_currency) VALUES(p.name,txt,'https://'||p.domain,coalesce(p_data->>'client_type','Direct'),coalesce(p_data->>'currency','EUR')) RETURNING id INTO client;
  END IF;
  UPDATE sales_prospects SET client_id=client,stage='won',version=version+1,updated_at=now() WHERE id=p.id;
  RETURN jsonb_build_object('id',client);
 ELSIF p_action='task' THEN
  mid:=nullif(p_data->>'id','')::uuid;
  IF mid IS NULL THEN INSERT INTO sales_tasks(prospect_id,title,notes,due_at,created_by)
   VALUES(nullif(p_data->>'prospect_id','')::uuid,btrim(p_data->>'title'),coalesce(p_data->>'notes',''),coalesce((p_data->>'due_at')::timestamptz,now()),uid) RETURNING id INTO mid;
  ELSE UPDATE sales_tasks SET done=coalesce((p_data->>'done')::boolean,true) WHERE id=mid;
  END IF;
  RETURN jsonb_build_object('id',mid);
 ELSIF p_action='material' THEN
  mid:=nullif(p_data->>'id','')::uuid;
  IF mid IS NULL THEN INSERT INTO sales_materials(title,content,prospect_id,created_by) VALUES(btrim(p_data->>'title'),btrim(p_data->>'content'),nullif(p_data->>'prospect_id','')::uuid,uid) RETURNING id INTO mid;
  ELSE UPDATE sales_materials SET title=btrim(p_data->>'title'),content=btrim(p_data->>'content'),version=version+1,updated_at=now() WHERE id=mid AND version=(p_data->>'version')::integer;
   IF NOT FOUND THEN RAISE EXCEPTION 'Material changed. Refresh and review'; END IF;
  END IF;
  RETURN jsonb_build_object('id',mid);
 ELSE RAISE EXCEPTION 'Unknown Sales action';
 END IF;
 INSERT INTO sales_events(conversation_id,actor,event,detail) VALUES(cid,uid,p_action,jsonb_build_object('id',coalesce(mid,pid,cid)));
 RETURN jsonb_build_object('ok',true);
END $$;

-- Preserve the corrected 058 worker and verify the approved signature before send.
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
  -- Legacy approvals have no signature key and match an empty signature only.
  IF coalesce(snap->'message'->'signature','{}'::jsonb) IS DISTINCT FROM m.signature THEN RAISE EXCEPTION 'Approved signature does not match. Review the message again'; END IF;
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

REVOKE ALL ON FUNCTION public.sales_signature_valid_064(jsonb,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.sales_signature_valid_064(jsonb,boolean) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.sales_command_063(text,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.sales_command_063(text,jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.sales_system_063(text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.sales_system_063(text,jsonb) TO service_role;
NOTIFY pgrst,'reload schema';
COMMIT;

// Isolated PostgreSQL (PGlite) fixture. No network, live database or email calls.
// Run with PGLITE_MODULE pointing to an installed @electric-sql/pglite module.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const {PGlite}=await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const db=new PGlite();
const file=path=>readFileSync(new URL('../'+path,import.meta.url),'utf8');

await db.exec(`
CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role;
CREATE SCHEMA auth;
CREATE FUNCTION auth.role() RETURNS text LANGUAGE sql AS $$
 SELECT current_setting('request.jwt.claim.role',true)
$$;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql AS $$
 SELECT NULLIF(current_setting('request.jwt.claim.sub',true),'')::uuid
$$;
CREATE TABLE auth.users(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 email text UNIQUE,
 email_confirmed_at timestamptz,
 last_sign_in_at timestamptz
);
CREATE TABLE public.profiles(
 id uuid PRIMARY KEY REFERENCES auth.users(id),
 full_name text,
 role text NOT NULL
);
CREATE TABLE public.resources(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 profile_id uuid UNIQUE REFERENCES public.profiles(id),
 resource_type text NOT NULL,
 legal_name text,
 company_name text,
 email text,
 lifecycle_status text NOT NULL DEFAULT 'Active',
 portal_status text NOT NULL DEFAULT 'Not invited',
 updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.resource_access_invitations(
 resource_id uuid PRIMARY KEY REFERENCES public.resources(id),
 attempt_id uuid NOT NULL,
 actor_id uuid NOT NULL REFERENCES public.profiles(id),
 email text NOT NULL,
 started_at timestamptz NOT NULL DEFAULT now(),
 finished_at timestamptz,
 status text NOT NULL CHECK(status IN ('sending','sent','failed'))
);
CREATE TABLE public.audit_events(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 entity_type text,
 entity_id uuid,
 action text,
 before_values jsonb,
 after_values jsonb,
 reason text
);
CREATE FUNCTION public.is_admin() RETURNS boolean LANGUAGE sql AS $$
 SELECT auth.role()='service_role'
$$;
CREATE FUNCTION public.append_trusted_tms_audit_event(
 p_entity_type text,p_entity_id uuid,p_action text,
 p_before_values jsonb,p_after_values jsonb,p_reason text
) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO audit_events(entity_type,entity_id,action,before_values,after_values,reason)
 VALUES(p_entity_type,p_entity_id,p_action,p_before_values,p_after_values,p_reason);
END
$$;
CREATE FUNCTION public.resource_onboarding_040(
 p_action text,p_actor_id uuid,p_resource_id uuid DEFAULT NULL,
 p_payload jsonb DEFAULT '{}'::jsonb,p_request_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE sql AS $$ SELECT '{}'::jsonb $$;
CREATE FUNCTION public.check_resource_auth_email_040() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,auth AS $$
BEGIN
 NEW.email:=NULLIF(lower(btrim(NEW.email)),'');
 IF NEW.profile_id IS NOT NULL AND NOT EXISTS(
  SELECT 1 FROM auth.users WHERE id=NEW.profile_id AND lower(btrim(email))=NEW.email
 ) THEN RAISE EXCEPTION 'Resource email must match its linked login email'; END IF;
 RETURN NEW;
END
$$;
CREATE TRIGGER resources_check_auth_email_040
BEFORE INSERT OR UPDATE OF email,profile_id ON resources
FOR EACH ROW EXECUTE FUNCTION check_resource_auth_email_040();
CREATE FUNCTION public.protect_external_resource_portal_security() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,auth AS $$
BEGIN
 IF NEW.resource_type<>'Internal' AND NEW.profile_id IS NOT NULL THEN
  IF NOT EXISTS(
   SELECT 1 FROM profiles p JOIN auth.users u ON u.id=p.id
   WHERE p.id=NEW.profile_id AND p.role='resource'
     AND lower(btrim(u.email))=lower(btrim(NEW.email))
  ) THEN RAISE EXCEPTION 'External Resource identity mismatch'; END IF;
 END IF;
 RETURN NEW;
END
$$;
CREATE TRIGGER resources_protect_external_portal_security
BEFORE INSERT OR UPDATE OF profile_id,resource_type,portal_status,email ON resources
FOR EACH ROW EXECUTE FUNCTION protect_external_resource_portal_security();
`);

await db.exec(file('tms/migrations/046_resource_invitation_email_correction.sql'));
await db.exec("SET request.jwt.claim.role='service_role'");

let passed=0;
async function check(name,fn){await fn();passed++;console.log('PASS '+name)}
async function addUser(email,role,lastSignIn=null){
 const {rows:[user]}=await db.query(
  'INSERT INTO auth.users(email,email_confirmed_at,last_sign_in_at) VALUES($1,now(),$2) RETURNING id',
  [email,lastSignIn]
 );
 await db.query('INSERT INTO profiles(id,full_name,role) VALUES($1,$2,$3)',[user.id,email,role]);
 return user.id;
}
async function addResource(number,email,userId,portal='Active'){
 const {rows:[resource]}=await db.query(
  "INSERT INTO resources(profile_id,resource_type,legal_name,email,portal_status) VALUES($1,'Freelancer',$2,$3,$4) RETURNING id",
  [userId,number,email,portal]
 );
 return resource.id;
}
async function correction(action,actor,resourceId,email,requestId){
 const {rows:[row]}=await db.query(
  'SELECT resource_email_correction_046($1,$2,$3,$4,$5) AS result',
  [action,actor,resourceId,email,requestId]
 );
 return row.result;
}

const admin=await addUser('admin@test.invalid','admin');
const pm=await addUser('pm@test.invalid','pm');

await check('browser roles have no table or function access',async()=>{
 for(const role of ['anon','authenticated']){
  const {rows:[privileges]}=await db.query(
   "SELECT has_table_privilege($1,'resource_email_correction_requests','SELECT') AS table_read, has_function_privilege($1,'resource_email_correction_046(text,uuid,uuid,text,uuid)','EXECUTE') AS function_run",
   [role]
  );
  assert.equal(privileges.table_read,false);assert.equal(privileges.function_run,false);
 }
});

await check('direct execution without the service role is rejected',async()=>{
 const user=await addUser('guarded-old@test.invalid','resource');
 const resource=await addResource('Guarded','guarded-old@test.invalid',user);
 await db.exec("SET request.jwt.claim.role='authenticated'");
 await assert.rejects(()=>correction('prepare',admin,resource,'guarded-new@test.invalid',crypto.randomUUID()),/Server access required/);
 await db.exec("SET request.jwt.claim.role='service_role'");
});

await check('only an Administrator actor can prepare a correction',async()=>{
 const user=await addUser('role-old@test.invalid','resource');
 const resource=await addResource('Role','role-old@test.invalid',user);
 await assert.rejects(()=>correction('prepare',pm,resource,'role-new@test.invalid',crypto.randomUUID()),/Administrator access required/);
});

await check('an account with sign-in history cannot be corrected',async()=>{
 const user=await addUser('used-old@test.invalid','resource','2026-09-10T10:00:00Z');
 const resource=await addResource('Used','used-old@test.invalid',user);
 await assert.rejects(()=>correction('prepare',admin,resource,'used-new@test.invalid',crypto.randomUUID()),/already been used/);
});

await check('duplicate Auth or Resource addresses are rejected',async()=>{
 await addUser('occupied@test.invalid','resource');
 const user=await addUser('duplicate-old@test.invalid','resource');
 const resource=await addResource('Duplicate','duplicate-old@test.invalid',user);
 await assert.rejects(()=>correction('prepare',admin,resource,'occupied@test.invalid',crypto.randomUUID()),/already used/);
});

await check('obvious provider typo is rejected at the database boundary',async()=>{
 const user=await addUser('typo-old@test.invalid','resource');
 const resource=await addResource('Typo','typo-old@test.invalid',user);
 await assert.rejects(()=>correction('prepare',admin,resource,'vlavla845@gmai.com',crypto.randomUUID()),/looks mistyped/);
});

await check('direct contact edit still cannot diverge from the linked Auth email',async()=>{
 const user=await addUser('protected-old@test.invalid','resource');
 const resource=await addResource('Protected','protected-old@test.invalid',user);
 await assert.rejects(()=>db.query("UPDATE resources SET email='protected-new@test.invalid' WHERE id=$1",[resource]),/must match/);
});

await check('prepared correction is resumable after the Auth email changes',async()=>{
 const user=await addUser('resume-old@test.invalid','resource');
 const resource=await addResource('Resume','resume-old@test.invalid',user);
 const firstRequest=crypto.randomUUID();
 const prepared=await correction('prepare',admin,resource,'resume-new@test.invalid',firstRequest);
 assert.equal(prepared.auth_update_required,true);assert.equal(prepared.auth_user_id,user);
 await db.query("UPDATE auth.users SET email='resume-new@test.invalid' WHERE id=$1",[user]);
 const resumed=await correction('prepare',admin,resource,'resume-new@test.invalid',crypto.randomUUID());
 assert.equal(resumed.request_id,firstRequest);assert.equal(resumed.auth_update_required,false);
 await correction('complete',admin,resource,'resume-new@test.invalid',firstRequest);
 const {rows:[updated]}=await db.query('SELECT email,portal_status FROM resources WHERE id=$1',[resource]);
 assert.equal(updated.email,'resume-new@test.invalid');assert.equal(updated.portal_status,'Invited');
});

await check('completion invalidates the old invitation and writes a trusted audit event',async()=>{
 const user=await addUser('wrong@test.invalid','resource');
 const resource=await addResource('Corrected','wrong@test.invalid',user);
 await db.query(
  "INSERT INTO resource_access_invitations(resource_id,attempt_id,actor_id,email,finished_at,status) VALUES($1,$2,$3,'wrong@test.invalid',now(),'sent')",
  [resource,crypto.randomUUID(),admin]
 );
 const request=crypto.randomUUID();
 const prepared=await correction('prepare',admin,resource,'right@test.invalid',request);
 assert.equal(prepared.completed,false);assert.equal(prepared.auth_update_required,true);
 await db.query("UPDATE auth.users SET email='right@test.invalid' WHERE id=$1",[user]);
 const completed=await correction('complete',admin,resource,'right@test.invalid',request);
 assert.equal(completed.completed,true);
 const {rows:[updated]}=await db.query('SELECT email,portal_status FROM resources WHERE id=$1',[resource]);
 assert.equal(updated.email,'right@test.invalid');assert.equal(updated.portal_status,'Invited');
 const {rows:[invitation]}=await db.query('SELECT email,status,finished_at<now()-interval \'60 seconds\' AS retry_ready FROM resource_access_invitations WHERE resource_id=$1',[resource]);
 assert.equal(invitation.email,'right@test.invalid');assert.equal(invitation.status,'failed');assert.equal(invitation.retry_ready,true);
 const {rows:[audit]}=await db.query('SELECT action,before_values,after_values FROM audit_events WHERE entity_id=$1',[resource]);
 assert.equal(audit.action,'External Resource login email corrected');
 assert.equal(audit.before_values.email,'wrong@test.invalid');assert.equal(audit.after_values.email,'right@test.invalid');
    const retried=await correction('complete',admin,resource,'right@test.invalid',request);
    assert.equal(retried.completed,true);
});

await check('Update 047 release audit reports only PASS rows',async()=>{
 const {rows}=await db.query(file('tms/audits/008_update_047_resource_email_correction_audit.sql'));
 assert.ok(rows.length>=8);
 assert.deepEqual([...new Set(rows.map(row=>row.result))],['PASS']);
});

console.log(`${passed} Update 047 database checks passed`);
await db.close();

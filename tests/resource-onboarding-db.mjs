// Isolated PostgreSQL (PGlite) fixture. No network, live database or email calls.
// Run with PGLITE_MODULE pointing to an installed @electric-sql/pglite module.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const {PGlite}=await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const db=new PGlite();
const file=p=>readFileSync(new URL('../'+p,import.meta.url),'utf8');
const extract=(path,name)=>{
    const sql=file(path), start=sql.indexOf('CREATE OR REPLACE FUNCTION public.'+name+'(');
    assert.ok(start>=0);return sql.slice(start,sql.indexOf('$$;',start)+3);
};
await db.exec(`
CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role;
CREATE SCHEMA auth;
CREATE FUNCTION auth.role() RETURNS text LANGUAGE sql AS $$ SELECT current_setting('request.jwt.claim.role',true) $$;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql AS $$ SELECT NULLIF(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
CREATE TABLE auth.users(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),email text UNIQUE,email_confirmed_at timestamptz);
CREATE TABLE public.profiles(id uuid PRIMARY KEY REFERENCES auth.users(id),full_name text,role text DEFAULT 'user'
 CHECK(role IN ('user','resource','pm','qa','client_relations','admin')));
CREATE TABLE public.resources(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),internal_number text UNIQUE,
 profile_id uuid UNIQUE REFERENCES profiles(id),resource_type text CHECK(resource_type IN ('Internal','Freelancer','Company')),
 legal_name text,company_name text,email text,internal_positions text[],gender text,
 lifecycle_status text DEFAULT 'Active' CHECK(lifecycle_status IN ('Active','On leave','Inactive')),
 portal_status text DEFAULT 'Not invited' CHECK(portal_status IN ('Not invited','Invited','Active','Read-only','Financial only','Closed')),
 assignment_approved boolean DEFAULT false,resource_status text DEFAULT 'New contact',financial_access_until timestamptz,
 created_by uuid REFERENCES profiles(id),created_at timestamptz DEFAULT now());
CREATE FUNCTION public.can_manage_operations() RETURNS boolean LANGUAGE sql AS $$
 SELECT COALESCE((SELECT role IN ('admin','pm','client_relations') FROM profiles WHERE id=auth.uid()),false) $$;
CREATE FUNCTION public.is_admin() RETURNS boolean LANGUAGE sql AS $$ SELECT auth.role()='service_role' $$;
`);
await db.exec(extract('tms/migrations/034_internal_resources_scoop_deadlines_and_context_numbers.sql','internal_positions_from_payload'));
await db.exec(extract('tms/migrations/038_external_resource_portal_and_role_boundaries.sql','protect_external_resource_portal_security'));
await db.exec(`CREATE TRIGGER resources_protect_external_portal_security
 BEFORE INSERT OR UPDATE OF profile_id,resource_type,portal_status,financial_access_until,email
 ON resources FOR EACH ROW EXECUTE FUNCTION protect_external_resource_portal_security();`);
await db.exec(file('tms/migrations/040_resource_onboarding.sql'));
await db.exec("SET request.jwt.claim.role='service_role'");
let passed=0;
async function check(name,fn){await fn();passed++;console.log('PASS '+name);}
async function addUser(email,role='user',confirmed=true){
 const {rows:[u]}=await db.query('INSERT INTO auth.users(email,email_confirmed_at) VALUES($1,$2) RETURNING id',[email,confirmed?'2026-09-07':null]);
 await db.query('INSERT INTO profiles(id,role) VALUES($1,$2)',[u.id,role]);return u.id;
}
const admin=await addUser('admin@test.invalid','admin');
const qa=await addUser('qa@test.invalid','qa');
const cr=await addUser('cr@test.invalid','client_relations');
const external=await addUser('self@test.invalid');
const attempt=()=>crypto.randomUUID();
async function rpc(action,actor,rid=null,payload={},request=null){
 const {rows:[r]}=await db.query('SELECT resource_onboarding_040($1,$2,$3,$4,$5) AS result',[action,actor,rid,JSON.stringify(payload),request]);return r.result;
}
const backfillUser=await addUser('backfill@test.invalid','resource');
const inactiveBackfillUser=await addUser('inactive-backfill@test.invalid','resource');
const {rows:[backfillResource]}=await db.query(
 "INSERT INTO resources(internal_number,resource_type,company_name,email,profile_id,portal_status) VALUES('BACKFILL','Company','Backfill Co','backfill@test.invalid',$1,'Invited') RETURNING id",
 [backfillUser],
);
const {rows:[inactiveBackfillResource]}=await db.query(
 "INSERT INTO resources(internal_number,resource_type,legal_name,email,profile_id,lifecycle_status,portal_status) VALUES('BACKFILL-INACTIVE','Freelancer','Inactive Backfill','inactive-backfill@test.invalid',$1,'Inactive','Invited') RETURNING id",
 [inactiveBackfillUser],
);
await db.query(
 "INSERT INTO resource_access_invitations(resource_id,attempt_id,actor_id,email,finished_at,status) VALUES($1,$2,$3,'backfill@test.invalid',now(),'sent'),($4,$5,$3,'inactive-backfill@test.invalid',now(),'sent')",
 [backfillResource.id,attempt(),admin,inactiveBackfillResource.id,attempt()],
);
await db.exec(file('tms/migrations/041_activate_sent_resource_invitations.sql'));
await db.exec(file('tms/migrations/041_activate_sent_resource_invitations.sql'));
await check('browser roles cannot execute the dispatcher',async()=>{
 for(const role of ['anon','authenticated']) {
  const {rows:[r]}=await db.query("SELECT has_function_privilege($1,'resource_onboarding_040(text,uuid,uuid,jsonb,uuid)','EXECUTE') AS allowed",[role]);
  assert.equal(r.allowed,false);
  const {rows:[triggerFunction]}=await db.query("SELECT has_function_privilege($1,'activate_sent_resource_invitation_041()','EXECUTE') AS allowed",[role]);
  assert.equal(triggerFunction.allowed,false);
 }
});
await check('migration backfills only valid already-sent staff invitations',async()=>{
 const {rows:[valid]}=await db.query('SELECT portal_status FROM resources WHERE id=$1',[backfillResource.id]);
 const {rows:[inactive]}=await db.query('SELECT portal_status FROM resources WHERE id=$1',[inactiveBackfillResource.id]);
 assert.equal(valid.portal_status,'Active');
 assert.equal(inactive.portal_status,'Invited');
});
await check('direct call without service JWT is rejected',async()=>{
 const {rows:[guarded]}=await db.query("INSERT INTO resources(internal_number,resource_type,email) VALUES('GUARDED-INVITE','Freelancer','guarded@test.invalid') RETURNING id");
 await db.query("INSERT INTO resource_access_invitations(resource_id,attempt_id,actor_id,email,status) VALUES($1,$2,$3,'guarded@test.invalid','sending')",[guarded.id,attempt(),admin]);
 await db.exec("SET request.jwt.claim.role='authenticated'");
 await assert.rejects(()=>rpc('register',external,null,{name:'Self'}),/Server access required/);
 await assert.rejects(()=>db.query("UPDATE resource_access_invitations SET status='sent' WHERE resource_id=$1",[guarded.id]),/Server access required/);
 await db.exec("SET request.jwt.claim.role='service_role'");
});
await check('verified self-registration creates one resource and stays pending',async()=>{
 const result=await rpc('register',external,null,{name:'Self',role:'admin'});
 assert.equal(result.pending_approval,true);
 await rpc('register',external,null,{name:'Changed'});
 const {rows}=await db.query('SELECT r.*,p.role FROM resources r JOIN profiles p ON p.id=r.profile_id WHERE profile_id=$1',[external]);
 assert.equal(rows.length,1);assert.equal(rows[0].role,'resource');assert.equal(rows[0].portal_status,'Invited');
 assert.equal(rows[0].legal_name,'Self');assert.equal(rows[0].assignment_approved,false);
});
await check('unverified email cannot register or claim a resource',async()=>{
 const user=await addUser('unverified@test.invalid','user',false);
 await assert.rejects(()=>rpc('register',user,null,{name:'No'}),/Confirm your email/);
});
await check('company account cannot self-register',async()=>{
 await assert.rejects(()=>rpc('register',admin,null,{name:'No'}),/Company accounts/);
});
let importedId;
await check('external import creates no account; self-registration reuses imported record',async()=>{
 const {rows:[r]}=await db.query("INSERT INTO resources(internal_number,resource_type,email,legal_name) VALUES('IMPORTED','Freelancer','import@test.invalid','Imported Name') RETURNING id");importedId=r.id;
 const {rows}=await db.query("SELECT id FROM auth.users WHERE email='import@test.invalid'");assert.equal(rows.length,0);
 const user=await addUser('import@test.invalid');await rpc('register',user,null,{name:'New Name'});
 const {rows:[updated]}=await db.query('SELECT * FROM resources WHERE id=$1',[importedId]);assert.equal(updated.legal_name,'Imported Name');assert.equal(updated.profile_id,user);
});
await check('duplicate resource email is rejected case-insensitively',async()=>{
 await assert.rejects(()=>db.query("INSERT INTO resources(internal_number,resource_type,email) VALUES('DUP','Freelancer',' IMPORT@TEST.INVALID ')"),/unique/);
});
let internalId;
await check('internal creation is idempotent and creates no second record on retry',async()=>{
 const request=attempt(),payload={name:'Internal',email:'internal@test.invalid',positions:['Project Manager']};
 const a=await rpc('create_internal',admin,null,payload,request);const b=await rpc('create_internal',admin,null,payload,request);
 assert.equal(a.resource_id,b.resource_id);internalId=a.resource_id;
});
await check('QA cannot create internal access',async()=>{
 await assert.rejects(()=>rpc('create_internal',qa,null,{name:'No',email:'no@test.invalid',positions:['Project Manager']},attempt()),/Operational access/);
});
await check('CR cannot grant PM access',async()=>{
 await assert.rejects(()=>rpc('create_internal',cr,null,{name:'No',email:'no@test.invalid',positions:['Project Manager']},attempt()),/Administrator or PM/);
});
await check('internal invitation links a new account with correct company role',async()=>{
 const id=attempt();const prepared=await rpc('prepare_invite',admin,internalId,{},id);assert.equal(prepared.user_id,null);
 const user=await addUser('internal@test.invalid');
 await rpc('link_invite',admin,internalId,{},id);await rpc('invite_sent',admin,internalId,{},id);
 const {rows:[r]}=await db.query('SELECT r.portal_status,p.role FROM resources r JOIN profiles p ON p.id=r.profile_id WHERE r.id=$1',[internalId]);
 assert.equal(r.role,'pm');assert.equal(r.portal_status,'Active');
});
await check('immediate repeat invitation is refused',async()=>{
 await assert.rejects(()=>rpc('prepare_invite',admin,internalId,{},attempt()),/recently requested/);
});
await check('external portal activates only after the invitation is recorded as sent',async()=>{
 const {rows:[r]}=await db.query("INSERT INTO resources(internal_number,resource_type,email) VALUES('INVITED','Freelancer','invite@test.invalid') RETURNING id");
 const id=attempt();await rpc('prepare_invite',admin,r.id,{},id);await addUser('invite@test.invalid');
 await rpc('link_invite',admin,r.id,{},id);
 const {rows:[result]}=await db.query('SELECT portal_status FROM resources WHERE id=$1',[r.id]);assert.equal(result.portal_status,'Invited');
 await rpc('invite_sent',admin,r.id,{},id);
 const {rows:[activated]}=await db.query('SELECT portal_status FROM resources WHERE id=$1',[r.id]);assert.equal(activated.portal_status,'Active');
});
await check('failed invitation remains Invited',async()=>{
 const {rows:[r]}=await db.query("INSERT INTO resources(internal_number,resource_type,email) VALUES('FAILED-INVITE','Freelancer','failed-invite@test.invalid') RETURNING id");
 const id=attempt();await rpc('prepare_invite',admin,r.id,{},id);await addUser('failed-invite@test.invalid');
 await rpc('link_invite',admin,r.id,{},id);await rpc('invite_failed',admin,r.id,{},id);
 const {rows:[result]}=await db.query('SELECT portal_status FROM resources WHERE id=$1',[r.id]);assert.equal(result.portal_status,'Invited');
});
await check('CR cannot invite external resource',async()=>{
 await assert.rejects(()=>rpc('prepare_invite',cr,importedId,{},attempt()),/Only the Administrator/);
});
await check('linked internal email cannot diverge from Auth email',async()=>{
 await assert.rejects(()=>db.query("UPDATE resources SET email='wrong@test.invalid' WHERE id=$1",[internalId]),/must match/);
});
await check('existing company role cannot be captured by an external invitation',async()=>{
 const {rows:[r]}=await db.query("INSERT INTO resources(internal_number,resource_type,email) VALUES('CONFLICT','Freelancer','qa@test.invalid') RETURNING id");
 await assert.rejects(()=>rpc('prepare_invite',admin,r.id,{},attempt()),/Company accounts/);
});
await check('changed email invalidates prepared invitation',async()=>{
 const {rows:[r]}=await db.query("INSERT INTO resources(internal_number,resource_type,email) VALUES('CHANGED','Freelancer','before@test.invalid') RETURNING id");
 const id=attempt();await rpc('prepare_invite',admin,r.id,{},id);
 await db.query("UPDATE resources SET email='after@test.invalid' WHERE id=$1",[r.id]);
 await addUser('after@test.invalid');
 await assert.rejects(()=>rpc('link_invite',admin,r.id,{},id),/Invitation changed/);
});
await check('linking an existing company account preserves its role',async()=>{
 const existing=await addUser('existing-qa@test.invalid','qa');
 const result=await rpc('create_internal',admin,null,{name:'Existing QA',email:'existing-qa@test.invalid',positions:['Project Manager']},attempt());
 const id=attempt();await rpc('prepare_invite',admin,result.resource_id,{},id);await rpc('link_invite',admin,result.resource_id,{},id);
 const {rows:[profile]}=await db.query('SELECT role FROM profiles WHERE id=$1',[existing]);assert.equal(profile.role,'qa');
});
await check('inactive company actor cannot provision resources',async()=>{
 const {rows:[r]}=await db.query("INSERT INTO resources(internal_number,resource_type,email,profile_id,lifecycle_status) VALUES('CR-INACTIVE','Internal','cr@test.invalid',$1,'Inactive') RETURNING id",[cr]);
 await assert.rejects(()=>rpc('create_internal',cr,null,{name:'No',email:'disabled@test.invalid',positions:['Project']},attempt()),/Operational access/);
});
console.log(`${passed} PostgreSQL fixture checks passed`);
await db.close();

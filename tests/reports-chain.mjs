// Applies repository schema/policies. Supabase platform objects are emulated.
// PGlite lacks pgcrypto; only its CREATE EXTENSION statement is omitted.
// The chain uses built-in gen_random_uuid and no other pgcrypto functions.
import fs from 'node:fs';
import {pathToFileURL} from 'node:url';
const {PGlite}=await import(pathToFileURL(process.env.PGLITE_MODULE));
const db=new PGlite();
await db.exec(`CREATE ROLE authenticated; CREATE ROLE anon; CREATE ROLE service_role BYPASSRLS;
CREATE SCHEMA auth; CREATE TABLE auth.users(id uuid PRIMARY KEY,email text,raw_user_meta_data jsonb DEFAULT '{}',raw_app_meta_data jsonb DEFAULT '{}',email_confirmed_at timestamptz,created_at timestamptz DEFAULT now(),updated_at timestamptz DEFAULT now(),banned_until timestamptz);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
CREATE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS $$SELECT nullif(current_setting('request.jwt.claim.role',true),'')$$;
CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $$SELECT coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
GRANT USAGE ON SCHEMA auth, public TO authenticated,anon,service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT,INSERT,UPDATE,DELETE ON TABLES TO authenticated,service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE ON SEQUENCES TO authenticated,service_role;`);
const files=['tms/setup.sql',...fs.readdirSync('tms/migrations').filter(n=>n.endsWith('.sql')).sort().map(n=>'tms/migrations/'+n)];
let done=0;
try {for(const file of files){await db.exec(fs.readFileSync(file,'utf8').replace('CREATE EXTENSION IF NOT EXISTS pgcrypto;', '-- PGlite: gen_random_uuid is built in'));if(file==='tms/setup.sql') await db.exec("INSERT INTO auth.users(id,email,raw_user_meta_data) VALUES ('00000000-0000-0000-0000-000000000001','aleksandra.atanasoff@gmail.com','{\"full_name\":\"Isolated bootstrap fixture\"}')");done++;console.log('PASS',file);}console.log('PASS complete repository migration chain');}
catch(e){console.error('BLOCKED',files[done],e.message);process.exitCode=1;}
finally {await db.close();}

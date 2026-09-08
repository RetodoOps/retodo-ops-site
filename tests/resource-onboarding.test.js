'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {handler} = require('../netlify/functions/resource-onboarding');
const actor = '11111111-1111-4111-8111-111111111111';
const resource = '22222222-2222-4222-8222-222222222222';
const request = '33333333-3333-4333-8333-333333333333';
const originalFetch = global.fetch;
process.env.SUPABASE_URL = 'https://test.supabase.co';
process.env.SUPABASE_SERVICE_ROLE_KEY = 'unit-test-placeholder';
process.env.TMS_SITE_URL = 'https://tms.retodo-ops.com';
process.env.GOOGLE_CLIENT_ID = 'test-google-client';
process.env.GOOGLE_CLIENT_SECRET = 'unit-test-placeholder';
process.env.GOOGLE_REFRESH_TOKEN = 'unit-test-placeholder';
process.env.GMAIL_FROM_EMAIL = 'ops@retodo-ops.com';
test.after(()=>{global.fetch=originalFetch;});
function event(body, overrides={}) { return {httpMethod:'POST',headers:{authorization:'Bearer user-token',origin:process.env.TMS_SITE_URL},body:JSON.stringify(body),...overrides}; }
function mock({confirmed=false,denyPrepare=false,failMail=false,failAuth=false,failLink=false,unauthorized=false,badLink=false}={}) {
    const calls=[];
    global.fetch=async (url,options)=>{
        const payload=options.body && String(options.headers?.['Content-Type'] || '').includes('application/json')
            ? JSON.parse(options.body) : options.body || null;
        calls.push({url,options,payload});
        let value={};let status=200;
        if(url.endsWith('/user')) {value={id:actor};if(unauthorized)status=401;}
        else if(url.includes('/rpc/')) {
            assert.equal(payload.p_actor_id,actor,'actor must come from verified token');
            if(payload.p_action==='create_internal') value={resource_id:resource};
            if(payload.p_action==='prepare_invite') {
                value={email:'recipient@example.test',confirmed,name:'Test',user_id:confirmed?request:null};
                if(denyPrepare){status=403;value={message:'Operational access required'};}
            }
            if(payload.p_action==='link_invite'&&failLink){status=400;value={message:'Resource and login email do not match'};}
            if(payload.p_action==='register') value={registered:true,pending_approval:true};
        } else if(url.endsWith('/auth/v1/admin/generate_link')) {
            value={action_link:badLink ? 'https://evil.test/steal' :
                `https://test.supabase.co/auth/v1/verify?token=unit-test-token&type=${payload.type}&redirect_to=${encodeURIComponent(payload.redirect_to)}`};
        } else if(url==='https://oauth2.googleapis.com/token') {
            if(failAuth){status=401;value={error_description:'provider-private-detail'};}
            else value={access_token:'test-google-access'};
        } else if(url==='https://gmail.googleapis.com/gmail/v1/users/me/messages/send') {
            if(failMail){status=429;value={message:'smtp secret must not leak'};}
            else value={id:'gmail-message-id',threadId:'gmail-thread-id'};
        }
        return {ok:status<400,status,json:async()=>value};
    };
    return calls;
}
test('missing authentication never reaches the privileged API',async()=>{
    const calls=mock();const response=await handler(event({action:'invite',resource_id:resource},{headers:{}}));
    assert.equal(response.statusCode,401);assert.equal(calls.length,0);
});
test('invalid token cannot reach RPC or mail',async()=>{
    const calls=mock({unauthorized:true});const response=await handler(event({action:'invite',resource_id:resource}));
    assert.equal(response.statusCode,401);assert.equal(calls.length,1);
});
test('cross-origin requests are refused',async()=>{
    const calls=mock();const response=await handler(event({action:'invite'},{headers:{authorization:'Bearer token',origin:'https://evil.test'}}));
    assert.equal(response.statusCode,403);assert.equal(calls.length,0);
});
test('unapproved actor cannot send mail even with forged actor or role fields',async()=>{
    const calls=mock({denyPrepare:true});const response=await handler(event({action:'invite',resource_id:resource,actor_id:request,role:'admin'}));
    assert.equal(response.statusCode,400);assert.equal(calls.length,2);
});
test('new account generates an invite link and sends a branded access invitation',async()=>{
    const calls=mock();const response=await handler(event({action:'invite',resource_id:resource,redirect_to:'https://evil.test',password:'malicious'}));
    assert.equal(response.statusCode,200);
    const generated=calls.find(x=>x.url.endsWith('/auth/v1/admin/generate_link'));
    assert.deepEqual(generated.payload,{type:'invite',email:'recipient@example.test',
        redirect_to:'https://tms.retodo-ops.com/reset-password.html',data:{full_name:'Test'}});
    assert.equal(Object.hasOwn(generated.payload,'password'),false);
    const gmail=calls.find(x=>x.url==='https://gmail.googleapis.com/gmail/v1/users/me/messages/send');
    const mime=Buffer.from(gmail.payload.raw.replaceAll('-','+').replaceAll('_','/'),'base64').toString('utf8');
    const bodies=[...mime.matchAll(/Content-Transfer-Encoding: base64\r\n\r\n([A-Za-z0-9+/=]+)\r\n/g)]
        .map(match=>Buffer.from(match[1],'base64').toString('utf8')).join('\n');
    assert.match(mime,new RegExp(Buffer.from('Your RetodoOps TMS access invitation','utf8').toString('base64')));
    assert.match(mime,/recipient@example\.test/);
    assert.match(bodies,/Retodo Ops has invited you to access the TMS/);
    assert.match(bodies,/Create password and open TMS/);
    assert.doesNotMatch(bodies,/Reset your password/);
    assert.ok(!response.body.includes('unit-test-token'));
    assert.deepEqual(calls.filter(x=>x.payload?.p_action).map(x=>x.payload.p_action),['prepare_invite','link_invite','invite_sent']);
});
test('existing confirmed account uses a recovery token inside the same access-invitation message',async()=>{
    const calls=mock({confirmed:true});const response=await handler(event({action:'invite',resource_id:resource}));
    assert.equal(response.statusCode,200);
    assert.ok(!calls.some(x=>x.url.includes('/auth/v1/invite')||x.url.includes('/auth/v1/recover')||x.url.includes('/admin/users')));
    const generated=calls.find(x=>x.url.endsWith('/auth/v1/admin/generate_link'));
    assert.deepEqual(generated.payload,{type:'recovery',email:'recipient@example.test',
        redirect_to:'https://tms.retodo-ops.com/reset-password.html'});
    const link=calls.findIndex(x=>x.payload?.p_action==='link_invite');
    const mail=calls.findIndex(x=>x.url==='https://gmail.googleapis.com/gmail/v1/users/me/messages/send');
    assert.ok(link<mail);
});
test('failed email preserves created resource ID for safe retry and records failure',async()=>{
    const calls=mock({failMail:true});const response=await handler(event({action:'create_internal',request_id:request,payload:{name:'Internal'}}));
    const result=JSON.parse(response.body);
    assert.equal(response.statusCode,400);assert.equal(result.resource_id,resource);
    assert.equal(calls.at(-1).payload.p_action,'invite_failed');
    assert.ok(!response.body.includes('smtp secret'));
    assert.ok(!calls.some(x=>x.options.method==='DELETE'));
});
test('failed Gmail authorization leaks no provider detail and never activates access',async()=>{
    const calls=mock({failAuth:true});const response=await handler(event({action:'invite',resource_id:resource}));
    assert.equal(response.statusCode,400);
    assert.equal(calls.at(-1).payload.p_action,'invite_failed');
    assert.ok(!calls.some(x=>x.url==='https://gmail.googleapis.com/gmail/v1/users/me/messages/send'));
    assert.ok(!response.body.includes('provider-private-detail'));
    assert.ok(!calls.some(x=>x.payload?.p_action==='invite_sent'));
});
test('link conflicts prevent recovery mail to existing account',async()=>{
    const calls=mock({confirmed:true,failLink:true});const response=await handler(event({action:'invite',resource_id:resource}));
    assert.equal(response.statusCode,400);
    assert.ok(!calls.some(x=>x.url==='https://gmail.googleapis.com/gmail/v1/users/me/messages/send'));
});
test('an invalid generated action link is rejected before linking or sending email',async()=>{
    const calls=mock({badLink:true});const response=await handler(event({action:'invite',resource_id:resource}));
    assert.equal(response.statusCode,400);
    assert.ok(!calls.some(x=>x.payload?.p_action==='link_invite'));
    assert.ok(!calls.some(x=>x.url==='https://gmail.googleapis.com/gmail/v1/users/me/messages/send'));
    assert.ok(!response.body.includes('unit-test-token'));
});
test('registration sends only name to server RPC, never grants a body-supplied role',async()=>{
    const calls=mock();const response=await handler(event({action:'register',name:'Linguist',role:'admin',actor_id:request}));
    assert.equal(response.statusCode,200);assert.equal(calls.length,2);
    assert.deepEqual(calls[1].payload.p_payload,{name:'Linguist'});
    assert.equal(JSON.parse(response.body).pending_approval,true);
});
test('internal creation requires an idempotency key',async()=>{
    const calls=mock();const response=await handler(event({action:'create_internal',payload:{}}));
    assert.equal(response.statusCode,400);assert.equal(calls.length,0);
});
test('internal retry preserves supplied creation request ID',async()=>{
    const calls=mock();await handler(event({action:'create_internal',request_id:request,payload:{name:'Internal'}}));
    assert.equal(calls.find(x=>x.payload?.p_action==='create_internal').payload.p_request_id,request);
});

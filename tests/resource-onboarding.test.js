'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {handler} = require('../netlify/functions/resource-onboarding');
const actor = '11111111-1111-4111-8111-111111111111';
const resource = '22222222-2222-4222-8222-222222222222';
const request = '33333333-3333-4333-8333-333333333333';
const originalFetch = global.fetch;
process.env.SUPABASE_URL = 'https://test.supabase.co';
process.env.SUPABASE_SERVICE_ROLE_KEY = 'test-server-secret';
process.env.TMS_SITE_URL = 'https://tms.retodo-ops.com';
test.after(()=>{global.fetch=originalFetch;});
function event(body, overrides={}) { return {httpMethod:'POST',headers:{authorization:'Bearer user-token',origin:process.env.TMS_SITE_URL},body:JSON.stringify(body),...overrides}; }
function mock({confirmed=false,denyPrepare=false,failMail=false,failLink=false,unauthorized=false}={}) {
    const calls=[];
    global.fetch=async (url,options)=>{
        const payload=options.body?JSON.parse(options.body):null;
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
        } else if(failMail) {status=429;value={message:'smtp secret must not leak'};}
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
test('new account uses invitation then links it; no password or role sent to Auth',async()=>{
    const calls=mock();const response=await handler(event({action:'invite',resource_id:resource,redirect_to:'https://evil.test',password:'malicious'}));
    assert.equal(response.statusCode,200);
    const mail=calls.find(x=>x.url.includes('/invite?'));
    const mailUrl=new URL(mail.url);
    assert.equal(mailUrl.pathname,'/auth/v1/invite');
    assert.equal(mailUrl.searchParams.get('redirect_to'),'https://tms.retodo-ops.com/reset-password.html');
    assert.deepEqual(mail.payload,{email:'recipient@example.test',data:{full_name:'Test'}});
    assert.equal(Object.hasOwn(mail.payload,'redirect_to'),false);
    assert.deepEqual(calls.filter(x=>x.payload?.p_action).map(x=>x.payload.p_action),['prepare_invite','link_invite','invite_sent']);
});
test('existing confirmed account is linked then sent recovery; never created or password overwritten',async()=>{
    const calls=mock({confirmed:true});const response=await handler(event({action:'invite',resource_id:resource}));
    assert.equal(response.statusCode,200);
    assert.ok(!calls.some(x=>x.url.includes('/invite?')||x.url.includes('/admin/users')));
    const link=calls.findIndex(x=>x.payload?.p_action==='link_invite');
    const mail=calls.findIndex(x=>x.url.includes('/recover?'));
    assert.ok(link<mail);
    const mailUrl=new URL(calls[mail].url);
    assert.equal(mailUrl.pathname,'/auth/v1/recover');
    assert.equal(mailUrl.searchParams.get('redirect_to'),'https://tms.retodo-ops.com/reset-password.html');
    assert.deepEqual(calls[mail].payload,{email:'recipient@example.test'});
    assert.equal(Object.hasOwn(calls[mail].payload,'redirect_to'),false);
});
test('failed email preserves created resource ID for safe retry and records failure',async()=>{
    const calls=mock({failMail:true});const response=await handler(event({action:'create_internal',request_id:request,payload:{name:'Internal'}}));
    const result=JSON.parse(response.body);
    assert.equal(response.statusCode,400);assert.equal(result.resource_id,resource);
    assert.equal(calls.at(-1).payload.p_action,'invite_failed');
    assert.ok(!response.body.includes('smtp secret'));
    assert.ok(!calls.some(x=>x.options.method==='DELETE'));
});
test('link conflicts prevent recovery mail to existing account',async()=>{
    const calls=mock({confirmed:true,failLink:true});const response=await handler(event({action:'invite',resource_id:resource}));
    assert.equal(response.statusCode,400);assert.ok(!calls.some(x=>x.url.endsWith('/recover')));
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

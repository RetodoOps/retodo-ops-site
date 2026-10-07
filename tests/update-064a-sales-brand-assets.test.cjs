'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),crypto=require('node:crypto'),{execFileSync}=require('node:child_process');
const signature=require('../tms/sales-signature'),gmail=require('../netlify/functions/_shared/sales-gmail');
const sourceHash='747a6f6ef984b726bb5efa86737e513dc76b16296453099d28b090fc47cc4890';
test('Corrected signature embeds the exact supplied Drive logo at its square aspect ratio',()=>{
 const asset=signature.logoAsset(signature.DEFAULTS),bytes=Buffer.from(asset.base64,'base64');
 assert.equal(signature.DEFAULTS.version,2);assert.equal(crypto.createHash('sha256').update(bytes).digest('hex'),sourceHash);
 assert.equal(bytes.readUInt32BE(16),600);assert.equal(bytes.readUInt32BE(20),600);
 const html=signature.html(signature.DEFAULTS);assert.match(html,/width="48" height="48"/);assert.match(html,/Retodo <span style="color:#0ea5e9;">Ops/);assert.doesNotMatch(html,/width="110"|#136f7a/);
});
test('Previously reviewed renderer 1 HTML remains byte-for-byte identical after adding renderer 2',()=>{
 const hash=x=>crypto.createHash('sha256').update(x).digest('hex');
 const body='An approved message\nwith unchanged content.';
 assert.equal(hash(signature.html(signature.LEGACY_DEFAULTS)),"ba9f5f06c1b5ed4ddbbc1930303ebd1c978a887399ca9ffae988b8bea546f81c");
 assert.equal(hash(signature.messageHtml(body,signature.LEGACY_DEFAULTS)),"9f0e1d8ff4b963bb5181377337bd6fef53d99d1ceeb33e0e19d17374590437cb");
 assert.equal(hash(Buffer.from(signature.logoAsset(signature.LEGACY_DEFAULTS).base64,'base64')),"88306ca31eddc445b4ab3dce26b79a3f07b5ad1450e87301375a3fe8f7b588e8");
});
test('Delivered renderer 2 MIME uses the same reviewed brand bytes and versioned image reference',()=>{
 const id='00000000-0000-0000-0000-000000000064';
 const raw=Buffer.from(gmail.buildMime({id,subject:'Brand check',body:'Reviewed text',signature:{...signature.DEFAULTS},rfc_id:`<sales.${id}@retodo-ops.com>`,attachments:[]},{recipient:'test@example.invalid',sender:'eli.s@retodo-ops.com',reply_to:'eli.s@retodo-ops.com'}),'base64url');
 const result=JSON.parse(execFileSync('python3',['-c',`import json,sys,hashlib,email.policy
from email.parser import BytesParser
m=BytesParser(policy=email.policy.default).parsebytes(sys.stdin.buffer.read())
parts=list(m.walk());image=next(p for p in parts if p.get_content_type()=='image/png');html=next(p for p in parts if p.get_content_type()=='text/html').get_content()
print(json.dumps({'hash':hashlib.sha256(image.get_payload(decode=True)).hexdigest(),'cid':str(image['Content-ID']),'html':html,'disposition':image.get_content_disposition(),'defects':[str(d) for p in parts for d in p.defects]}))`],{input:raw,encoding:'utf8'}));
 assert.equal(result.hash,sourceHash);assert.equal(result.cid,'<retodo-logo-v2@retodo-ops.com>');assert.equal(result.disposition,'inline');assert.deepEqual(result.defects,[]);
 assert.ok(result.html.includes(signature.messageHtml('Reviewed text',signature.DEFAULTS,{logoSrc:'cid:retodo-logo-v2@retodo-ops.com'})));
});

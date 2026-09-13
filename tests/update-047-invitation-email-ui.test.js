'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {readFileSync}=require('node:fs');
const path=require('node:path');

const root=path.resolve(__dirname,'..');
const read=file=>readFileSync(path.join(root,file),'utf8');

test('invitation UI blocks known provider typos and requires exact re-entry',()=>{
    const source=read('tms/onboarding.js');
    assert.match(source,/\['gmai\.com','gmail\.com'\]/);
    assert.match(source,/requestExactEmailConfirmation/);
    assert.match(source,/prompt\(/);
    assert.match(source,/confirmed_email:confirmedEmail/);
    assert.match(source,/Nothing was sent/);
});

test('linked External Resource email edits use the protected correction action',()=>{
    const source=read('tms/resource.js');
    assert.match(source,/linkedEmailChange/);
    assert.match(source,/appRole!=='admin'/);
    assert.match(source,/action:'correct_email'/);
    assert.match(source,/request_id:crypto\.randomUUID\(\)/);
    assert.match(source,/replacement invitation sent/);
});

test('Internal Resource creation also confirms the exact invitation address',()=>{
    const source=read('tms/resources.js');
    assert.match(source,/requestExactEmailConfirmation\(payload\.email/);
    assert.match(source,/action:'create_internal'/);
    assert.match(source,/confirmed_email:confirmedEmail/);
});

test('Delivery tab badge counts effective Ready files only',()=>{
    const html=read('tms/job.html'),source=read('tms/job.js');
    assert.match(html,/id="deliveryFileCount"/);
    assert.match(source,/updateDeliveryFileBadge/);
    assert.match(source,/upload_status\|\|\(file\.archived_at\?'Archived':'Ready'\)/);
    assert.match(source,/==='Ready'/);
    assert.match(source,/readyCount===0/);
});

test('existing invitation scripts retain Update 047 cache keys; changed pages use Update 048',()=>{
    assert.match(read('tms/resource.html'),/onboarding\.js\?v=047/);
    assert.match(read('tms/resource.html'),/resource\.js\?v=048/);
    assert.match(read('tms/resources.html'),/resources\.js\?v=047/);
    assert.match(read('tms/job.html'),/job\.js\?v=048/);
});

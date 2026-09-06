let accounts = [], clients = [], specializations = [], accountSpecializations = [];
const esc = value => String(value ?? '').replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;').replaceAll("'",'&#039;');
const el = id => document.getElementById(id);
const value = id => el(id).value.trim();
const accountById = id => accounts.find(account => account.id === id);
const specializationById = id => specializations.find(item => item.id === id);

function toggleSub(id,item){el(id).classList.toggle('open');item.classList.toggle('open')}
function closeModal(id){el(id).classList.add('hidden');document.querySelectorAll('#'+id+' .error-msg').forEach(node=>node.classList.add('hidden'))}
function setError(message){const node=el('accountError');node.textContent=message;node.classList.remove('hidden')}
function normalizedCode(raw){return raw.toUpperCase().replace(/[^A-Z0-9]/g,'').slice(0,12)}
function statusPill(status){const cls=status==='Active'?'pill-green':status==='On Hold'?'pill-amber':'pill-red';return '<span class="pill '+cls+'">'+esc(status||'Active')+'</span>'}
function formatDate(date){return date?new Date(date).toLocaleDateString('en-GB'):'—'}

function filteredAccounts(){
  const query=value('accountSearch').toLowerCase(),clientId=el('accountClientFilter').value,status=el('accountStatusFilter').value;
  return accounts.filter(account=>{
    const client=clients.find(row=>row.id===account.client_id),hay=[account.name,account.code,client?.name,client?.code].filter(Boolean).join(' ').toLowerCase();
    return (!query||hay.includes(query))&&(!clientId||account.client_id===clientId)&&(!status||account.restriction_status===status);
  });
}
function renderFilters(){
  const current=el('accountClientFilter').value;
  el('accountClientFilter').innerHTML='<option value="">All clients</option>'+clients.map(client=>'<option value="'+client.id+'">'+esc(client.name)+(client.code?' · '+esc(client.code):'')+'</option>').join('');
  if(clients.some(client=>client.id===current))el('accountClientFilter').value=current;
}
function renderAccounts(){
  const rows=filteredAccounts(),body=el('accountsTbody');
  el('accountCount').textContent=rows.length+' account'+(rows.length===1?'':'s');
  if(!rows.length){body.innerHTML='<tr class="state-row"><td colspan="8">No accounts match the current filters.</td></tr>';return}
  body.innerHTML=rows.map(account=>{
    const client=clients.find(row=>row.id===account.client_id),names=accountSpecializations.filter(link=>link.account_id===account.id).map(link=>specializationById(link.specialization_id)?.name).filter(Boolean);
    return '<tr class="clickable-row" data-id="'+account.id+'"><td><div class="customer-main">'+esc(client?.name||'—')+'</div><div class="customer-sub">'+esc(client?.code||'')+'</div></td><td><span class="code-badge">'+esc(account.code||'—')+'</span></td><td><div class="customer-main">'+esc(account.name)+'</div></td><td><div class="tag-list">'+(names.length?names.map(name=>'<span class="tag">'+esc(name)+'</span>').join(''):'<span class="muted">None</span>')+'</div></td><td>'+esc(account.default_production_mode||'Not selected')+'</td><td>'+esc(account.default_cat_system||'—')+'</td><td>'+statusPill(account.restriction_status)+'</td><td>'+formatDate(account.updated_at)+'</td></tr>';
  }).join('');
  body.querySelectorAll('.clickable-row').forEach(row=>row.addEventListener('click',()=>openAccountModal(row.dataset.id)));
}
function renderSpecializations(selected=[]){
  el('a-specializations').innerHTML=specializations.filter(item=>item.active!==false||selected.includes(item.id)).map(item=>'<label class="checkbox-row"><input type="checkbox" value="'+item.id+'" '+(selected.includes(item.id)?'checked':'')+'>'+esc(item.name)+(item.active===false?' · inactive':'')+'</label>').join('');
}
function populateClientOptions(selected=''){
  el('a-client').innerHTML='<option value="">Select Client…</option>'+clients.map(client=>'<option value="'+client.id+'" '+(client.id===selected?'selected':'')+'>'+esc(client.name)+(client.code?' · '+esc(client.code):'')+'</option>').join('');
}
function openAccountModal(accountId=null){
  const account=accountById(accountId),selected=accountSpecializations.filter(link=>link.account_id===accountId).map(link=>link.specialization_id);
  el('accountModalTitle').textContent=account?'Edit account':'Add account';
  const fields={'a-id':account?.id,'a-name':account?.name,'a-code':account?.code,'a-source':account?.default_source_language,'a-cat':account?.default_cat_system,'a-production':account?.default_production_mode||'Not selected','a-blind':account?.blind_cv_label,'a-instructions':account?.instructions,'a-terminology':account?.terminology_notes,'a-communication':account?.communication_boundaries,'a-confidentiality':account?.confidentiality_notes,'a-restriction':account?.restriction_status||'Active','a-restriction-reason':account?.restriction_reason};
  Object.entries(fields).forEach(([id,fieldValue])=>el(id).value=fieldValue??'');
  populateClientOptions(account?.client_id||'');el('a-disclose').checked=!!account?.allow_name_in_blind_cv;renderSpecializations(selected);el('accountError').classList.add('hidden');el('accountModal').classList.remove('hidden');el('a-client').focus();
}
async function saveAccount(){
  const accountId=value('a-id'),clientId=el('a-client').value,name=value('a-name'),selected=[...document.querySelectorAll('#a-specializations input:checked')].map(input=>input.value);
  if(!clientId)return setError('Select a Client.');
  if(!name)return setError('Account name is required.');
  if(!selected.length)return setError('Select at least one Account specialization.');
  const payload={client_id:clientId,name,code:normalizedCode(value('a-code'))||null,default_source_language:value('a-source')||null,default_cat_system:value('a-cat')||null,default_production_mode:value('a-production')||'Not selected',blind_cv_label:value('a-blind')||null,allow_name_in_blind_cv:el('a-disclose').checked,instructions:value('a-instructions')||null,terminology_notes:value('a-terminology')||null,communication_boundaries:value('a-communication')||null,confidentiality_notes:value('a-confidentiality')||null,restriction_status:value('a-restriction'),restriction_reason:value('a-restriction-reason')||null};
  const result=accountId?await _sb.from('client_accounts').update(payload).eq('id',accountId).select('id').single():await _sb.from('client_accounts').insert(payload).select('id').single();
  if(result.error)return setError(result.error.code==='23505'?'That Account name already exists for this Client.':result.error.message);
  const savedId=result.data.id,deletion=await _sb.from('client_account_specializations').delete().eq('account_id',savedId);
  if(deletion.error)return setError('Account saved, but its specializations could not be updated: '+deletion.error.message);
  const insertion=await _sb.from('client_account_specializations').insert(selected.map(id=>({account_id:savedId,specialization_id:id,is_default:true})));
  if(insertion.error)return setError('Account saved, but its specializations could not be updated: '+insertion.error.message);
  closeModal('accountModal');await loadAccounts();window.TMS_QUICK_NAV?.recordVisit('Account',savedId,name,'Account');
}
async function loadAccounts(){
  const [a,c,s,l]=await Promise.all([_sb.from('client_accounts').select('*').order('name'),_sb.from('clients').select('id,name,code').order('name'),_sb.from('specializations').select('id,name,active').order('name'),_sb.from('client_account_specializations').select('account_id,specialization_id,is_default')]);
  if(a.error)return setError(a.error.message);
  accounts=a.data||[];clients=c.data||[];specializations=s.data||[];accountSpecializations=l.data||[];renderFilters();renderAccounts();
}
el('accountSearch').addEventListener('input',renderAccounts);el('accountClientFilter').addEventListener('change',renderAccounts);el('accountStatusFilter').addEventListener('change',renderAccounts);
(async()=>{const user=await requireAuth();if(!user)return;await loadAccounts()})();

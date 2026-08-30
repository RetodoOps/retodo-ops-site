let jobId, job, project, assignedResource, offers = [], offerResources = new Map();
let specializations = [], projectSpecializations = [], issues = [], purchaseOrder, poLines = [], poVersions = [];
let candidateRows = [], selectedCandidateId = null, currentUser, currentRole = 'user';
let overviewCandidates = [], resourceRates = [];

const esc = value => String(value ?? '').replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;').replaceAll("'",'&#039;');
const val = id => document.getElementById(id).value.trim();
const nullable = id => val(id) || null;
const money = (amount, currency = purchaseOrder?.currency || job?.supplier_currency || 'EUR') => `${Number(amount || 0).toFixed(2)} ${currency}`;
const resourceName = resource => resource?.legal_name || resource?.company_name || resource?.internal_number || 'Unknown Resource';
const toLocalDT = iso => { if(!iso)return ''; const d=new Date(iso),p=n=>String(n).padStart(2,'0'); return `${d.getFullYear()}-${p(d.getMonth()+1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`; };
const datePart = iso => toLocalDT(iso).slice(0,10);
const timePart = iso => toLocalDT(iso).slice(11,16);
const combineDateTime = (dateId,timeId) => {const date=val(dateId);return date?`${date}T${val(timeId)||'17:00'}`:null};
const fourHoursFromNow = () => new Date(Date.now()+4*60*60*1000).toISOString();

function closeModal(id){document.getElementById(id).classList.add('hidden')}
function showError(message,id='jobError'){const el=document.getElementById(id);el.textContent=message;el.classList.remove('hidden');el.scrollIntoView({behavior:'smooth',block:'nearest'})}
function clearError(id='jobError'){const el=document.getElementById(id);el.textContent='';el.classList.add('hidden')}
function setStatus(message){const el=document.getElementById('saveStatus');el.textContent=message;clearTimeout(setStatus.timer);setStatus.timer=setTimeout(()=>el.textContent='',4000)}
function specName(id){return specializations.find(row=>row.id===id)?.name || 'Non-defined'}
function eligibleResource(resource){return ['Assignable','Proven','Preferred'].includes(resource.resource_status)}
function rateLanguages(rate,side){const list=rate?.[`${side}_languages`];if(Array.isArray(list)&&list.length)return list;const scalar=rate?.[`${side}_language`];return scalar?[scalar]:[]}
function rateLabel(rate){const specificity=rate.specialization_id?specName(rate.specialization_id):'All specializations',languages=`${rateLanguages(rate,'source').join(', ')||'Any'} → ${rateLanguages(rate,'target').join(', ')||'Any'}`,band=rate.cat_band?` · ${rate.cat_band}`:'';return `${Number(rate.rate).toFixed(4).replace(/0+$/,'').replace(/\.$/,'')} ${rate.currency} / ${rate.unit} · ${languages} · ${specificity}${band}`}
function overviewTerms(){return {service_type:val('j-service')||job.service_type,source_language:val('j-source')||job.source_language,target_language:val('j-target')||job.target_language,specialization_id:val('j-specialization')||job.specialization_id,unit:val('j-unit')||job.unit}}
function rateMismatchReasons(rate,resourceId){const terms=overviewTerms(),reasons=[],sources=rateLanguages(rate,'source'),targets=rateLanguages(rate,'target');if(rate.resource_id!==resourceId)reasons.push('different Resource');if(rate.base_rate_id)reasons.push('CAT child row');if(rate.status!=='Approved')reasons.push(`status ${rate.status}`);if(rate.active===false)reasons.push('inactive');if(rate.service_type!==terms.service_type)reasons.push(`Service ${rate.service_type} ≠ ${terms.service_type}`);if(rate.unit!==terms.unit)reasons.push(`Unit ${rate.unit} ≠ ${terms.unit||'not set'}`);if(sources.length&&!sources.includes(terms.source_language))reasons.push(`Source ${sources.join(', ')} does not include ${terms.source_language||'not set'}`);if(targets.length&&!targets.includes(terms.target_language))reasons.push(`Target ${targets.join(', ')} does not include ${terms.target_language||'not set'}`);if(rate.specialization_id&&rate.specialization_id!==terms.specialization_id)reasons.push(`Specialization ${specName(rate.specialization_id)} ≠ ${specName(terms.specialization_id)}`);return reasons}
function matchingRate(rate,resourceId){return rateMismatchReasons(rate,resourceId).length===0}
async function fillRateSelect(selectId,resourceId){const select=document.getElementById(selectId),help=document.getElementById(selectId==='o-rate'?'o-rate-help':'j-rate-help');if(!resourceId){select.innerHTML='<option value="">Select Resource first…</option>';select.disabled=true;help.textContent='';return}select.innerHTML='<option value="">Loading approved rates…</option>';select.disabled=true;help.textContent='Checking the selected Resource rate cards…';const {data,error}=await _sb.from('resource_rates').select('*').eq('resource_id',resourceId).eq('status','Approved').eq('active',true).is('base_rate_id',null).order('created_at',{ascending:false});if(error){select.innerHTML='<option value="">Rate lookup failed</option>';help.textContent=error.message;return}resourceRates=data||[];const matches=resourceRates.filter(rate=>matchingRate(rate,resourceId)).sort((a,b)=>Number(!!b.specialization_id)-Number(!!a.specialization_id)),nonMatches=resourceRates.filter(rate=>!matchingRate(rate,resourceId));let html=matches.length?'<option value="">Select approved matching rate…</option>'+matches.map(rate=>`<option value="${rate.id}">${esc(rateLabel(rate))}</option>`).join(''):'<option value="">No exact matching approved rate</option>';if(nonMatches.length)html+=`<optgroup label="Approved cards that do not match this Job">${nonMatches.map(rate=>`<option disabled>${esc(rateLabel(rate))} — ${esc(rateMismatchReasons(rate,resourceId).join('; '))}</option>`).join('')}</optgroup>`;select.innerHTML=html;select.disabled=!resourceRates.length;if(matches.length===1)select.value=matches[0].id;help.textContent=matches.length?`${matches.length} matching approved base rate${matches.length===1?'':'s'} found.${matches.length===1?' Selected automatically.':''}`:resourceRates.length?'Approved base rate cards exist, but none matches this Job. Open the dropdown to see the exact mismatch.':'This Resource has no active Approved base rate card.';if(selectId==='o-rate')updateOfferCurrency()}
function updateOfferCurrency(){const rate=resourceRates.find(item=>item.id===val('o-rate'));document.getElementById('o-currency').value=rate?.currency||''}
function statusClass(status){return status==='Accepted'||status==='Approved'?'pill-green':status==='Declined'||status==='Withdrawn'||status==='Cancelled'?'pill-red':status==='Sent'||status==='Viewed'||status==='In Progress'?'pill-blue':status==='Expired'||status==='Revision Required'?'pill-amber':''}

function populateHeader(){
  document.title=`${job.job_number} — RetodoOps TMS`;
  document.getElementById('jobTitle').textContent=job.job_number;
  document.getElementById('jobBreadcrumb').textContent=job.job_number;
  document.getElementById('jobSubtitle').textContent=`${project.display_name} · ${job.source_language||'—'} → ${job.target_language||'—'} · ${job.service_type}`;
  const projectLink=document.getElementById('projectLink'); projectLink.href=`project.html?id=${project.id}`; projectLink.textContent=project.display_name;
  const resourceLink=document.getElementById('openResourceLink');
  if(assignedResource){resourceLink.href=`resource.html?id=${assignedResource.id}`;resourceLink.classList.remove('hidden')}else resourceLink.classList.add('hidden');
}

function populateOverview(){
  const fields={'j-number':job.job_number,'j-status':job.status,'j-deadline-date':datePart(job.deadline),'j-deadline-time':timePart(job.deadline),'j-service':job.service_type,'j-source':job.source_language,'j-target':job.target_language,'j-quantity':job.quantity,'j-unit':job.unit,'j-rate':job.supplier_rate,'j-amount':job.resource_id?money(job.supplier_amount,job.supplier_currency):'','j-notes':job.notes};
  Object.entries(fields).forEach(([id,value])=>document.getElementById(id).value=value??'');
  document.getElementById('j-specialization').innerHTML=projectSpecializations.map(link=>{const spec=specializations.find(item=>item.id===link.specialization_id);return spec?`<option value="${spec.id}" ${spec.id===job.specialization_id?'selected':''}>${esc(spec.name)}</option>`:''}).join('');
  document.getElementById('j-po-required').checked=!!job.po_required;
  ['j-service','j-source','j-target','j-specialization','j-quantity','j-unit','j-deadline-date','j-deadline-time','j-status','j-po-required','j-notes'].forEach(id=>document.getElementById(id).disabled=false);
  const resourceLabel=assignedResource?`${assignedResource.internal_number} · ${resourceName(assignedResource)}`:'No Resource assigned';
  document.getElementById('jobSummary').innerHTML=`<div><span>Assigned Resource</span><strong>${esc(resourceLabel)}</strong></div><div><span>Job status</span><strong><span class="pill ${statusClass(job.status)}">${esc(job.status)}</span></strong></div><div><span>Supplier value</span><strong>${job.resource_id?money(job.supplier_amount,job.supplier_currency):'—'}</strong></div><div><span>Supplier PO</span><strong>${purchaseOrder?esc(purchaseOrder.po_number):job.po_required?'Pending assignment':'Not required'}</strong></div>`;
}

async function loadOverviewCandidates(){
  const candidateSelect=document.getElementById('j-candidate'),rateSelect=document.getElementById('j-rate-select');
  document.getElementById('j-rate-help').textContent='';
  const activeOffer=offers.find(offer=>['Draft','Sent','Viewed'].includes(offer.status));
  if(job.resource_id){candidateSelect.innerHTML=`<option value="${job.resource_id}">${esc(resourceName(assignedResource))} · assigned</option>`;candidateSelect.disabled=true;document.getElementById('j-create-offer').disabled=true;await fillRateSelect('j-rate-select',job.resource_id);if(resourceRates.some(rate=>rate.id===job.resource_rate_id))rateSelect.value=job.resource_rate_id;document.getElementById('j-rate-help').textContent+=' Select another matching Approved rate and Save to revise the Job and PO.';return}
  if(activeOffer){const candidate=offerResources.get(activeOffer.resource_id);candidateSelect.innerHTML=`<option>${esc(resourceName(candidate))} · ${esc(activeOffer.status)} Offer</option>`;candidateSelect.disabled=true;rateSelect.innerHTML=`<option>${activeOffer.supplier_rate??'Rate pending'} ${esc(activeOffer.currency||'')}</option>`;rateSelect.disabled=true;document.getElementById('j-create-offer').disabled=true;return}
  const {data,error}=await _sb.rpc('search_job_candidates',{p_job_id:jobId,p_search:null,p_limit:100});
  if(error){candidateSelect.innerHTML='<option>Resource search failed</option>';candidateSelect.disabled=true;return}
  overviewCandidates=(data||[]).filter(eligibleResource);candidateSelect.innerHTML='<option value="">Select assignable Resource…</option>'+overviewCandidates.map(resource=>`<option value="${resource.id}">${esc(resource.internal_number)} · ${esc(resourceName(resource))} · ${esc(resource.resource_status)}</option>`).join('');candidateSelect.disabled=!overviewCandidates.length;rateSelect.innerHTML='<option value="">Select Resource first…</option>';rateSelect.disabled=true;document.getElementById('j-create-offer').disabled=!overviewCandidates.length;if(!overviewCandidates.length)candidateSelect.innerHTML='<option value="">No Active Assignable, Proven or Preferred Resources</option>';
}

async function createOverviewOffer(){clearError();const resourceId=val('j-candidate'),rateId=val('j-rate-select');if(!resourceId)return showError('Select a matching Resource.');if(!rateId)return showError('Select an approved matching rate from the Resource profile.');const {error}=await _sb.rpc('create_job_offer_from_rate',{p_job_id:jobId,p_resource_id:resourceId,p_resource_rate_id:rateId,p_response_due_at:fourHoursFromNow(),p_quantity:val('j-quantity')===''?null:Number(val('j-quantity')),p_message:null,p_client_identity_disclosed:false,p_override:false,p_override_reason:null});if(error)return showError(error.message);await loadJob();setStatus('Draft Offer created from the selected Resource rate ✓')}

async function saveJob(){
  clearError();
  if(!val('j-specialization'))return showError('Job specialization is required.');
  if(job.resource_id && val('j-status')==='Unassigned')return showError('An assigned Job cannot return to Unassigned. Cancel it or create a new Job.');
  if(!job.resource_id&&['In Progress','Delivered','Revision Required','Approved'].includes(val('j-status')))return showError('Assign a Resource through an accepted Job Offer before moving this Job into production.');
  if(!val('j-source')||!val('j-target'))return showError('Source and Target languages are required.');
  if(!TMS_REF.languages.includes(val('j-source'))||!TMS_REF.languages.includes(val('j-target')))return showError('Choose Source and Target from the shared language list.');
  const termsChanged=val('j-service')!==job.service_type||val('j-source')!==(job.source_language||'')||val('j-target')!==(job.target_language||'')||val('j-specialization')!==job.specialization_id||Number(val('j-quantity')||0)!==Number(job.quantity||0)||val('j-unit')!==(job.unit||'');
  if(job.resource_id&&termsChanged&&!val('j-rate-select'))return showError('Select an Approved Supplier rate matching the edited Job terms.');
  const payload={status:val('j-status'),deadline:combineDateTime('j-deadline-date','j-deadline-time'),service_type:val('j-service'),source_language:val('j-source'),target_language:val('j-target'),specialization_id:val('j-specialization'),quantity:val('j-quantity')===''?null:Number(val('j-quantity')),unit:val('j-unit'),po_required:document.getElementById('j-po-required').checked,notes:nullable('j-notes'),resource_rate_id:job.resource_id?nullable('j-rate-select'):null};
  const {data,error}=await _sb.rpc('save_job_overview',{p_job_id:jobId,p_payload:payload});if(error)return showError(error.message);
  await loadJob();setStatus(Number(data)>0?`Job saved · Supplier PO version ${data} created ✓`:'Job saved ✓');
}

function renderOffers(){
  document.getElementById('offerCount').textContent=offers.length;
  const active=offers.some(offer=>['Draft','Sent','Viewed'].includes(offer.status));
  document.getElementById('newOfferBtn').disabled=active||!!job.resource_id||['Approved','Cancelled'].includes(job.status);
  const body=document.getElementById('offersTbody');
  if(!offers.length){body.innerHTML='<tr class="state-row"><td colspan="7">No offers yet. Select an assignable Resource and its approved rate card to begin.</td></tr>';return}
  body.innerHTML=offers.map(offer=>{
    const resource=offerResources.get(offer.resource_id), actions=[];
    if(offer.status==='Draft')actions.push(`<button class="table-action" onclick="sendOffer('${offer.id}')">Mark sent</button>`);
    if(['Sent','Viewed'].includes(offer.status)){actions.push(`<button class="table-action success" onclick="answerOffer('${offer.id}','Accepted')">Record accepted</button>`,`<button class="table-action" onclick="answerOffer('${offer.id}','Declined')">Declined</button>`)}
    if(['Draft','Sent','Viewed'].includes(offer.status))actions.push(`<button class="table-action danger" onclick="withdrawOffer('${offer.id}')">Withdraw</button>`);
    return `<tr><td>${offer.sequence_number}</td><td><a class="table-link" href="resource.html?id=${offer.resource_id}">${esc(resource?.internal_number||'—')} · ${esc(resourceName(resource))}</a><div class="customer-sub">${esc(resource?.resource_status||'—')}</div></td><td><span class="pill ${statusClass(offer.status)}">${esc(offer.status)}</span>${offer.restriction_warning?'<div class="warning-text">Override recorded</div>':''}</td><td>${new Date(offer.response_due_at).toLocaleString('en-GB')}</td><td>${offer.quantity??'—'} ${esc(offer.unit||'')} × ${offer.supplier_rate??'rate pending'}<div class="customer-sub">${money(offer.amount,offer.currency)}</div></td><td>${offer.client_identity_disclosed?'<span class="pill pill-amber">Disclosed</span>':'Hidden'}</td><td><div class="table-actions">${actions.join('')}</div></td></tr>`;
  }).join('');
}

function openOfferModal(){
  clearError('offerError');selectedCandidateId=null;candidateRows=[];
  document.getElementById('candidateSearch').value='';document.getElementById('candidateResults').innerHTML='<div class="empty-compact">Search assignable Resources.</div>';
  const responseDue=fourHoursFromNow();document.getElementById('o-response-date').value=datePart(responseDue);document.getElementById('o-response-time').value=timePart(responseDue);document.getElementById('o-quantity').value=job.quantity??'';document.getElementById('o-unit').value=job.unit||'Source words';document.getElementById('o-rate').innerHTML='<option value="">Select Resource first…</option>';document.getElementById('o-rate').disabled=true;document.getElementById('o-rate-help').textContent='';document.getElementById('o-currency').value='';document.getElementById('o-message').value='';document.getElementById('o-disclose').checked=false;document.getElementById('o-disclose').disabled=currentRole!=='admin';document.getElementById('offerModal').classList.remove('hidden');searchCandidates();
}

async function searchCandidates(){
  const wrap=document.getElementById('candidateResults');wrap.innerHTML='<div class="empty-compact">Searching…</div>';
  const {data,error}=await _sb.rpc('search_job_candidates',{p_job_id:jobId,p_search:nullable('candidateSearch'),p_limit:30});
  if(error){wrap.innerHTML=`<div class="error-msg">${esc(error.message)}</div>`;return}
  candidateRows=data||[];selectedCandidateId=null;
  if(!candidateRows.length){wrap.innerHTML='<div class="empty-compact">No Active Assignable, Proven or Preferred Resources found.</div>';return}
  wrap.innerHTML=candidateRows.map(resource=>`<label class="candidate-row"><input type="radio" name="candidate" value="${resource.id}"><span><strong>${esc(resource.internal_number)} · ${esc(resourceName(resource))}</strong><small>${esc((resource.source_languages||[]).join(', ')||'No language pairs')} → ${esc((resource.target_languages||[]).join(', ')||'No target languages')} · ${esc((resource.services||[]).join(', ')||'No services')}</small><small>${esc(resource.resource_status)} · Domain: ${esc(resource.specialization_qualification)} · Account: ${esc(resource.account_qualification)} · ${esc(resource.availability_status||'Unknown availability')}</small>${resource.warning_text?`<small class="warning-text">${esc(resource.warning_text)}</small>`:''}</span><span class="pill pill-green">Selectable</span></label>`).join('');
  wrap.querySelectorAll('input[name="candidate"]').forEach(input=>input.addEventListener('change',()=>{selectedCandidateId=input.value;fillRateSelect('o-rate',selectedCandidateId)}));
}

async function createOffer(){
  clearError('offerError');if(!selectedCandidateId)return showError('Select a Resource.','offerError');if(!val('o-rate'))return showError('Select an approved matching rate from the Resource profile.','offerError');
  const args={p_job_id:jobId,p_resource_id:selectedCandidateId,p_resource_rate_id:val('o-rate'),p_response_due_at:combineDateTime('o-response-date','o-response-time'),p_quantity:val('o-quantity')===''?null:Number(val('o-quantity')),p_message:nullable('o-message'),p_client_identity_disclosed:document.getElementById('o-disclose').checked,p_override:false,p_override_reason:null};
  const {error}=await _sb.rpc('create_job_offer_from_rate',args);if(error)return showError(error.message,'offerError');closeModal('offerModal');await loadJob();setStatus('Draft offer created from Resource rate ✓');
}

async function sendOffer(id){if(!confirm('Confirm that you are sending this offer manually. The TMS will mark it Sent and create an email task for ops@retodo-ops.com.'))return;const {error}=await _sb.rpc('send_job_offer',{p_offer_id:id});if(error)return showError(error.message);await loadJob();setStatus('Offer marked Sent; email task created ✓')}
async function answerOffer(id,response){let reason=null;if(response==='Declined')reason=prompt('Optional decline reason:')||null;else if(!confirm('Record that the Resource accepted this offer? This assigns the Job and creates the Draft Supplier PO.'))return;const {error}=await _sb.rpc('respond_job_offer',{p_offer_id:id,p_response:response,p_decline_reason:reason});if(error)return showError(error.message);await loadJob();setStatus(response==='Accepted'?'Resource assigned and Draft PO created ✓':'Decline recorded ✓')}
async function withdrawOffer(id){const reason=prompt('Reason for withdrawal:');if(!reason)return;const {error}=await _sb.rpc('withdraw_job_offer',{p_offer_id:id,p_reason:reason});if(error)return showError(error.message);await loadJob();setStatus('Offer withdrawn ✓')}

function poRateSource(line={}){if(line.adjustment_type)return 'Adjustment';if(line.resource_rate_id&&line.cat_band)return `${line.cat_band}${line.discount_percent==null?'':` · ${Number(line.discount_percent).toFixed(2).replace(/\.00$/,'')}% off`}`;if(line.resource_rate_id)return 'Resource base rate';return 'Manual'}
function poLineRow(line={}){const options=['','Discount','Credit','Surcharge','Minimum fee'].map(value=>`<option value="${value}" ${value===(line.adjustment_type||'')?'selected':''}>${value||'None'}</option>`).join('');return `<tr><td><input class="po-description" value="${esc(line.description||'')}"></td><td><input class="po-quantity" type="number" step="0.001" value="${line.quantity??''}"></td><td><select class="po-unit"><option>Source words</option><option>Target words</option><option>Hours</option><option>Pages</option><option>Minutes</option><option>Fixed fee</option></select></td><td><input class="po-unit-price" type="number" step="0.0001" value="${line.unit_price??''}"></td><td><span class="rate-source-label">${esc(poRateSource(line))}</span></td><td><select class="po-adjustment">${options}</select></td><td><input class="po-amount" type="number" step="0.01" value="${line.amount??0}"></td><td><button class="del-line-btn" onclick="this.closest('tr').remove();calculatePOTotals()">×</button></td></tr>`}
function addPOLine(line={}){const body=document.getElementById('poLinesTbody');body.insertAdjacentHTML('beforeend',poLineRow(line));const row=body.lastElementChild;row.querySelector('.po-unit').value=line.unit||'Source words';wirePOLine(row);calculatePOTotals()}
function wirePOLine(row){row.querySelectorAll('input,select').forEach(el=>el.addEventListener('input',()=>{const q=Number(row.querySelector('.po-quantity').value||0),rate=Number(row.querySelector('.po-unit-price').value||0),adj=row.querySelector('.po-adjustment').value;if(el.classList.contains('po-quantity')||el.classList.contains('po-unit-price'))row.querySelector('.po-amount').value=(q*rate).toFixed(2);if(['Discount','Credit'].includes(adj))row.querySelector('.po-amount').value=(-Math.abs(Number(row.querySelector('.po-amount').value||0))).toFixed(2);calculatePOTotals()}))}
function collectPOLines(){return [...document.querySelectorAll('#poLinesTbody tr')].map((row,index)=>({description:row.querySelector('.po-description').value.trim(),quantity:row.querySelector('.po-quantity').value,unit:row.querySelector('.po-unit').value,unit_price:row.querySelector('.po-unit-price').value,adjustment_type:row.querySelector('.po-adjustment').value,amount:row.querySelector('.po-amount').value,sort_order:(index+1)*10}))}
function calculatePOTotals(){const lines=collectPOLines(),subtotal=lines.filter(x=>!x.adjustment_type).reduce((sum,x)=>sum+Number(x.amount||0),0),adjustments=lines.filter(x=>x.adjustment_type).reduce((sum,x)=>sum+Number(x.amount||0),0);document.getElementById('poSubtotal').textContent=money(subtotal);document.getElementById('poAdjustments').textContent=money(adjustments);document.getElementById('poTotal').textContent=money(subtotal+adjustments);renderPOPrint(lines,subtotal,adjustments)}

function renderPO(){
  const hasPO=!!purchaseOrder;document.getElementById('poBadge').textContent=hasPO?1:0;document.getElementById('poEmpty').classList.toggle('hidden',hasPO);document.getElementById('poWorkspace').classList.toggle('hidden',!hasPO);if(!hasPO)return;
  document.getElementById('poTitle').textContent=purchaseOrder.po_number;document.getElementById('poMeta').textContent=`${purchaseOrder.status} · Version ${purchaseOrder.current_version} · ${resourceName(assignedResource)} · Work may begin before acknowledgement`;
  const body=document.getElementById('poLinesTbody');body.innerHTML='';poLines.forEach(addPOLine);if(!poLines.length)addPOLine();
  const draft=purchaseOrder.status==='Draft',admin=currentRole==='admin';document.getElementById('savePoBtn').textContent=draft?'Save Draft':'Create Revision';document.getElementById('savePoBtn').disabled=!draft&&!admin;document.getElementById('issuePoBtn').classList.toggle('hidden',!draft);document.getElementById('issuePoBtn').disabled=!admin;document.getElementById('revisionReasonWrap').classList.toggle('hidden',draft);
  document.querySelectorAll('#poLinesTbody input,#poLinesTbody select,.add-line-btn').forEach(el=>el.disabled=!draft&&!admin);
  document.getElementById('poVersions').innerHTML=poVersions.length?poVersions.map(version=>`<div class="version-row"><strong>Version ${version.version_number}</strong><span>${esc(version.document_status)} · ${new Date(version.created_at).toLocaleString('en-GB')}</span><span>${esc(version.change_reason||'Initial issue')}</span></div>`).join(''):'<span class="muted">No issued versions yet.</span>';
  calculatePOTotals();
}

async function savePO(){const lines=collectPOLines();if(!lines.length)return showError('At least one PO line is required.');let result;if(purchaseOrder.status==='Draft')result=await _sb.rpc('save_supplier_po_draft',{p_po_id:purchaseOrder.id,p_lines:lines});else{const reason=val('poRevisionReason');if(!reason)return showError('An Administrator revision reason is required.');result=await _sb.rpc('revise_supplier_po',{p_po_id:purchaseOrder.id,p_lines:lines,p_reason:reason})}if(result.error)return showError(result.error.message);await loadJob();setStatus(purchaseOrder.status==='Draft'?'Draft PO saved ✓':'New PO version created ✓')}
async function issuePO(){if(currentRole!=='admin')return showError('Only the Administrator can issue a Supplier PO.');if(!confirm(`Issue ${purchaseOrder.po_number}? Issued facts will be locked and later changes will create a new version.`))return;const save=await _sb.rpc('save_supplier_po_draft',{p_po_id:purchaseOrder.id,p_lines:collectPOLines()});if(save.error)return showError(save.error.message);const {error}=await _sb.rpc('issue_supplier_po',{p_po_id:purchaseOrder.id});if(error)return showError(error.message);await loadJob();setStatus('Supplier PO issued; email task created ✓')}

function renderPOPrint(lines=collectPOLines(),subtotal=Number(purchaseOrder?.subtotal||0),adjustments=Number(purchaseOrder?.adjustment_amount||0)){
  if(!purchaseOrder)return;const supplier=purchaseOrder.supplier_snapshot||{};const lineHtml=lines.map(line=>`<tr><td>${esc(line.description)}</td><td>${esc(line.quantity||'')}</td><td>${esc(line.unit||'')}</td><td>${esc(line.unit_price||'')}</td><td>${money(line.amount,purchaseOrder.currency)}</td></tr>`).join('');
  document.getElementById('poPrintArea').innerHTML=`<div class="po-doc-head"><div><strong>Retodo Ops</strong><span>Supplier Purchase Order</span></div><div><h2>${esc(purchaseOrder.po_number)}</h2><span>Version ${purchaseOrder.current_version}</span></div></div><div class="po-doc-grid"><div><small>Supplier</small><strong>${esc(supplier.legal_name||supplier.company_name||resourceName(assignedResource))}</strong><span>${esc(supplier.internal_number||'')}</span><span>${esc(supplier.email||'')}</span></div><div><small>Job</small><strong>${esc(job.job_number)}</strong><span>${esc(job.service_type)} · ${esc(job.source_language||'')} → ${esc(job.target_language||'')}</span><span>Deadline: ${job.deadline?new Date(job.deadline).toLocaleString('en-GB'):'Non-defined'}</span></div></div><table><thead><tr><th>Description</th><th>Qty</th><th>Unit</th><th>Rate</th><th>Amount</th></tr></thead><tbody>${lineHtml}</tbody></table><div class="po-doc-total"><span>Subtotal ${money(subtotal,purchaseOrder.currency)}</span><span>Adjustments ${money(adjustments,purchaseOrder.currency)}</span><strong>Total ${money(subtotal+adjustments,purchaseOrder.currency)}</strong></div><p class="po-doc-note">This purchase order contains Retodo Ops project identifiers only. Client and account identity remain confidential unless expressly disclosed. Work may begin before PO acknowledgement. Confidentiality, non-disclosure and non-circumvention obligations continue to apply.</p>`;
}
function printPO(){renderPOPrint();document.body.classList.add('printing-po');window.print();setTimeout(()=>document.body.classList.remove('printing-po'),300)}

function renderIssues(){const body=document.getElementById('issuesTbody');if(!issues.length){body.innerHTML='<tr class="state-row"><td colspan="5">No delivery issues.</td></tr>';return}body.innerHTML=issues.map(issue=>`<tr><td><span class="pill ${statusClass(issue.status)}">${esc(issue.status)}</span></td><td>${esc(issue.severity||'—')}</td><td>${esc(issue.description)}</td><td>${new Date(issue.reported_at).toLocaleString('en-GB')}</td><td>${esc(issue.resolution||'—')}</td></tr>`).join('')}

async function loadJob(){
  clearError();const jobResult=await _sb.from('project_jobs').select('*').eq('id',jobId).single();if(jobResult.error)return showError(jobResult.error.message);job=jobResult.data;
  const [projectResult,specResult,projectSpecResult,offerResult,poResult,issueResult]=await Promise.all([_sb.from('projects').select('*').eq('id',job.project_id).single(),_sb.from('specializations').select('*').eq('active',true).order('name'),_sb.from('project_specializations').select('*').eq('project_id',job.project_id).order('created_at'),_sb.from('job_offers').select('*').eq('job_id',jobId).order('sequence_number'),_sb.from('supplier_purchase_orders').select('*').eq('job_id',jobId).maybeSingle(),_sb.from('job_issues').select('*').eq('job_id',jobId).order('reported_at',{ascending:false})]);
  if(projectResult.error)return showError(projectResult.error.message);project=projectResult.data;specializations=specResult.data||[];projectSpecializations=projectSpecResult.data||[];offers=offerResult.data||[];purchaseOrder=poResult.data||null;issues=issueResult.data||[];resourceRates=[];
  const resourceIds=[...new Set([job.resource_id,...offers.map(x=>x.resource_id)].filter(Boolean))];offerResources=new Map();if(resourceIds.length){const {data}=await _sb.from('resources').select('*').in('id',resourceIds);(data||[]).forEach(resource=>offerResources.set(resource.id,resource))}assignedResource=job.resource_id?offerResources.get(job.resource_id):null;
  if(purchaseOrder){const [lineResult,versionResult]=await Promise.all([_sb.from('supplier_po_lines').select('*').eq('purchase_order_id',purchaseOrder.id).order('sort_order'),_sb.from('supplier_po_versions').select('*').eq('purchase_order_id',purchaseOrder.id).order('version_number',{ascending:false})]);poLines=lineResult.data||[];poVersions=versionResult.data||[]}else{poLines=[];poVersions=[]}
  populateHeader();populateOverview();renderOffers();renderPO();renderIssues();await loadOverviewCandidates();
}

document.querySelectorAll('.record-tab').forEach(tab=>tab.addEventListener('click',()=>{document.querySelectorAll('.record-tab').forEach(t=>t.classList.toggle('active',t===tab));document.querySelectorAll('.record-pane').forEach(pane=>pane.classList.toggle('active',pane.id===`pane-${tab.dataset.tab}`))}));
document.getElementById('candidateSearch').addEventListener('keydown',event=>{if(event.key==='Enter'){event.preventDefault();searchCandidates()}});
document.getElementById('j-candidate').addEventListener('change',event=>fillRateSelect('j-rate-select',event.target.value));
['j-service','j-source','j-target','j-specialization','j-unit'].forEach(id=>document.getElementById(id).addEventListener('change',()=>{const resourceId=job.resource_id||val('j-candidate');if(resourceId)fillRateSelect('j-rate-select',resourceId)}));
document.getElementById('o-rate').addEventListener('change',updateOfferCurrency);

(async()=>{currentUser=await requireAuth();if(!currentUser)return;TMS_REF.installDatalists();const {data:profile}=await _sb.from('profiles').select('role').eq('id',currentUser.id).maybeSingle();currentRole=profile?.role||'user';jobId=new URLSearchParams(location.search).get('id');if(!jobId){location.href='dashboard.html';return}await loadJob()})();

let jobId, job, project, assignedResource, offers = [], offerResources = new Map();
let specializations = [], projectSpecializations = [], issues = [], purchaseOrders = [], purchaseOrder, poLines = [], poVersions = [], allPOVersions = [], poEmails = [];
let currentUser, currentRole = 'user';
let overviewCandidates = [], resourceRates = [];
let projectScopeLines = [], projectJobs = [];
let supplierTermsDirty = false;
let selectedPOVersionKey = null;

const esc = value => String(value ?? '').replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;').replaceAll("'",'&#039;');
const val = id => document.getElementById(id).value.trim();
const nullable = id => val(id) || null;
const money = (amount, currency = purchaseOrder?.currency || job?.supplier_currency || 'EUR') => `${Number(amount || 0).toFixed(2)} ${currency}`;
const unitMoney = (amount, currency = purchaseOrder?.currency || job?.supplier_currency || 'EUR') => `${Number(amount || 0).toFixed(4)} ${currency}`;
const roundMoney = amount => Math.round((Number(amount || 0) + Number.EPSILON) * 100) / 100;
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
const SUPPLIER_CAT_ORDER=['New words','50–74%','75–84%','85–94%','95–99%','100%','100% matches','101% / Context match','Repetitions'];
function supplierCatPrefix(){return 'j'}
function catBandKey(value){const band=String(value||'New words').toLowerCase().replaceAll('–','-').replace(/\s+/g,' ').trim();if(band==='new words')return 'newwords';if(band.startsWith('101%')||band.includes('context match'))return '101context';if(band==='100%'||band.startsWith('100% match'))return '100matches';return band.replace(/[^a-z0-9%]+/g,'')}
function existingCatState(baseId){const analysis=job?.cat_analysis||{},same=!analysis.base_rate_id||analysis.base_rate_id===baseId,rows=same&&Array.isArray(analysis.rows)?analysis.rows:[];return {exists:rows.length>0,quantities:new Map(rows.map(row=>[row.resource_rate_id,Number(row.quantity||0)]))}}
function inheritedProjectCatQuantities(){const terms=overviewTerms(),result=new Map();projectScopeLines.filter(line=>line.service_type===terms.service_type&&line.specialization_id===terms.specialization_id&&line.price_unit===terms.unit&&line.cat_band).forEach(line=>result.set(catBandKey(line.cat_band),Number(line.quantity||0)));return result}
function displayedJobCatRows(){return [...document.querySelectorAll('#j-cat-rows tr')].map(row=>({cat_band:row.dataset.band||'New words',quantity:Number(row.querySelector('.supplier-cat-quantity')?.value||0),unit:row.dataset.unit,unit_price:Number(row.dataset.rate||0),currency:row.dataset.currency||job?.supplier_currency||'EUR'}))}
function currentJobClientValue(terms,supplierRows){
  const activeJobs=projectJobs.filter(row=>!['Declined','Cancelled'].includes(row.status));
  if(activeJobs.length===1&&activeJobs[0].id===job.id)return project?.price==null?null:roundMoney(project.price);
  const quantityRows=supplierRows.length?supplierRows:[{cat_band:null,quantity:Number(val('j-quantity')||job?.quantity||0),unit:terms.unit}];let clientValue=0,matched=0;
  quantityRows.forEach(row=>{const matches=projectScopeLines.filter(line=>line.service_type===terms.service_type&&line.specialization_id===terms.specialization_id&&line.price_unit===terms.unit&&(row.cat_band?catBandKey(line.cat_band)===catBandKey(row.cat_band):!line.cat_band));matches.forEach(line=>{clientValue+=roundMoney(line.price_unit==='Fixed fee'?(Number(row.quantity||0)>0?Number(line.unit_price||0):0):Number(row.quantity||0)*Number(line.unit_price||0));matched++})});
  return matched?roundMoney(clientValue):null;
}
function jobFinancialSnapshot(){
  const terms=overviewTerms(),displayed=displayedJobCatRows(),supplierRows=displayed.length?displayed:(Array.isArray(job?.cat_analysis?.rows)?job.cat_analysis.rows:[]),supplierCurrency=supplierRows[0]?.currency||job?.supplier_currency||null;
  const poCost=!supplierTermsDirty?currentPOSupplierCost():null,supplierCost=poCost!=null?poCost:(supplierRows.length?supplierRows.reduce((sum,row)=>sum+roundMoney(row.unit==='Fixed fee'?(Number(row.quantity||0)>0?Number(row.unit_price||0):0):Number(row.quantity||0)*Number(row.unit_price||0)),0):(job?.resource_id?Number(job.supplier_amount||0):null));
  const clientValue=currentJobClientValue(terms,supplierRows);
  return {clientValue,clientCurrency:project?.currency||'EUR',supplierCost:supplierCost==null?null:roundMoney(supplierCost),supplierCurrency:poCost!=null?purchaseOrder.currency:supplierCurrency};
}
function currentPOSupplierCost(){if(!purchaseOrder)return null;const snapshotTotal=poVersions[0]?.snapshot?.total,value=snapshotTotal??purchaseOrder.total;return value==null||Number.isNaN(Number(value))?null:roundMoney(value)}
function effectiveJobSupplierCost(){const poCost=currentPOSupplierCost();return {amount:poCost??Number(job?.supplier_amount||0),currency:poCost==null?(job?.supplier_currency||'EUR'):(purchaseOrder?.currency||job?.supplier_currency||'EUR')}}
function renderJobFinancials(){
  const snapshot=jobFinancialSnapshot(),clientEl=document.getElementById('job-client-value'),supplierEl=document.getElementById('job-supplier-cost'),profitEl=document.getElementById('job-profit'),marginEl=document.getElementById('job-margin');
  if(!clientEl)return;
  clientEl.textContent=snapshot.clientValue==null?'Not priced':money(snapshot.clientValue,snapshot.clientCurrency);
  supplierEl.textContent=snapshot.supplierCost==null?'Rate pending':money(snapshot.supplierCost,snapshot.supplierCurrency||'EUR');
  if(snapshot.clientValue==null||snapshot.supplierCost==null){profitEl.textContent='—';marginEl.textContent='—';return}
  if(snapshot.clientCurrency!==(snapshot.supplierCurrency||snapshot.clientCurrency)){profitEl.textContent='Currency conversion required';marginEl.textContent='—';return}
  const profit=roundMoney(snapshot.clientValue-snapshot.supplierCost),margin=snapshot.clientValue?profit/snapshot.clientValue*100:0;
  profitEl.textContent=money(profit,snapshot.clientCurrency);marginEl.textContent=`${margin.toFixed(2)}%`;
}
function calculateSupplierCatGrid(prefix){const body=document.getElementById(`${prefix}-cat-rows`);let total=0,currency='';body.querySelectorAll('tr').forEach(row=>{const q=Number(row.querySelector('.supplier-cat-quantity').value||0),rate=Number(row.dataset.rate||0),amount=roundMoney(row.dataset.unit==='Fixed fee'?(q>0?rate:0):q*rate);row.querySelector('.supplier-cat-amount').textContent=money(amount,row.dataset.currency);total+=amount;currency=row.dataset.currency});document.getElementById(`${prefix}-cat-total`).textContent=money(total,currency||'EUR');renderJobFinancials()}
function collectSupplierCatRows(prefix){return [...document.querySelectorAll(`#${prefix}-cat-rows tr`)].map(row=>({resource_rate_id:row.dataset.rateId,quantity:Number(row.querySelector('.supplier-cat-quantity').value||0)}))}
function renderSupplierCatGrid(selectId){const prefix=supplierCatPrefix(),baseId=val(selectId),card=document.getElementById(`${prefix}-cat-card`),body=document.getElementById(`${prefix}-cat-rows`);if(!baseId){card.classList.add('hidden');body.innerHTML='';renderJobFinancials();return}const base=resourceRates.find(rate=>rate.id===baseId&&!rate.base_rate_id);if(!base){card.classList.add('hidden');renderJobFinancials();return}const children=resourceRates.filter(rate=>rate.base_rate_id===baseId),saved=existingCatState(baseId),inherited=inheritedProjectCatQuantities(),allRows=[base,...children].sort((a,b)=>SUPPLIER_CAT_ORDER.indexOf(a.cat_band||'New words')-SUPPLIER_CAT_ORDER.indexOf(b.cat_band||'New words')),rows=saved.exists?allRows.filter(rate=>saved.quantities.has(rate.id)):allRows,defaultQuantity=Number(val('j-quantity')||0);body.innerHTML=rows.map((rate,index)=>{const band=rate.cat_band||'New words',inheritedQuantity=inherited.get(catBandKey(band)),quantity=saved.quantities.has(rate.id)?saved.quantities.get(rate.id):(inheritedQuantity??(index===0?defaultQuantity:0));return `<tr data-rate-id="${rate.id}" data-band="${esc(band)}" data-rate="${rate.rate}" data-unit="${esc(rate.unit)}" data-currency="${esc(rate.currency)}"><td><strong>${esc(band)}</strong>${rate.discount_percent==null?'':`<div class="customer-sub">${Number(rate.discount_percent).toFixed(2).replace(/\.00$/,'')}% discount</div>`}</td><td><input class="supplier-cat-quantity inline-quantity" type="number" min="0" step="0.001" value="${quantity}"></td><td>${esc(rate.unit)}</td><td>${unitMoney(rate.rate,rate.currency)}</td><td class="supplier-cat-amount number-cell">${money(0,rate.currency)}</td><td><button type="button" class="del-line-btn cat-delete-btn" title="Remove this CAT row" aria-label="Remove ${esc(band)}" onclick="supplierTermsDirty=true;this.closest('tr').remove();calculateSupplierCatGrid('${prefix}')">🗑</button></td></tr>`}).join('');body.querySelectorAll('.supplier-cat-quantity').forEach(input=>input.addEventListener('input',()=>{supplierTermsDirty=true;calculateSupplierCatGrid(prefix)}));const preparingAssignment=!purchaseOrder||val('j-candidate')!==job.resource_id;card.classList.toggle('hidden',!preparingAssignment);calculateSupplierCatGrid(prefix)}
async function fillRateSelect(selectId,resourceId){const select=document.getElementById(selectId),help=document.getElementById('j-rate-help');renderSupplierCatGrid(selectId);if(!resourceId){select.innerHTML='<option value="">Select Resource first…</option>';select.disabled=true;help.textContent='';return}select.innerHTML='<option value="">Loading approved rates…</option>';select.disabled=true;help.textContent='Checking the selected Resource rate cards…';const {data,error}=await _sb.from('resource_rates').select('*').eq('resource_id',resourceId).eq('status','Approved').eq('active',true).order('created_at',{ascending:false});if(error){select.innerHTML='<option value="">Rate lookup failed</option>';help.textContent=error.message;return}resourceRates=data||[];const bases=resourceRates.filter(rate=>!rate.base_rate_id),matches=bases.filter(rate=>matchingRate(rate,resourceId)).sort((a,b)=>Number(!!b.specialization_id)-Number(!!a.specialization_id)),nonMatches=bases.filter(rate=>!matchingRate(rate,resourceId));let html=matches.length?'<option value="">Select approved matching rate…</option>'+matches.map(rate=>`<option value="${rate.id}">${esc(rateLabel(rate))}</option>`).join(''):'<option value="">No exact matching approved rate</option>';if(nonMatches.length)html+=`<optgroup label="Approved cards that do not match this Job">${nonMatches.map(rate=>`<option disabled>${esc(rateLabel(rate))} — ${esc(rateMismatchReasons(rate,resourceId).join('; '))}</option>`).join('')}</optgroup>`;select.innerHTML=html;select.disabled=!bases.length;if(matches.length===1)select.value=matches[0].id;help.textContent=matches.length?`${matches.length} matching approved base rate${matches.length===1?'':'s'} found.${matches.length===1?' Selected automatically.':''}`:bases.length?'Approved base rate cards exist, but none matches this Job. Open the dropdown to see the exact mismatch.':'This Resource has no active Approved base rate card.';renderSupplierCatGrid(selectId)}
function statusClass(status){return status==='Accepted'||status==='Approved'?'pill-green':status==='Declined'||status==='Withdrawn'||status==='Cancelled'?'pill-red':status==='Sent'||status==='Viewed'||status==='Assigned'||status==='In Progress'?'pill-blue':status==='Expired'||status==='Revision Required'?'pill-amber':''}

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
  const effectiveCost=effectiveJobSupplierCost(),fields={'j-number':job.job_number,'j-status':job.status,'j-deadline-date':datePart(job.deadline),'j-deadline-time':timePart(job.deadline),'j-service':job.service_type,'j-source':job.source_language,'j-target':job.target_language,'j-quantity':job.quantity,'j-unit':job.unit,'j-rate':job.supplier_rate,'j-amount':job.resource_id?money(effectiveCost.amount,effectiveCost.currency):'','j-notes':job.notes};
  Object.entries(fields).forEach(([id,value])=>document.getElementById(id).value=value??'');
  document.getElementById('j-specialization').innerHTML=projectSpecializations.map(link=>{const spec=specializations.find(item=>item.id===link.specialization_id);return spec?`<option value="${spec.id}" ${spec.id===job.specialization_id?'selected':''}>${esc(spec.name)}</option>`:''}).join('');
  document.getElementById('j-po-required').checked=!!job.po_required;
  ['j-service','j-source','j-target','j-specialization','j-quantity','j-unit','j-deadline-date','j-deadline-time','j-status','j-po-required','j-notes'].forEach(id=>document.getElementById(id).disabled=false);
  const resourceLabel=assignedResource?`${assignedResource.internal_number} · ${resourceName(assignedResource)}`:'No Resource assigned';
  document.getElementById('jobSummary').innerHTML=`<div><span>Assigned Resource</span><strong>${esc(resourceLabel)}</strong></div><div><span>Job status</span><strong><span class="pill ${statusClass(job.status)}">${esc(job.status)}</span></strong></div><div><span>Supplier value</span><strong>${job.resource_id?money(effectiveCost.amount,effectiveCost.currency):'—'}</strong></div><div><span>Supplier PO</span><strong>${purchaseOrder?`${esc(purchaseOrder.po_number)} · V${currentPOVersion()}`:job.po_required?'Pending assignment':'Not required'}</strong></div>`;
  renderJobFinancials();
}

async function loadOverviewCandidates(){
  const candidateSelect=document.getElementById('j-candidate'),rateSelect=document.getElementById('j-rate-select');
  document.getElementById('j-rate-help').textContent='';
  const {data,error}=await _sb.rpc('search_job_candidates',{p_job_id:jobId,p_search:null,p_limit:100});
  if(error){candidateSelect.innerHTML='<option>Resource search failed</option>';candidateSelect.disabled=true;return}
  overviewCandidates=(data||[]).filter(eligibleResource);
  if(assignedResource&&!overviewCandidates.some(resource=>resource.id===assignedResource.id))overviewCandidates.unshift(assignedResource);
  candidateSelect.innerHTML='<option value="">Select assignable Resource…</option>'+overviewCandidates.map(resource=>`<option value="${resource.id}" ${resource.id===job.resource_id?'selected':''}>${esc(resource.internal_number)} · ${esc(resourceName(resource))} · ${esc(resource.resource_status||'Current')}</option>`).join('');
  candidateSelect.disabled=!overviewCandidates.length;rateSelect.innerHTML='<option value="">Select Resource first…</option>';rateSelect.disabled=true;
  if(!overviewCandidates.length){candidateSelect.innerHTML='<option value="">No Active Assignable, Proven or Preferred Resources</option>';document.getElementById('j-create-offer').disabled=true;return}
  if(job.resource_id){await fillRateSelect('j-rate-select',job.resource_id);if(resourceRates.some(rate=>rate.id===job.resource_rate_id))rateSelect.value=job.resource_rate_id;renderSupplierCatGrid('j-rate-select')}
  updateAssignmentAction();
}

function updateAssignmentAction(){const button=document.getElementById('j-create-offer'),resourceId=val('j-candidate');if(!resourceId){button.textContent='Assign Resource & Send PO';button.disabled=true;return}const replacing=!!job.resource_id&&resourceId!==job.resource_id;button.textContent=replacing?'Reassign & Send New PO':'Assign Resource & Send PO';button.disabled=!!job.resource_id&&!replacing}
async function sendSupplierPOEmail(poId){
  const {data:{session}}=await _sb.auth.getSession();if(!session?.access_token)throw new Error('Your session expired. Sign in again.');
  const response=await fetch('/.netlify/functions/send-supplier-po',{method:'POST',headers:{'Content-Type':'application/json',Authorization:`Bearer ${session.access_token}`},body:JSON.stringify({purchase_order_id:poId})});
  const result=await response.json().catch(()=>({}));if(!response.ok||!result.ok)throw new Error(result.error||'PO email could not be sent');return result;
}
async function assignResourceAndIssuePO(){
  clearError();const resourceId=val('j-candidate'),rateId=val('j-rate-select');
  if(!resourceId)return showError('Select a Resource.');
  if(job.resource_id===resourceId)return showError('This Resource is already assigned. Change Job terms and Save to create a PO revision, or select another Resource.');
  if(!rateId)return showError('Select an Approved matching Supplier rate card.');
  const catRows=collectSupplierCatRows('j');if(!catRows.some(row=>row.quantity>0))return showError('Enter a quantity in at least one Supplier CAT row.');
  const replacing=!!job.resource_id;let reason=null;if(replacing){reason=prompt('Reason for replacing the assigned Resource and cancelling the current PO:');if(!reason)return}
  if(replacing&&!confirm('The current PO will be cancelled and a new PO will be issued and emailed to the selected Resource.'))return;
  const action=document.getElementById('j-create-offer');action.disabled=true;action.textContent='Creating and sending…';
  const {data:poId,error}=await _sb.rpc('assign_job_and_issue_po',{p_job_id:jobId,p_resource_id:resourceId,p_resource_rate_id:rateId,p_cat_rows:catRows,p_reassignment_reason:reason});
  if(error){updateAssignmentAction();return showError(error.message)}
  try{await sendSupplierPOEmail(poId)}catch(mailError){await loadJob();showError(`Resource assigned and PO created, but the email was not sent: ${mailError.message}. Open Supplier PO and use Retry sending.`);return}
  await loadJob();setStatus(replacing?'Resource reassigned · new PO sent ✓':'Resource assigned · PO sent ✓');
}

async function saveJob(){
  clearError();
  if(job.resource_id&&val('j-candidate')&&val('j-candidate')!==job.resource_id)return showError('Use Reassign & Issue New PO to replace the Resource; this preserves and cancels the current PO correctly.');
  if(!val('j-specialization'))return showError('Job specialization is required.');
  if(job.resource_id && val('j-status')==='Unassigned')return showError('An assigned Job cannot return to Unassigned. Cancel it or create a new Job.');
  if(!job.resource_id&&['Assigned','In Progress','Delivered','Revision Required','Approved'].includes(val('j-status')))return showError('Assign a Resource and issue its Supplier PO before moving this Job into production.');
  if(!val('j-source')||!val('j-target'))return showError('Source and Target languages are required.');
  if(!TMS_REF.languages.includes(val('j-source'))||!TMS_REF.languages.includes(val('j-target')))return showError('Choose Source and Target from the shared language list.');
  const termsChanged=val('j-service')!==job.service_type||val('j-source')!==(job.source_language||'')||val('j-target')!==(job.target_language||'')||val('j-specialization')!==job.specialization_id||Number(val('j-quantity')||0)!==Number(job.quantity||0)||val('j-unit')!==(job.unit||'');
  if(job.resource_id&&termsChanged&&!val('j-rate-select'))return showError('Select an Approved Supplier rate matching the edited Job terms.');
  const catRows=val('j-rate-select')?collectSupplierCatRows('j'):[],payload={status:val('j-status'),deadline:combineDateTime('j-deadline-date','j-deadline-time'),service_type:val('j-service'),source_language:val('j-source'),target_language:val('j-target'),specialization_id:val('j-specialization'),quantity:catRows.length?catRows.reduce((sum,row)=>sum+Number(row.quantity||0),0):(val('j-quantity')===''?null:Number(val('j-quantity'))),unit:val('j-unit'),po_required:document.getElementById('j-po-required').checked,notes:nullable('j-notes'),resource_rate_id:job.resource_id?nullable('j-rate-select'):null,cat_rows:catRows};
  const {data,error}=await _sb.rpc('save_job_overview',{p_job_id:jobId,p_payload:payload});if(error)return showError(error.message);
  await loadJob();setStatus(Number(data)>0?`Job saved · Supplier PO version ${data} created ✓`:'Job saved ✓');
}

function renderOffers(){
  document.getElementById('offerCount').textContent=offers.length+allPOVersions.length;
  const body=document.getElementById('offersTbody');
  if(!offers.length&&!allPOVersions.length){body.innerHTML='<tr class="state-row"><td colspan="7">No assignment history yet.</td></tr>';return}
  const events=offers.map(offer=>{
    const resource=offerResources.get(offer.resource_id), actions=[];
    if(['Draft','Sent','Viewed'].includes(offer.status))actions.push(`<button class="table-action danger" onclick="withdrawOffer('${offer.id}')">Close legacy offer</button>`);
    const hasCat=Array.isArray(offer.cat_analysis?.rows)&&offer.cat_analysis.rows.length>0,terms=hasCat?`${offer.cat_analysis.rows.filter(row=>Number(row.quantity||0)>0).length} CAT band${offer.cat_analysis.rows.filter(row=>Number(row.quantity||0)>0).length===1?'':'s'}`:`${offer.quantity??'—'} ${esc(offer.unit||'')} × ${offer.supplier_rate??'rate pending'}`;
    const displayStatus=offer.status==='Accepted'?'Assigned / PO issued':offer.status;
    return {createdAt:offer.created_at,html:`<tr><td>${offer.sequence_number}</td><td><a class="table-link" href="resource.html?id=${offer.resource_id}">${esc(resource?.internal_number||'—')} · ${esc(resourceName(resource))}</a><div class="customer-sub">${esc(resource?.resource_status||'—')}</div></td><td><span class="pill ${statusClass(offer.status)}">${esc(displayStatus)}</span>${offer.restriction_warning?'<div class="warning-text">Override recorded</div>':''}</td><td>${new Date(offer.created_at).toLocaleString('en-GB')}</td><td>${terms}<div class="customer-sub"><strong>${money(offer.amount,offer.currency)}</strong></div></td><td>${offer.client_identity_disclosed?'<span class="pill pill-amber">Disclosed</span>':'Hidden'}</td><td><div class="table-actions">${actions.join('')}</div></td></tr>`};
  });
  allPOVersions.forEach(versionRow=>{
    const po=purchaseOrders.find(row=>row.id===versionRow.purchase_order_id),snapshot=versionRow.snapshot||{},resourceId=po?.resource_id||snapshot.resource_id,resource=offerResources.get(resourceId),lines=Array.isArray(snapshot.lines)?snapshot.lines:[],currency=snapshot.currency||po?.currency||job.supplier_currency||'EUR',total=snapshot.total??po?.total??0;
    const terms=`${lines.length} PO line${lines.length===1?'':'s'}`,supplierLabel=resource?resourceName(resource):(snapshot.supplier?.legal_name||snapshot.supplier?.company_name||snapshot.supplier?.internal_number||'Resource'),supplierNumber=resource?.internal_number||snapshot.supplier?.internal_number||'—';
    events.push({createdAt:versionRow.created_at,html:`<tr class="history-version-row"><td>${esc(po?.po_number||snapshot.po_number||'PO')} · V${Number(versionRow.version_number)}</td><td>${resourceId?`<a class="table-link" href="resource.html?id=${resourceId}">${esc(supplierNumber)} · ${esc(supplierLabel)}</a>`:esc(supplierLabel)}</td><td><span class="pill ${versionRow.document_status==='Issued'?'pill-green':'pill-blue'}">PO ${esc(versionRow.document_status||'Version')}</span></td><td>${new Date(versionRow.created_at).toLocaleString('en-GB')}</td><td>${terms}<div class="customer-sub"><strong>${money(total,currency)}</strong></div></td><td>${snapshot.client_identity_disclosed?'<span class="pill pill-amber">Disclosed</span>':'Hidden'}</td><td><button class="table-action" onclick="openPOVersion('${versionRow.purchase_order_id}',${Number(versionRow.version_number)})">View version</button></td></tr>`});
  });
  body.innerHTML=events.sort((a,b)=>new Date(a.createdAt)-new Date(b.createdAt)).map(event=>event.html).join('');
}

async function withdrawOffer(id){const reason=prompt('Reason for withdrawal:');if(!reason)return;const {error}=await _sb.rpc('withdraw_job_offer',{p_offer_id:id,p_reason:reason});if(error)return showError(error.message);await loadJob();setStatus('Offer withdrawn ✓')}

function poRateSource(line={}){if(line.adjustment_type)return 'Adjustment';if(line.resource_rate_id&&line.cat_band)return `${line.cat_band}${line.discount_percent==null?'':` · ${Number(line.discount_percent).toFixed(2).replace(/\.00$/,'')}% off`}`;if(line.resource_rate_id)return 'Resource base rate';return 'Manual'}
function poLineRow(line={}){const options=['','Discount','Credit','Surcharge','Minimum fee'].map(value=>`<option value="${value}" ${value===(line.adjustment_type||'')?'selected':''}>${value||'None'}</option>`).join('');return `<tr><td><input class="po-description" value="${esc(line.description||'')}"></td><td><input class="po-quantity" type="number" step="0.001" value="${line.quantity??''}"></td><td><select class="po-unit"><option>Source words</option><option>Target words</option><option>Hours</option><option>Pages</option><option>Minutes</option><option>Fixed fee</option></select></td><td><input class="po-unit-price" type="number" step="0.0001" value="${line.unit_price??''}"></td><td><span class="rate-source-label">${esc(poRateSource(line))}</span></td><td><select class="po-adjustment">${options}</select></td><td><input class="po-amount" type="number" step="0.01" value="${line.amount??0}"></td><td><button class="del-line-btn" onclick="this.closest('tr').remove();calculatePOTotals()">×</button></td></tr>`}
function addPOLine(line={}){const body=document.getElementById('poLinesTbody');body.insertAdjacentHTML('beforeend',poLineRow(line));const row=body.lastElementChild;row.querySelector('.po-unit').value=line.unit||'Source words';wirePOLine(row);calculatePOTotals()}
function wirePOLine(row){row.querySelectorAll('input,select').forEach(el=>el.addEventListener('input',()=>{const q=Number(row.querySelector('.po-quantity').value||0),rate=Number(row.querySelector('.po-unit-price').value||0),adj=row.querySelector('.po-adjustment').value;if(el.classList.contains('po-quantity')||el.classList.contains('po-unit-price'))row.querySelector('.po-amount').value=(q*rate).toFixed(2);if(['Discount','Credit'].includes(adj))row.querySelector('.po-amount').value=(-Math.abs(Number(row.querySelector('.po-amount').value||0))).toFixed(2);calculatePOTotals()}))}
function collectPOLines(){return [...document.querySelectorAll('#poLinesTbody tr')].map((row,index)=>({description:row.querySelector('.po-description').value.trim(),quantity:row.querySelector('.po-quantity').value,unit:row.querySelector('.po-unit').value,unit_price:row.querySelector('.po-unit-price').value,adjustment_type:row.querySelector('.po-adjustment').value,amount:row.querySelector('.po-amount').value,sort_order:(index+1)*10}))}
function calculatePOTotals(){const lines=collectPOLines(),subtotal=lines.filter(x=>!x.adjustment_type).reduce((sum,x)=>sum+Number(x.amount||0),0),adjustments=lines.filter(x=>x.adjustment_type).reduce((sum,x)=>sum+Number(x.amount||0),0);document.getElementById('poSubtotal').textContent=money(subtotal);document.getElementById('poAdjustments').textContent=money(adjustments);document.getElementById('poTotal').textContent=money(subtotal+adjustments);renderPOPrint(lines,subtotal,adjustments)}

function currentPOVersion(){return purchaseOrder?Math.max(Number(purchaseOrder.current_version||0),...poVersions.map(version=>Number(version.version_number||0))):0}
function currentPOEmail(){const version=currentPOVersion();return purchaseOrder?poEmails.find(record=>record.purchase_order_id===purchaseOrder.id&&Number(record.po_version||1)===version):null}
function poVersionKey(poId,versionNumber){return `${poId}:${Number(versionNumber)}`}
function poForVersion(versionRow){return purchaseOrders.find(row=>row.id===versionRow.purchase_order_id)}
function renderPOVersionPreview(){
  const preview=document.getElementById('poVersionPreview'),versionRow=allPOVersions.find(row=>poVersionKey(row.purchase_order_id,row.version_number)===selectedPOVersionKey);
  if(!versionRow){preview.classList.add('hidden');preview.innerHTML='';return}
  const po=poForVersion(versionRow),snapshot=versionRow.snapshot||{},currency=snapshot.currency||po?.currency||'EUR',lines=Array.isArray(snapshot.lines)?snapshot.lines:[],subtotal=snapshot.subtotal??lines.filter(line=>!line.adjustment_type).reduce((sum,line)=>sum+Number(line.amount||0),0),adjustments=snapshot.adjustment_amount??lines.filter(line=>line.adjustment_type).reduce((sum,line)=>sum+Number(line.amount||0),0),total=snapshot.total??Number(subtotal)+Number(adjustments);
  preview.innerHTML=`<div class="po-version-preview-head"><div><span>Selected immutable version</span><strong>${esc(po?.po_number||snapshot.po_number||'Supplier PO')} · V${Number(versionRow.version_number)}</strong></div><div><span>PO value</span><strong>${money(total,currency)}</strong></div></div><table class="module-table"><thead><tr><th>Description</th><th>Quantity</th><th>Unit</th><th>Unit price</th><th>Adjustment</th><th>Amount</th></tr></thead><tbody>${lines.map(line=>`<tr><td>${esc(line.description||'—')}</td><td>${esc(line.quantity??'—')}</td><td>${esc(line.unit||'—')}</td><td>${unitMoney(line.unit_price,currency)}</td><td>${esc(line.adjustment_type||'—')}</td><td class="number-cell">${money(line.amount,currency)}</td></tr>`).join('')||'<tr class="state-row"><td colspan="6">No lines stored in this version.</td></tr>'}</tbody></table><div class="po-version-preview-total"><span>Subtotal ${money(subtotal,currency)}</span><span>Adjustments ${money(adjustments,currency)}</span><strong>Total ${money(total,currency)}</strong></div>`;
  preview.classList.remove('hidden');
}
function renderVersionHistory(){
  const card=document.getElementById('poVersionHistoryCard'),list=document.getElementById('poVersions');card.classList.toggle('hidden',!allPOVersions.length);if(!allPOVersions.length){list.innerHTML='';renderPOVersionPreview();return}
  list.innerHTML=[...allPOVersions].sort((a,b)=>new Date(b.created_at)-new Date(a.created_at)||Number(b.version_number)-Number(a.version_number)).map(versionRow=>{const po=poForVersion(versionRow),snapshot=versionRow.snapshot||{},currency=snapshot.currency||po?.currency||'EUR',total=snapshot.total??po?.total??0,email=poEmails.find(record=>record.purchase_order_id===versionRow.purchase_order_id&&Number(record.po_version||1)===Number(versionRow.version_number)),emailState=email?.status==='Sent'?'Email sent':email?.status==='Failed'?'Email failed':'Not sent',key=poVersionKey(versionRow.purchase_order_id,versionRow.version_number),selected=key===selectedPOVersionKey;return `<button type="button" class="version-row version-row-button${selected?' selected':''}" onclick="openPOVersion('${versionRow.purchase_order_id}',${Number(versionRow.version_number)})" aria-expanded="${selected?'true':'false'}"><strong>${esc(po?.po_number||snapshot.po_number||'Supplier PO')} · V${Number(versionRow.version_number)}</strong><span><strong>${money(total,currency)}</strong> · ${esc(versionRow.document_status)} · ${emailState}</span><span>${new Date(versionRow.created_at).toLocaleString('en-GB')} · ${esc(versionRow.change_reason||'Initial issue')}</span></button>`}).join('');
  renderPOVersionPreview();
}
function openPOVersion(poId,versionNumber){
  selectedPOVersionKey=poVersionKey(poId,versionNumber);const tab=document.querySelector('.record-tab[data-tab="po"]');if(tab&&!tab.classList.contains('active'))tab.click();renderVersionHistory();document.getElementById('poVersionPreview').scrollIntoView({behavior:'smooth',block:'nearest'});
}
function renderPOEmail(){
  const status=document.getElementById('poEmailStatus'),button=document.getElementById('sendPoBtn');if(!purchaseOrder){status.classList.add('hidden');button.classList.add('hidden');return}
  const version=currentPOVersion(),email=currentPOEmail(),recipient=purchaseOrder.supplier_snapshot?.email||assignedResource?.email||'Resource email';status.classList.remove('hidden');button.classList.remove('hidden');button.disabled=false;
  if(email?.status==='Sent'){
    status.className='po-email-status email-sent';status.innerHTML=`<div><strong>PO V${version} email sent</strong><span>To ${esc(email.to_addresses?.[0]||recipient)} · ${new Date(email.sent_at).toLocaleString('en-GB')}</span></div>${email.external_url?`<a class="btn-secondary" href="${esc(email.external_url)}" target="_blank" rel="noopener">Open V${version} in Gmail</a>`:''}`;button.textContent=`Send V${version} again`;
  }else if(email?.status==='Failed'){
    status.className='po-email-status email-failed';status.innerHTML=`<div><strong>PO V${version} email failed</strong><span>${esc(email.failure_reason||'Unknown delivery error')}</span></div>`;button.textContent=`Retry V${version}`;
  }else{
    status.className='po-email-status email-pending';status.innerHTML=`<div><strong>PO V${version} not sent</strong><span>Recipient: ${esc(recipient)}</span></div>`;button.textContent=`Send V${version}`;
  }
}
async function sendCurrentPOEmail(){
  if(!purchaseOrder)return;const version=currentPOVersion();if(currentPOEmail()?.status==='Sent'&&!confirm(`Send ${purchaseOrder.po_number} V${version} again to the Resource?`))return;
  const button=document.getElementById('sendPoBtn');button.disabled=true;button.textContent='Sending…';clearError();
  try{await sendSupplierPOEmail(purchaseOrder.id);await loadJob();setStatus(`${purchaseOrder.po_number} V${version} sent to ${purchaseOrder?.supplier_snapshot?.email||'Resource'} ✓`)}catch(error){await loadJob();showError(`PO V${version} email was not sent: ${error.message}`)}
}

function renderPO(){
  const hasPO=!!purchaseOrder;document.getElementById('poBadge').textContent=allPOVersions.length||purchaseOrders.length;document.getElementById('poEmpty').classList.toggle('hidden',hasPO);document.getElementById('poWorkspace').classList.toggle('hidden',!hasPO);renderVersionHistory();if(!hasPO)return;
  const version=currentPOVersion();purchaseOrder.current_version=version;document.getElementById('poTitle').textContent=`${purchaseOrder.po_number} · V${version}`;document.getElementById('poMeta').textContent=`${purchaseOrder.status} · Version ${version} · ${resourceName(assignedResource)} · Work may begin before acknowledgement`;
  const body=document.getElementById('poLinesTbody');body.innerHTML='';poLines.forEach(addPOLine);if(!poLines.length)addPOLine();
  const draft=purchaseOrder.status==='Draft',admin=currentRole==='admin';document.getElementById('savePoBtn').textContent=draft?'Save Draft':'Create Revision';document.getElementById('savePoBtn').disabled=!draft&&!admin;document.getElementById('issuePoBtn').classList.toggle('hidden',!draft);document.getElementById('issuePoBtn').disabled=!admin;document.getElementById('revisionReasonWrap').classList.toggle('hidden',draft);
  document.getElementById('cancelPoBtn').classList.toggle('hidden',!['Draft','Issued','Acknowledged'].includes(purchaseOrder.status));renderPOEmail();
  document.querySelectorAll('#poLinesTbody input,#poLinesTbody select,.add-line-btn').forEach(el=>el.disabled=!draft&&!admin);
  calculatePOTotals();
}
async function cancelCurrentPO(){const reason=prompt('Reason for cancelling this PO and unassigning the Resource:');if(!reason)return;if(!confirm('Cancel the current PO and return the Job to Unassigned? The PO history will be preserved.'))return;const {error}=await _sb.rpc('cancel_job_supplier_po',{p_job_id:jobId,p_reason:reason});if(error)return showError(error.message);await loadJob();setStatus('PO cancelled · Job returned to Unassigned ✓')}

async function savePO(){const lines=collectPOLines();if(!lines.length)return showError('At least one PO line is required.');let result;if(purchaseOrder.status==='Draft')result=await _sb.rpc('save_supplier_po_draft',{p_po_id:purchaseOrder.id,p_lines:lines});else{const reason=val('poRevisionReason');if(!reason)return showError('An Administrator revision reason is required.');result=await _sb.rpc('revise_supplier_po',{p_po_id:purchaseOrder.id,p_lines:lines,p_reason:reason})}if(result.error)return showError(result.error.message);await loadJob();setStatus(purchaseOrder.status==='Draft'?'Draft PO saved ✓':'New PO version created ✓')}
async function issuePO(){if(currentRole!=='admin')return showError('Only the Administrator can issue a Supplier PO.');if(!confirm(`Issue and email ${purchaseOrder.po_number}? Issued facts will be locked and later changes will create a new version.`))return;const save=await _sb.rpc('save_supplier_po_draft',{p_po_id:purchaseOrder.id,p_lines:collectPOLines()});if(save.error)return showError(save.error.message);const poId=purchaseOrder.id,{error}=await _sb.rpc('issue_supplier_po',{p_po_id:poId});if(error)return showError(error.message);try{await sendSupplierPOEmail(poId)}catch(mailError){await loadJob();return showError(`PO issued, but the email was not sent: ${mailError.message}. Use Retry sending.`)}await loadJob();setStatus('Supplier PO issued and sent ✓')}

function renderPOPrint(lines=collectPOLines(),subtotal=Number(purchaseOrder?.subtotal||0),adjustments=Number(purchaseOrder?.adjustment_amount||0)){
  if(!purchaseOrder)return;const supplier=purchaseOrder.supplier_snapshot||{};const lineHtml=lines.map(line=>`<tr><td>${esc(line.description)}</td><td>${esc(line.quantity||'')}</td><td>${esc(line.unit||'')}</td><td>${esc(line.unit_price||'')}</td><td>${money(line.amount,purchaseOrder.currency)}</td></tr>`).join('');
  document.getElementById('poPrintArea').innerHTML=`<div class="po-doc-head"><div><strong>Retodo Ops</strong><span>Supplier Purchase Order</span></div><div><h2>${esc(purchaseOrder.po_number)}</h2><span>Version ${purchaseOrder.current_version}</span></div></div><div class="po-doc-grid"><div><small>Supplier</small><strong>${esc(supplier.legal_name||supplier.company_name||resourceName(assignedResource))}</strong><span>${esc(supplier.internal_number||'')}</span><span>${esc(supplier.email||'')}</span></div><div><small>Job</small><strong>${esc(job.job_number)}</strong><span>${esc(job.service_type)} · ${esc(job.source_language||'')} → ${esc(job.target_language||'')}</span><span>Deadline: ${job.deadline?new Date(job.deadline).toLocaleString('en-GB'):'Non-defined'}</span></div></div><table><thead><tr><th>Description</th><th>Qty</th><th>Unit</th><th>Rate</th><th>Amount</th></tr></thead><tbody>${lineHtml}</tbody></table><div class="po-doc-total"><span>Subtotal ${money(subtotal,purchaseOrder.currency)}</span><span>Adjustments ${money(adjustments,purchaseOrder.currency)}</span><strong>Total ${money(subtotal+adjustments,purchaseOrder.currency)}</strong></div><p class="po-doc-note">This purchase order contains Retodo Ops project identifiers only. Client and account identity remain confidential unless expressly disclosed. Work may begin before PO acknowledgement. Confidentiality, non-disclosure and non-circumvention obligations continue to apply.</p>`;
}
function printPO(){renderPOPrint();document.body.classList.add('printing-po');window.print();setTimeout(()=>document.body.classList.remove('printing-po'),300)}

function renderIssues(){const body=document.getElementById('issuesTbody');if(!issues.length){body.innerHTML='<tr class="state-row"><td colspan="5">No delivery issues.</td></tr>';return}body.innerHTML=issues.map(issue=>`<tr><td><span class="pill ${statusClass(issue.status)}">${esc(issue.status)}</span></td><td>${esc(issue.severity||'—')}</td><td>${esc(issue.description)}</td><td>${new Date(issue.reported_at).toLocaleString('en-GB')}</td><td>${esc(issue.resolution||'—')}</td></tr>`).join('')}

async function loadJob(){
  clearError();supplierTermsDirty=false;const jobResult=await _sb.from('project_jobs').select('*').eq('id',jobId).single();if(jobResult.error)return showError(jobResult.error.message);job=jobResult.data;
  const [projectResult,specResult,projectSpecResult,offerResult,poResult,issueResult,scopeResult,emailResult,projectJobsResult]=await Promise.all([_sb.from('projects').select('*').eq('id',job.project_id).single(),_sb.from('specializations').select('*').eq('active',true).order('name'),_sb.from('project_specializations').select('*').eq('project_id',job.project_id).order('created_at'),_sb.from('job_offers').select('*').eq('job_id',jobId).order('sequence_number'),_sb.from('supplier_purchase_orders').select('*').eq('job_id',jobId).order('created_at',{ascending:false}),_sb.from('job_issues').select('*').eq('job_id',jobId).order('reported_at',{ascending:false}),_sb.from('scope_items').select('service_type,specialization_id,price_unit,cat_band,quantity,unit_price,price,adjustment_type').eq('project_id',job.project_id),_sb.from('email_records').select('*').eq('job_id',jobId).eq('direction','Outgoing').order('created_at',{ascending:false}),_sb.from('project_jobs').select('id,status').eq('project_id',job.project_id)]);
  if(projectResult.error)return showError(projectResult.error.message);if(scopeResult.error)return showError(scopeResult.error.message);if(emailResult.error)return showError(emailResult.error.message);if(projectJobsResult.error)return showError(projectJobsResult.error.message);project=projectResult.data;specializations=specResult.data||[];projectSpecializations=projectSpecResult.data||[];offers=offerResult.data||[];purchaseOrders=poResult.data||[];purchaseOrder=purchaseOrders.find(po=>!['Cancelled','Superseded'].includes(po.status))||null;issues=issueResult.data||[];projectScopeLines=scopeResult.data||[];projectJobs=projectJobsResult.data||[];poEmails=emailResult.data||[];resourceRates=[];
  const resourceIds=[...new Set([job.resource_id,...offers.map(x=>x.resource_id),...purchaseOrders.map(x=>x.resource_id)].filter(Boolean))];offerResources=new Map();if(resourceIds.length){const {data}=await _sb.from('resources').select('*').in('id',resourceIds);(data||[]).forEach(resource=>offerResources.set(resource.id,resource))}assignedResource=job.resource_id?offerResources.get(job.resource_id):null;
  const poIds=purchaseOrders.map(po=>po.id),[lineResult,versionResult]=await Promise.all([purchaseOrder?_sb.from('supplier_po_lines').select('*').eq('purchase_order_id',purchaseOrder.id).order('sort_order'):Promise.resolve({data:[]}),poIds.length?_sb.from('supplier_po_versions').select('*').in('purchase_order_id',poIds).order('created_at',{ascending:false}):Promise.resolve({data:[]})]);
  if(lineResult.error)return showError(lineResult.error.message);if(versionResult.error)return showError(versionResult.error.message);allPOVersions=versionResult.data||[];poVersions=purchaseOrder?allPOVersions.filter(version=>version.purchase_order_id===purchaseOrder.id).sort((a,b)=>Number(b.version_number)-Number(a.version_number)):[];if(purchaseOrder){const latestVersion=poVersions[0],snapshotLines=latestVersion?.snapshot?.lines;poLines=Array.isArray(snapshotLines)?snapshotLines:(lineResult.data||[]);purchaseOrder.current_version=Math.max(Number(purchaseOrder.current_version||0),...poVersions.map(version=>Number(version.version_number||0)))}else poLines=[];
  populateHeader();populateOverview();renderOffers();renderPO();renderIssues();window.TMS_QUICK_NAV?.recordVisit('Job',job.id,job.job_number,[project.display_name,job.service_type,job.status].filter(Boolean).join(' · '));await loadOverviewCandidates();
}

document.querySelectorAll('.record-tab').forEach(tab=>tab.addEventListener('click',()=>{document.querySelectorAll('.record-tab').forEach(t=>t.classList.toggle('active',t===tab));document.querySelectorAll('.record-pane').forEach(pane=>pane.classList.toggle('active',pane.id===`pane-${tab.dataset.tab}`))}));
document.getElementById('j-candidate').addEventListener('change',async event=>{await fillRateSelect('j-rate-select',event.target.value);updateAssignmentAction()});
document.getElementById('j-rate-select').addEventListener('change',()=>{supplierTermsDirty=true;renderSupplierCatGrid('j-rate-select')});
['j-service','j-source','j-target','j-specialization','j-unit'].forEach(id=>document.getElementById(id).addEventListener('change',()=>{supplierTermsDirty=true;const resourceId=val('j-candidate')||job.resource_id;if(resourceId)fillRateSelect('j-rate-select',resourceId)}));
document.getElementById('j-quantity').addEventListener('input',()=>{supplierTermsDirty=true;renderJobFinancials()});

(async()=>{currentUser=await requireAuth();if(!currentUser)return;TMS_REF.installDatalists();const {data:profile}=await _sb.from('profiles').select('role').eq('id',currentUser.id).maybeSingle();currentRole=profile?.role||'user';jobId=new URLSearchParams(location.search).get('id');if(!jobId){location.href='dashboard.html';return}await loadJob()})();

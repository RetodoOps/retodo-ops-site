let resourceId, resource, appRole = 'user', cvData = null, portalLinkStatus = null;
let complianceSummary = null, complianceFileRecords = [], complianceRefreshTimer = null;
let pairs=[], services=[], specializations=[], resourceSpecializations=[], rates=[], tests=[], accountQualifications=[], accounts=[], education=[], documents=[], history=[], availability=[], privateNotes=[], accountSpecializationDefaults=[];
const esc=value=>String(value??'').replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;').replaceAll("'",'&#039;');
const el=id=>document.getElementById(id), val=id=>el(id).value.trim(), nullable=id=>val(id)||null;
const initialsFromName=name=>String(name||'').trim().split(/[\s-]+/).filter(Boolean).map(part=>Array.from(part)[0]||'').join('').toLocaleUpperCase().slice(0,12);
const CAT_BANDS=['Repetitions','101% / Context match','100% matches','95–99%','85–94%','75–84%','50–74%'];
function toggleSub(id,item){el(id).classList.toggle('open');item.classList.toggle('open')}
function closeModal(id){el(id).classList.add('hidden');el(id).querySelectorAll('.error-msg').forEach(x=>x.classList.add('hidden'))}
function modalError(id,message){el(id).textContent=message;el(id).classList.remove('hidden')}
function showError(message){el('resourceError').textContent=message;el('resourceError').classList.remove('hidden');el('resourceError').scrollIntoView({behavior:'smooth'})}
function setStatus(message){el('saveStatus').textContent=message;clearTimeout(setStatus.timer);setStatus.timer=setTimeout(()=>el('saveStatus').textContent='',3500)}
function fmtDate(value){return value?new Intl.DateTimeFormat('en-GB',{day:'2-digit',month:'short',year:'numeric'}).format(new Date(value)):'—'}
function fmtDateTime(value){return value?new Intl.DateTimeFormat('en-GB',{dateStyle:'medium',timeStyle:'short'}).format(new Date(value)):'—'}
function toLocalDT(iso){if(!iso)return '';const d=new Date(iso),p=n=>String(n).padStart(2,'0');return `${d.getFullYear()}-${p(d.getMonth()+1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`}
const datePart=iso=>toLocalDT(iso).slice(0,10);
const timePart=iso=>toLocalDT(iso).slice(11,16);
const combineDateTime=(dateId,timeId)=>{const date=val(dateId);return date?`${date}T${val(timeId)||'00:00'}`:null};
function money(amount,currency='EUR'){return `${Number(amount||0).toFixed(4).replace(/0+$/,'').replace(/\.$/,'')} ${currency}`}
function specName(id){return specializations.find(row=>row.id===id)?.name||'Non-defined'}
function approvalPill(approved){return `<span class="pill ${approved?'pill-green':'pill-amber'}">${approved?'Approved':'Not approved'}</span>`}
function qualificationPill(status){const css=status==='Approved'?'pill-green':status==='Not approved'?'pill-red':'pill-amber';return `<span class="pill ${css}">${esc(status||'Not tested')}</span>`}
function languageOptions(selected='',empty='Select…'){return `<option value="">${empty}</option>`+TMS_REF.languages.map(language=>`<option value="${esc(language)}" ${language===selected?'selected':''}>${esc(language)}</option>`).join('')}
function selectedInternalPositions(){return [...document.querySelectorAll('#r-internal-positions input:checked')].map(input=>input.value)}
function updateInternalPositionsSummary(){const positions=selectedInternalPositions();document.querySelector('#r-internal-positions summary').textContent=positions.length?positions.join(', '):'Select one or more positions…'}
function populateInternalOverview(){const name=resource.legal_name||resource.internal_number;document.title=`${name} — RetodoOps TMS`;el('resourceTitle').textContent=name;el('resourceBreadcrumb').textContent=resource.internal_number;document.body.classList.add('internal-resource-mode');el('internalOverviewCard').classList.remove('hidden');el('blindCvButton').classList.add('hidden');const breadcrumb=el('resourcesBreadcrumbLink');breadcrumb.href='resources.html?type=internal';breadcrumb.textContent='Internal Resources';el('r-internal-name').value=resource.legal_name||'';el('r-internal-number').value=resource.internal_number||'';el('r-internal-email').value=resource.email||'';el('r-internal-gender').value=resource.gender||'';el('r-internal-status').value=resource.lifecycle_status||'Active';document.querySelectorAll('#r-internal-positions input').forEach(input=>input.checked=(resource.internal_positions||[]).includes(input.value));updateInternalPositionsSummary();const state=el('internalAccessState'),active=resource.lifecycle_status==='Active';state.textContent=!resource.profile_id?'Invitation needed':active?'Account linked':resource.lifecycle_status==='On leave'?'On leave':'Access disabled';state.className=`pill ${active?'pill-green':resource.lifecycle_status==='On leave'?'pill-amber':'pill-red'}`;el('resourceSubtitle').textContent=`${resource.internal_number} · Internal Resource · ${resource.lifecycle_status||'Active'}`}
async function saveInternalOverview(){const name=val('r-internal-name'),email=val('r-internal-email'),positions=selectedInternalPositions();if(!name||!email||!positions.length)return showError('Name, Email and at least one Position are required.');const {error}=await _sb.rpc('update_internal_resource_profile',{p_resource_id:resourceId,p_payload:{name,email,positions,gender:nullable('r-internal-gender'),status:val('r-internal-status')}});if(error)return showError(error.message);await loadResource();setStatus('Saved ✓')}

function populateOverview(){
    if(resource.resource_type==='Internal')return populateInternalOverview();
    const name=resource.legal_name||resource.company_name||resource.internal_number;document.title=`${name} — RetodoOps TMS`;el('resourceTitle').textContent=name;el('resourceBreadcrumb').textContent=resource.internal_number;el('resourceSubtitle').textContent=`${resource.internal_number} · ${resource.resource_type} · ${resource.resource_status}`;
    const fields={'r-number':resource.internal_number,'r-legacy':resource.legacy_id,'r-type':resource.resource_type,'r-name':resource.legal_name,'r-initials':resource.initials,'r-company':resource.company_name,'r-nationality':resource.nationality,'r-country':resource.country_of_residence,'r-city':resource.city,'r-native':resource.native_language,'r-timezone':resource.timezone,'r-email':resource.email,'r-phone':resource.phone,'r-website':resource.website,'r-linkedin':resource.linkedin_url,'r-linkedin-confidence':resource.linkedin_match_confidence,'r-linkedin-status':resource.linkedin_connection_status,'r-lifecycle':resource.lifecycle_status||'Active','r-status':resource.resource_status||'New contact','r-compliance':resource.compliance_status,'r-compliance-expiry':resource.compliance_expiry,'r-quality':resource.quality_rating,'r-restrictions':resource.operational_restrictions||resource.restriction_reason,'r-quality-evidence':resource.quality_evidence,'r-notes':resource.notes,'r-portal':resource.portal_status,'r-financial-until':resource.financial_access_until,'r-payment-days':resource.payment_terms_days,'r-invoice-cycle':resource.invoice_cycle,'r-tax':resource.tax_id,'r-cv-status':resource.blind_cv_status};Object.entries(fields).forEach(([id,value])=>el(id).value=value??'');
    ['r-portal','r-financial-until'].forEach(id=>{el(id).disabled=appRole!=='admin';el(id).title=appRole==='admin'?'':'Administrator access required'});
    const currentAvailability=availability.find(row=>new Date(row.starts_at)<=new Date()&&(!row.ends_at||new Date(row.ends_at)>=new Date()));
    el('resourceSummary').innerHTML=`<div><span>Resource status</span><strong>${esc(resource.resource_status)}</strong><small>${resource.lifecycle_status||'Active'} lifecycle</small></div><div><span>Availability</span><strong>${esc(currentAvailability?.status||'Unknown')}</strong><small>${currentAvailability?.ends_at?`Until ${fmtDate(currentAvailability.ends_at)}`:'No current end date'}</small></div><div><span>Last recorded work</span><strong>${fmtDate(resource.last_recorded_job)}</strong><small>${history.length} history record${history.length===1?'':'s'}</small></div><div><span>Blind CV</span><strong>${esc(resource.blind_cv_status||'Not ready')}</strong><small>${education.length} education record${education.length===1?'':'s'}</small></div>`;
}

async function saveOverview(){
    if(resource?.resource_type==='Internal')return saveInternalOverview();
    el('resourceError').classList.add('hidden');
    const readyStatuses=['Assignable','Proven','Preferred'];
    if(readyStatuses.includes(val('r-status'))&&!val('r-email'))return showError(`Add an email address before setting the Resource to ${val('r-status')}.`);
    const payload={resource_type:val('r-type'),lifecycle_status:val('r-lifecycle'),resource_status:val('r-status'),legal_name:nullable('r-name'),company_name:nullable('r-company'),initials:nullable('r-initials'),nationality:nullable('r-nationality'),country_of_residence:nullable('r-country'),city:nullable('r-city'),native_language:nullable('r-native'),timezone:nullable('r-timezone'),email:nullable('r-email'),phone:nullable('r-phone'),website:nullable('r-website'),linkedin_url:nullable('r-linkedin'),linkedin_match_confidence:nullable('r-linkedin-confidence'),linkedin_connection_status:nullable('r-linkedin-status'),compliance_status:val('r-compliance'),compliance_expiry:val('r-compliance-expiry')||null,quality_rating:val('r-quality')===''?null:Number(val('r-quality')),operational_restrictions:nullable('r-restrictions'),quality_evidence:nullable('r-quality-evidence'),notes:nullable('r-notes'),portal_status:val('r-portal'),financial_access_until:val('r-financial-until')||null,payment_terms_days:Number(val('r-payment-days')||60),invoice_cycle:nullable('r-invoice-cycle'),tax_id:nullable('r-tax'),blind_cv_status:val('r-cv-status')};
    const currentEmail=normalizeInvitationEmail(resource.email),newEmail=normalizeInvitationEmail(payload.email);
    const linkedEmailChange=!!resource.profile_id&&newEmail!==currentEmail;
    if(linkedEmailChange){
        if(appRole!=='admin')return showError('Only an Administrator can correct a linked login email.');
        let confirmedEmail;
        try{
            confirmedEmail=requestExactEmailConfirmation(newEmail,
                `Correct the linked login from ${currentEmail} to ${newEmail} and send a replacement access invitation? This is allowed only if the account has never signed in.`);
        }catch(error){return showError(error.message)}
        if(!confirmedEmail)return;
        try{
            await resourceOnboarding({action:'correct_email',resource_id:resourceId,new_email:newEmail,confirmed_email:confirmedEmail,request_id:crypto.randomUUID()});
        }catch(error){
            await loadResource();
            if(error.emailCorrected)return showError(`The login email was corrected, but the replacement invitation was not sent: ${error.message}`);
            if(error.emailCorrectionPending){el('r-email').value=newEmail;return showError('The login email correction is incomplete. Retry Save changes to finish it safely.')}
            return showError(error.message);
        }
        const {email,portal_status,resource_type,...profilePayload}=payload;
        profilePayload.resource_type=resource.resource_type;
        const saved=await _sb.from('resources').update(profilePayload).eq('id',resourceId);
        if(saved.error){await loadResource();return showError(`The login email was corrected and the replacement invitation was sent, but other profile changes were not saved: ${saved.error.message}`)}
        await loadResource();setStatus('Login email corrected · replacement invitation sent ✓');return;
    }
    const {error}=await _sb.from('resources').update(payload).eq('id',resourceId);
    if(error)return showError(error.message);
    await loadResource();setStatus('Saved ✓');
}

function renderPortalLinkState(message,tone=''){
    const card=el('portalLinkCard'),state=el('portalLinkState');
    if(!card||!state)return;
    card.classList.remove('portal-link-ready','portal-link-warning','portal-link-error');
    if(tone)card.classList.add(`portal-link-${tone}`);
    state.textContent=message;
}
function portalLinkFailure(message){
    const error=el('portalLinkError');
    if(error){error.textContent=message;error.classList.remove('hidden')}
    renderPortalLinkState('Portal link status could not be verified.','error');
}
async function loadPortalLinkStatus(){
    const card=el('portalLinkCard'),button=el('activatePortalBtn'),error=el('portalLinkError');
    if(!card||!button||!resource)return;
    if(resource.resource_type==='Internal'){card.classList.add('hidden');renderAccessInvitation();return}
    renderAccessInvitation();
    card.classList.remove('hidden');
    if(error){error.textContent='';error.classList.add('hidden')}
    button.disabled=true;button.textContent='Approve portal access';
    if(appRole!=='admin'){
        renderPortalLinkState(resource.profile_id
            ?`Authentication account linked · portal ${resource.portal_status||'Not invited'}. Only an Administrator can change the link.`
            :'No Authentication account is linked. Administrator access is required.');
        button.textContent='Administrator required';
        return;
    }
    renderPortalLinkState('Checking the Resource email…');
    const {data,error:rpcError}=await _sb.rpc('external_resource_portal_link_status',{p_resource_id:resourceId});
    if(rpcError){portalLinkFailure(rpcError.message);return}
    portalLinkStatus=data||{};
    const status=portalLinkStatus;
    if(!status.resource_email_present){renderPortalLinkState('Add and save the Resource email first.','warning');return}
    if(status.resource_has_other_profile_link){renderPortalLinkState('This Resource is already linked to a different Authentication account.','error');return}
    if(status.linked_to_another_resource){renderPortalLinkState('The matching Authentication account is already linked to another Resource.','error');return}
    if(status.auth_user_exists&&status.profile_role&&!['user','resource'].includes(status.profile_role)){
        renderPortalLinkState(`The matching Authentication account has company role “${status.profile_role}” and cannot be used here.`,'error');return;
    }
    if(status.linked_to_this_resource&&status.profile_role==='resource'&&['Active','Read-only','Financial only'].includes(status.portal_status)){
        renderPortalLinkState(`Linked and ready · portal ${status.portal_status}.`,'ready');button.textContent='Portal login active';return;
    }
    if(!status.auth_user_exists){
        renderPortalLinkState('No login account yet. Sending an access invitation creates it and approves portal access.','warning');button.textContent='Invite the resource first';return;
    }
    renderPortalLinkState(status.linked_to_this_resource
        ?'The account is linked but portal access is not active.'
        :'Matching Authentication user found and ready to link.','warning');
    button.disabled=false;button.textContent=status.linked_to_this_resource?'Restore portal access':'Approve portal access';
}
async function activateResourcePortal(){
    if(appRole!=='admin'||!portalLinkStatus?.auth_user_exists)return;
    const email=resource?.email||'the matching email';
    if(!confirm(`Link the Supabase Authentication user ${email} to this External Resource and approve portal access?`))return;
    const button=el('activatePortalBtn');button.disabled=true;button.textContent='Activating…';
    const {error}=await _sb.rpc('activate_external_resource_portal',{p_resource_id:resourceId});
    if(error){portalLinkFailure(error.message);button.textContent='Try again';button.disabled=false;return}
    await loadResource();setStatus('External Resource portal activated ✓');
}

function renderPairs(){el('pairsList').innerHTML=pairs.length?pairs.map(pair=>`<div class="data-card"><div><strong>${esc(pair.source_language)} → ${esc(pair.target_language)}</strong><small>${pair.native_target?'Native target · ':''}${esc(pair.notes||'')}</small></div><div class="table-actions"><span class="pill pill-green">Capability</span><button class="table-action danger" onclick="removePair('${pair.id}')">Remove</button></div></div>`).join(''):'<div class="empty-compact">No language pairs.</div>'}
function openPairModal(){el('pair-source').innerHTML=languageOptions();el('pair-target').innerHTML=languageOptions();el('pair-notes').value='';el('pair-native').checked=false;el('pairModal').classList.remove('hidden')}
async function savePair(){if(!val('pair-source')||!val('pair-target'))return modalError('pairError','Source and target are required.');const {error}=await _sb.from('resource_language_pairs').insert({resource_id:resourceId,source_language:val('pair-source'),target_language:val('pair-target'),native_target:el('pair-native').checked,approved:true,notes:nullable('pair-notes')});if(error)return modalError('pairError',error.message);closeModal('pairModal');await loadResource();setStatus('Language pair added ✓')}
async function removePair(id){const pair=pairs.find(item=>item.id===id);if(!pair||!confirm(`Remove ${pair.source_language} → ${pair.target_language}? Existing Job and PO history will be preserved; matching current rate cards will become inactive.`))return;const {error}=await _sb.rpc('remove_resource_language_pair',{p_pair_id:id});if(error)return showError(error.message);await loadResource();setStatus('Language pair removed ✓')}
function renderServices(){el('servicesList').innerHTML=services.length?services.map(service=>`<div class="data-card"><div><strong>${esc(service.service_type)}</strong><small>${esc(service.notes||'')}</small></div><div class="table-actions"><span class="pill pill-green">Capability</span><button class="table-action danger" onclick="removeService('${esc(service.service_type)}')">Remove</button></div></div>`).join(''):'<div class="empty-compact">No services.</div>'}
function openServiceModal(){const configured=new Set(services.map(service=>service.service_type));el('service-name').innerHTML=TMS_REF.services.filter(service=>!configured.has(service)).map(service=>`<option>${esc(service)}</option>`).join('')||'<option value="">All Project services are already configured</option>';el('service-notes').value='';el('serviceModal').classList.remove('hidden')}
async function saveService(){const {error}=await _sb.from('resource_services').insert({resource_id:resourceId,service_type:val('service-name'),approved:true,notes:nullable('service-notes')});if(error)return modalError('serviceError',error.message);closeModal('serviceModal');await loadResource();setStatus('Service added ✓')}
async function removeService(serviceType){if(!confirm(`Remove ${serviceType}? Existing Job and PO history will be preserved; matching current rate cards will become inactive.`))return;const {error}=await _sb.rpc('remove_resource_service',{p_resource_id:resourceId,p_service_type:serviceType});if(error)return showError(error.message);await loadResource();setStatus('Service removed ✓')}

function renderSpecializations(){const body=el('specializationsTbody');body.innerHTML=resourceSpecializations.length?resourceSpecializations.map(row=>`<tr><td>${esc(specName(row.specialization_id))}</td><td>${row.experience_years??'—'}${row.experience_years!=null?' years':''}</td><td>${qualificationPill(row.qualification_status)}</td><td>${esc(row.evidence||'—')}</td><td><button class="table-action" onclick="openSpecializationModal('${row.specialization_id}')">Edit</button></td></tr>`).join(''):'<tr class="state-row"><td colspan="5">No specializations.</td></tr>'}
function specOptions(selected=''){return '<option value="">Non-defined</option>'+specializations.map(spec=>`<option value="${spec.id}" ${spec.id===selected?'selected':''}>${esc(spec.name)}</option>`).join('')}
function openSpecializationModal(specializationId=null){const row=resourceSpecializations.find(item=>item.specialization_id===specializationId);el('specializationModalTitle').textContent=row?'Edit specialization':'Add specialization';el('spec-original-id').value=row?.specialization_id||'';el('spec-id').innerHTML=specOptions(row?.specialization_id||'');el('spec-id').disabled=!!row;el('spec-years').value=row?.experience_years??'';el('spec-evidence').value=row?.evidence||'';el('spec-status').value=row?.qualification_status||'Not tested';el('specializationModal').classList.remove('hidden')}
async function saveSpecialization(){if(!val('spec-id'))return modalError('specError','Select a specialization.');const originalId=val('spec-original-id'),payload={experience_years:val('spec-years')===''?null:Number(val('spec-years')),qualification_status:val('spec-status'),evidence:nullable('spec-evidence')};const {error}=originalId?await _sb.from('resource_specializations').update(payload).eq('resource_id',resourceId).eq('specialization_id',originalId):await _sb.from('resource_specializations').insert({...payload,resource_id:resourceId,specialization_id:val('spec-id')});if(error)return modalError('specError',error.message);closeModal('specializationModal');await loadResource();setStatus(originalId?'Specialization updated ✓':'Specialization added ✓')}

function renderRates(){
    const activeRates=rates.filter(rate=>rate.active!==false),bases=activeRates.filter(rate=>!rate.base_rate_id),children=new Map();activeRates.filter(rate=>rate.base_rate_id).forEach(rate=>{if(!children.has(rate.base_rate_id))children.set(rate.base_rate_id,[]);children.get(rate.base_rate_id).push(rate)});
    if(!bases.length){el('ratesTbody').innerHTML='<tr class="state-row"><td colspan="8">No active supplier rate cards.</td></tr>';return}
    el('ratesTbody').innerHTML=bases.map(base=>{
        const sources=rateLanguages(base,'source'),targets=rateLanguages(base,'target'),status=`<span class="pill ${base.status==='Approved'?'pill-green':base.status==='Rejected'?'pill-red':'pill-amber'}">${esc(base.status)}</span>`,scope=base.account_id?accountName(base.account_id):'All Accounts',specialization=base.specialization_id?specName(base.specialization_id):'All specs',baseRow=`<tr class="rate-base-row"><td><strong>${esc(supplierRateCardName(base))}</strong><div class="customer-sub">${esc(sources.join(', ')||'Any')} → ${esc(targets.join(', ')||'Any')}</div></td><td><span class="pill ${base.account_id?'pill-blue':''}">${esc(scope)}</span></td><td>${esc(base.service_type)}<div class="customer-sub">${esc(specialization)}</div></td><td>${esc(base.unit)}<div class="customer-sub">Base price</div></td><td>—</td><td><strong>${money(base.rate,base.currency)}</strong></td><td>${base.minimum_fee==null?'—':Number(base.minimum_fee).toFixed(2)+' '+base.currency}</td><td><div class="table-actions">${status}<button class="table-action" onclick="openRateModal('${base.id}')">Edit</button></div></td></tr>`;
        const bandRows=(children.get(base.id)||[]).sort((a,b)=>CAT_BANDS.indexOf(a.cat_band)-CAT_BANDS.indexOf(b.cat_band)).map(rate=>`<tr class="rate-band-row"><td></td><td></td><td></td><td>${esc(rate.cat_band||'CAT band')}</td><td>${rate.discount_percent==null?'—':Number(rate.discount_percent).toFixed(2).replace(/\.00$/,'')+'%'}</td><td>${money(rate.rate,rate.currency)}</td><td></td><td><span class="customer-sub">linked to base</span></td></tr>`).join('');return baseRow+bandRows;
    }).join('');
}
function supplierRateCardName(rate){const sources=rateLanguages(rate,'source'),targets=rateLanguages(rate,'target'),pair=`${sources.map(language=>TMS_REF.compactLanguage(language)).join('+')||'ANY'}-${targets.map(language=>TMS_REF.compactLanguage(language)).join('+')||'ANY'}`,service=TMS_REF.compactServiceCode(rate.service_type),spec=rate.specialization_id?specName(rate.specialization_id):'All specs',account=rate.account_id?accountName(rate.account_id):'All acc',unit=TMS_REF.compactUnit(rate.unit);return `${pair} · ${service} · ${spec} - ${account} - ${money(rate.rate,rate.currency)}/${unit}`}
function rateLanguages(rate,side){const list=rate?.[`${side}_languages`];if(Array.isArray(list)&&list.length)return list;const scalar=rate?.[`${side}_language`];return scalar?[scalar]:[]}
function selectedRateLanguages(containerId){return [...el(containerId).querySelectorAll('input:checked')].map(input=>input.value)}
function renderLanguageDropdown(containerId,values,selected,empty,onChange){const container=el(containerId),menu=container.querySelector('.catalog-dropdown-menu');menu.innerHTML=values.map(value=>`<label class="checkbox-row"><input type="checkbox" value="${esc(value)}" ${selected.has(value)?'checked':''}>${esc(value)}</label>`).join('')||`<span class="muted">${esc(empty)}</span>`;const update=()=>{const chosen=selectedRateLanguages(containerId),summary=container.querySelector('summary');summary.textContent=chosen.length?(chosen.length<=2?chosen.join(', '):`${chosen.length} languages selected`):`Select ${containerId==='rate-sources'?'Source':'Target'} languages…`;if(onChange)onChange()};menu.querySelectorAll('input').forEach(input=>input.addEventListener('change',update));update()}
function renderRateLanguageOptions(base=null){
    const selectedSources=new Set(rateLanguages(base,'source')),selectedTargets=new Set(rateLanguages(base,'target'));
    const languages=TMS_REF.languages;
    renderLanguageDropdown('rate-sources',languages,selectedSources,'No active languages in Settings.');
    renderLanguageDropdown('rate-targets',languages,selectedTargets,'No active languages in Settings.');
}
function renderCatDiscountRows(baseId=null){const children=rates.filter(rate=>rate.base_rate_id===baseId&&rate.active!==false);el('catDiscountRows').innerHTML=CAT_BANDS.map(band=>{const child=children.find(rate=>rate.cat_band===band);return `<tr><td>${esc(band)}</td><td><input class="cat-discount" data-band="${esc(band)}" type="number" min="0" max="100" step="0.01" placeholder="%" value="${child?.discount_percent??''}"></td><td class="cat-calculated">—</td></tr>`}).join('');el('catDiscountRows').querySelectorAll('.cat-discount').forEach(input=>input.addEventListener('input',calculateCatRates));calculateCatRates()}
function calculateCatRates(){const base=Number(val('rate-value')),currency=val('rate-currency')||'EUR';el('catDiscountRows').querySelectorAll('tr').forEach(row=>{const raw=row.querySelector('.cat-discount').value,output=row.querySelector('.cat-calculated');output.textContent=raw===''||!Number.isFinite(base)?'—':money(base*(1-Number(raw)/100),currency)})}
function toggleCatDiscounts(){const enabled=['Source words','Target words'].includes(val('rate-unit'));el('catDiscountSection').classList.toggle('hidden',!enabled)}
function openRateModal(baseId=null){
    const base=rates.find(rate=>rate.id===baseId&&!rate.base_rate_id);el('rateModalTitle').textContent=base?'Edit supplier rate card':'Add supplier rate card';el('saveRateBtn').textContent=base?'Save changes':'Save rate card';el('rate-id').value=base?.id||'';renderRateLanguageOptions(base);
    const catalog=[...TMS_REF.services];if(base?.service_type&&!catalog.includes(base.service_type))catalog.push(base.service_type);el('rate-service').innerHTML=catalog.map(service=>`<option>${esc(service)}</option>`).join('');
    const configuredSpecs=new Set(resourceSpecializations.map(item=>item.specialization_id));el('rate-spec').innerHTML='<option value="">All configured specializations</option>'+specializations.filter(spec=>configuredSpecs.has(spec.id)).map(spec=>`<option value="${spec.id}">${esc(spec.name)}</option>`).join('');
    el('rate-account').innerHTML='<option value="">All Accounts</option>'+accounts.map(account=>`<option value="${account.id}" ${account.id===base?.account_id?'selected':''}>${esc(account.name)}</option>`).join('');el('rate-value').value=base?.rate??'';el('rate-minimum').value=base?.minimum_fee??'';el('rate-currency').value=base?.currency||'EUR';el('rate-unit').value=base?.unit||'Source words';el('rate-status').value=base?.status||'Pending';if(base){el('rate-service').value=base.service_type;el('rate-spec').value=base.specialization_id||''}renderCatDiscountRows(base?.id||null);toggleCatDiscounts();el('rateModal').classList.remove('hidden')
}
async function saveRate(){
    const sources=selectedRateLanguages('rate-sources'),targets=selectedRateLanguages('rate-targets');if(!sources.length||!targets.length)return modalError('rateError','Select at least one Source and one Target language.');
    if(!val('rate-service'))return modalError('rateError','Select a service from the Settings catalog.');
    if(val('rate-value')===''||Number(val('rate-value'))<0)return modalError('rateError','Enter a valid base price.');
    const discounts=[...el('catDiscountRows').querySelectorAll('.cat-discount')].filter(input=>input.value!=='').map(input=>({cat_band:input.dataset.band,discount_percent:Number(input.value)}));
    if(discounts.some(item=>item.discount_percent<0||item.discount_percent>100))return modalError('rateError','CAT discounts must be between 0% and 100%.');
    const baseId=val('rate-id'),payload={base_rate_id:baseId||null,resource_id:resourceId,account_id:nullable('rate-account'),source_languages:sources,target_languages:targets,service_type:val('rate-service'),specialization_id:nullable('rate-spec'),unit:val('rate-unit'),base_rate:Number(val('rate-value')),currency:val('rate-currency'),minimum_fee:val('rate-minimum')===''?null:Number(val('rate-minimum')),status:val('rate-status'),cat_discounts:['Source words','Target words'].includes(val('rate-unit'))?discounts:[]};
    const {error}=await _sb.rpc('save_scoped_resource_rate_card',{p_payload:payload});if(error)return modalError('rateError',error.message);closeModal('rateModal');await loadResource();setStatus(baseId?'Supplier rate card updated ✓':'Supplier rate card added ✓')
}

function accountName(id){return accounts.find(account=>account.id===id)?.name||'Non-defined Account'}
function testScope(test){if(test.test_type==='General')return 'General';if(test.test_type==='Domain')return `Domain · ${specName(test.specialization_id)}`;return `Account · ${accountName(test.account_id)}${test.specialization_id?` · ${specName(test.specialization_id)}`:''}`}
function testStatusPill(status){const css=status==='Passed'?'pill-green':status==='Failed'?'pill-red':status==='Cancelled'?'':'pill-amber';return `<span class="pill ${css}">${esc(status)}</span>`}
function renderTests(){
    el('testsTbody').innerHTML=tests.length?tests.map(test=>`<tr><td><strong>${esc(testScope(test))}</strong><div class="customer-sub">${esc(test.evidence||'No evidence recorded')}</div></td><td>${esc(test.source_language||'—')} → ${esc(test.target_language||'—')}<div class="customer-sub">${esc(test.service_type||'—')}</div></td><td>${testStatusPill(test.status)}</td><td>${fmtDateTime(test.assigned_at)}<div class="customer-sub">${test.completed_at?fmtDateTime(test.completed_at):'Not completed'}</div></td><td>${test.memoq_project_ref?`<a class="table-link" href="${esc(test.memoq_project_ref)}" target="_blank" rel="noopener">memoQ ↗</a>`:'—'}<div class="customer-sub">${esc(test.reviewer_name||'Reviewer not set')}</div></td><td><div class="table-actions">${['Assigned','In review'].includes(test.status)?`<button class="table-action success" onclick="recordTestResult('${test.id}','Passed')">Pass</button><button class="table-action danger" onclick="recordTestResult('${test.id}','Failed')">Fail</button>`:''}</div></td></tr>`).join(''):'<tr class="state-row"><td colspan="6">No tests recorded.</td></tr>';
    el('accountQualificationsTbody').innerHTML=accountQualifications.length?accountQualifications.map(row=>`<tr><td>${esc(accountName(row.account_id))}</td><td>${esc(row.specialization_id?specName(row.specialization_id):'All specializations')}</td><td>${qualificationPill(row.qualification_status)}</td><td>${esc(row.evidence||'—')}</td></tr>`).join(''):'<tr class="state-row"><td colspan="4">No Account-specific qualifications.</td></tr>';
}
function updateTestScopeFields(){const type=val('test-type');el('test-spec').disabled=type==='General';el('test-account').disabled=type!=='Account';if(type==='General')el('test-spec').value='';if(type!=='Account')el('test-account').value=''}
function openTestModal(){
    const now=toLocalDT(new Date().toISOString());el('test-type').value='General';el('test-status').value='Assigned';el('test-assigned').value=now;
    el('test-source').innerHTML=languageOptions('','Not specified');el('test-target').innerHTML=languageOptions('','Not specified');
    const configuredServices=[...new Set(services.map(service=>service.service_type))];el('test-service').innerHTML='<option value="">Not specified</option>'+configuredServices.map(service=>`<option>${esc(service)}</option>`).join('');
    el('test-spec').innerHTML=specOptions();el('test-account').innerHTML='<option value="">Select Account…</option>'+accounts.map(account=>`<option value="${account.id}">${esc(account.name)}</option>`).join('');
    ['test-memoq','test-reviewer','test-evidence'].forEach(id=>el(id).value='');updateTestScopeFields();el('testModal').classList.remove('hidden')
}
async function saveTest(){const type=val('test-type');if(type==='Domain'&&!val('test-spec'))return modalError('testError','Select a specialization for a Domain test.');if(type==='Account'&&!val('test-account'))return modalError('testError','Select an Account for an Account test.');const user=(await _sb.auth.getUser()).data.user;const payload={resource_id:resourceId,test_type:type,status:val('test-status'),source_language:nullable('test-source'),target_language:nullable('test-target'),service_type:nullable('test-service'),specialization_id:type==='General'?null:nullable('test-spec'),account_id:type==='Account'?nullable('test-account'):null,assigned_at:val('test-assigned')||new Date().toISOString(),memoq_project_ref:nullable('test-memoq'),reviewer_name:nullable('test-reviewer'),evidence:nullable('test-evidence'),created_by:user?.id||null};const {error}=await _sb.from('resource_tests').insert(payload);if(error)return modalError('testError',error.message);closeModal('testModal');await loadResource();setStatus('Resource test recorded ✓')}
async function recordTestResult(id,status){const test=tests.find(item=>item.id===id);if(!test)return;if(status==='Failed'&&!confirm(`Record this ${test.test_type} test as Failed?${test.test_type==='General'?' The Resource will be marked Do not use.':''}`))return;const {error}=await _sb.from('resource_tests').update({status,completed_at:new Date().toISOString()}).eq('id',id);if(error)return showError(error.message);await loadResource();setStatus(status==='Passed'?'Test passed and qualification updated ✓':'Test failed and restriction updated ✓')}

const canEditCompliance = () => ['admin', 'pm', 'client_relations'].includes(appRole);
const complianceMonth = date => date ? String(date).slice(0, 7) : '';
const complianceFileById = id => complianceFileRecords.find(file => file.id === id);
const readyComplianceDocument = document => {
    const file=complianceFileById(document.file_record_id);
    return ['Pending','Valid'].includes(document.status)
        && file?.upload_status === 'Ready'
        && file?.storage_provider === 'Cloudflare R2'
        && file?.job_id === null
        && file?.file_role === `Compliance - ${document.document_type}`;
};

function evidenceFileCard(document){
    const file=complianceFileById(document.file_record_id);
    if(!file||!readyComplianceDocument(document))return '';
    const reviewed=document.status==='Valid';
    return `<div class="data-card compliance-file-card"><div><strong>${esc(file.original_filename)}</strong><small>${esc(document.document_type)} · ${reviewed?`reviewed ${fmtDateTime(document.reviewed_at)}`:'upload verified · review required for ISO eligibility'}</small></div><div class="table-actions"><button class="table-action" type="button" onclick="openComplianceFile('${file.id}','View')">Open</button><button class="table-action" type="button" onclick="openComplianceFile('${file.id}','Download')">Download</button>${!reviewed&&canEditCompliance()?`<button class="table-action" type="button" onclick="reviewComplianceEvidence('${file.id}')">Confirm evidence</button>`:''}</div></div>`;
}

function renderEducation(){
    const edit=canEditCompliance();
    el('addEducationBtn').classList.toggle('hidden',!edit);
    el('educationList').innerHTML=education.length?education.map(row=>{
        const linked=documents.filter(document=>document.education_id===row.id&&document.document_type==='Diploma / certificate');
        const ready=linked.filter(readyComplianceDocument);
        const graduation=row.graduation_date?complianceMonth(row.graduation_date).replace(/^(\d{4})-(\d{2})$/,'$2/$1'):(row.end_year||'Not recorded');
        const labels=[row.degree_type,row.field_of_study,row.institution,row.country,`Graduation: ${graduation}`].filter(Boolean);
        return `<div class="compliance-education-record"><div class="data-card"><div><strong>${esc(row.degree||row.degree_type||'Degree not specified')}</strong><small>${esc(labels.join(' · '))}</small><small>${row.is_highest_relevant?'Highest relevant degree · ':''}${row.verified?'Reviewed':'Not reviewed'} · ${ready.length} diploma/certificate file${ready.length===1?'':'s'}</small></div><div class="table-actions">${edit?`<button class="table-action" type="button" onclick="openEducationModal('${row.id}')">Edit</button><button class="table-action" type="button" onclick="openComplianceFileModal('Diploma / certificate','${row.id}')">Upload diploma/certificate</button>`:''}</div></div>${ready.map(evidenceFileCard).join('')}</div>`;
    }).join(''):'<div class="empty-compact">No education evidence recorded.</div>';
    const cv=documents.filter(document=>document.document_type==='CV'&&readyComplianceDocument(document));
    el('complianceCvFiles').innerHTML=cv.length?cv.map(evidenceFileCard).join(''):'<div class="empty-compact">No CV evidence files.</div>';
    el('saveProfessionalExperienceBtn').classList.toggle('hidden',!edit);
    el('uploadCvEvidenceBtn').classList.toggle('hidden',!edit);
    ['r-translation-since','r-revision-since','r-mtpe-since'].forEach(id=>el(id).disabled=!edit);
    for(const [id,date] of Object.entries({
        'r-translation-since':resource.translation_professional_since,
        'r-revision-since':resource.revision_professional_since,
        'r-mtpe-since':resource.mtpe_professional_since,
    }))el(id).value=complianceMonth(date);
    const other=documents.filter(document=>!['CV','Diploma / certificate'].includes(document.document_type));
    el('documentsList').innerHTML=other.length?other.map(row=>`<div class="data-card"><div><strong>${esc(row.document_type)}</strong><small>${esc(row.status)}${row.expires_on?` · expires ${fmtDate(row.expires_on)}`:''}</small></div></div>`).join(''):'<div class="empty-compact">No other document metadata.</div>';
}

function openEducationModal(id=null){
    if(!canEditCompliance())return;
    const row=education.find(item=>item.id===id);
    el('educationModalTitle').textContent=row?'Edit education evidence':'Add education evidence';
    el('edu-id').value=row?.id||'';
    for(const [id,value] of Object.entries({
        'edu-institution':row?.institution,
        'edu-degree':row?.degree,
        'edu-degree-type':row?.degree_type,
        'edu-field':row?.field_of_study,
        'edu-country':row?.country,
        'edu-graduation':row?.graduation_date?complianceMonth(row.graduation_date):'',
        'edu-graduation-year':row?.end_year||'',
    }))el(id).value=value||'';
    el('edu-highest').checked=row?!!row.is_highest_relevant:!education.some(item=>item.is_highest_relevant);
    el('edu-verified').checked=!!row?.verified;
    el('educationModal').classList.remove('hidden');
}

async function saveEducation(){
    if(!canEditCompliance())return modalError('educationError','Operational access required.');
    const graduation=val('edu-graduation');
    const graduationYear=val('edu-graduation-year');
    if(graduation&&!/^\d{4}-(0[1-9]|1[0-2])$/.test(graduation))return modalError('educationError','Enter a valid graduation month/year.');
    if(graduationYear&&(!/^\d{1,4}$/.test(graduationYear)||Number(graduationYear)>new Date().getUTCFullYear()))return modalError('educationError','Enter a valid graduation year.');
    const original=education.find(item=>item.id===val('edu-id'));
    const payload={
        institution:nullable('edu-institution'),
        degree:nullable('edu-degree'),
        degree_type:nullable('edu-degree-type'),
        field_of_study:nullable('edu-field'),
        country:nullable('edu-country'),
        graduation_date:graduation?`${graduation}-01`:null,
        end_year:graduation?Number(graduation.slice(0,4)):graduationYear?Number(graduationYear):null,
        verified:el('edu-verified').checked,
        is_highest_relevant:el('edu-highest').checked,
    };
    const button=el('saveEducationBtn');button.disabled=true;
    try{
        const {error}=await _sb.rpc('save_resource_education_047',{
            p_resource_id:resourceId,p_education_id:original?.id||null,p_payload:payload
        });
        if(error)throw error;
        closeModal('educationModal');await loadResource();
        setStatus(original?'Education updated ✓':'Education added ✓');
    }catch(error){modalError('educationError',error.message)}
    finally{button.disabled=false}
}

function renderComplianceSummary(){
    if(!complianceSummary)return;
    const experiences=complianceSummary.professional_experience||{};
    for(const [service,[id,label]] of Object.entries({
        translation:['translationExperience','Translation experience'],
        revision:['revisionExperience','Revision experience'],
        mtpe:['mtpeExperience','MTPE experience']
    }))el(id).textContent=`${label}: ${experiences[service]?.display||'Not recorded'}`;

    for(const [key,id] of Object.entries({
        translator:'isoTranslatorEligibility',
        reviser:'isoReviserEligibility',
        post_editor:'isoPostEditorEligibility',
    })){
        const result=complianceSummary.iso_eligibility?.[key];
        if(!result)continue;
        const row=el(id),badge=row.querySelector('summary strong'),explanation=row.querySelector('p');
        badge.textContent=result.status;
        badge.className=`pill ${result.eligible?'pill-green':'pill-amber'}`;
        explanation.textContent=result.explanation;
    }
}

async function refreshComplianceSummary(){
    if(!resourceId||resource?.resource_type==='Internal'||!['admin','pm','qa','client_relations'].includes(appRole))return;
    const {data,error}=await _sb.rpc('resource_compliance_summary_047',{p_resource_id:resourceId});
    if(error){showError(`Compliance calculation unavailable: ${error.message}`);return}
    complianceSummary=data;renderComplianceSummary();
}

function scheduleComplianceRefresh(){
    clearTimeout(complianceRefreshTimer);
    const now=Date.now(),nextUtcMidnight=Date.UTC(
        new Date(now).getUTCFullYear(),new Date(now).getUTCMonth(),new Date(now).getUTCDate()+1
    );
    complianceRefreshTimer=setTimeout(async()=>{
        try{
            await refreshComplianceSummary();
            if(!el('blindCvModal').classList.contains('hidden'))await refreshBlindCvData();
        }catch(error){showError(error.message)}finally{scheduleComplianceRefresh()}
    },Math.max(1000,nextUtcMidnight-now+2500));
}

async function saveProfessionalExperience(){
    if(!canEditCompliance())return showError('Operational access required.');
    const inputs=['r-translation-since','r-revision-since','r-mtpe-since'].map(val);
    const now=new Date(),currentMonth=`${now.getUTCFullYear()}-${String(now.getUTCMonth()+1).padStart(2,'0')}`;
    if(inputs.some(value=>value&&!/^\d{4}-(0[1-9]|1[0-2])$/.test(value)))return showError('Use valid MM/YYYY professional start dates.');
    if(inputs.some(value=>value&&value>currentMonth))return showError('Professional start dates cannot be in the future.');
    const button=el('saveProfessionalExperienceBtn');button.disabled=true;
    const dates=inputs.map(value=>value?`${value}-01`:null);
    try{
        const {error}=await _sb.rpc('save_resource_professional_since_047',{
            p_resource_id:resourceId,
            p_translation_since:dates[0],p_revision_since:dates[1],p_mtpe_since:dates[2]
        });
        if(error)throw error;
        await loadResource();setStatus('Professional start dates updated ✓');
    }catch(error){showError(error.message)}finally{button.disabled=false}
}

async function complianceFileApi(action,payload={}){
    const {data:{session}}=await _sb.auth.getSession();
    if(!session?.access_token)throw new Error('Session expired. Sign in again.');
    const response=await fetch('/.netlify/functions/resource-compliance-files',{
        method:'POST',
        headers:{'Content-Type':'application/json',Authorization:`Bearer ${session.access_token}`},
        body:JSON.stringify({action,...payload})
    });
    const result=await response.json().catch(()=>({}));
    if(!response.ok)throw new Error(result.error||`Compliance file request failed (HTTP ${response.status}).`);
    return result;
}

function openComplianceFileModal(type,educationId=null){
    if(!canEditCompliance())return;
    if(!['Diploma / certificate','CV'].includes(type))return;
    el('compliance-evidence-type').value=type;
    el('compliance-education-id').value=educationId||'';
    el('complianceFileModalTitle').textContent=`Upload ${type} evidence`;
    el('complianceFileInput').value='';
    el('complianceFileProgress').textContent='';
    el('complianceFileError').classList.add('hidden');
    el('complianceFileModal').classList.remove('hidden');
}

async function uploadComplianceFiles(){
    if(!canEditCompliance())return modalError('complianceFileError','Operational access required.');
    const files=[...(el('complianceFileInput').files||[])];
    if(!files.length)return modalError('complianceFileError','Choose at least one evidence file.');
    if(!globalThis.TMS_FILE_HASH?.sha256Hex)return modalError('complianceFileError','The secure file hasher is unavailable. Refresh the page.');
    const type=val('compliance-evidence-type'),educationId=nullable('compliance-education-id');
    const button=el('uploadComplianceFileBtn');button.disabled=true;
    let uploaded=0;
    try{
        for(const file of files){
            let prepared=null;
            try{
                el('complianceFileProgress').textContent=`Checking ${file.name} (${uploaded+1}/${files.length})…`;
                const checksum=await TMS_FILE_HASH.sha256Hex(file);
                prepared=await complianceFileApi('prepare_upload',{
                    resource_id:resourceId,
                    education_id:educationId,
                    evidence_type:type,
                    original_filename:file.name,
                    mime_type:file.type||'application/octet-stream',
                    size_bytes:file.size,
                    checksum_sha256:checksum
                });
                if(!prepared.file_id||!prepared.upload_url)throw new Error('Private R2 upload ticket incomplete.');
                el('complianceFileProgress').textContent=`Uploading ${file.name} (${uploaded+1}/${files.length})…`;
                const response=await fetch(prepared.upload_url,{
                    method:'PUT',headers:prepared.upload_headers||{},body:file
                });
                if(!response.ok)throw new Error(`Cloudflare R2 rejected the upload (HTTP ${response.status}).`);
                el('complianceFileProgress').textContent=`Verifying ${file.name}…`;
                await complianceFileApi('complete_upload',{file_id:prepared.file_id});
                uploaded++;
            }catch(error){
                if(prepared?.file_id)await complianceFileApi('discard_upload',{file_id:prepared.file_id}).catch(()=>{});
                throw error;
            }
        }
        closeModal('complianceFileModal');
        await loadResource();
        setStatus(`${uploaded} Compliance evidence file${uploaded===1?'':'s'} uploaded ✓`);
    }catch(error){
        await loadResource();
        modalError('complianceFileError',`${uploaded} uploaded; next file not published: ${error.message}`);
    }finally{button.disabled=false}
}

async function openComplianceFile(fileId,action='View'){
    const evidence=documents.find(row=>row.file_record_id===fileId);
    if(!evidence||!readyComplianceDocument(evidence))return showError('Compliance file unavailable.');
    try{
        const signed=await complianceFileApi('download',{
            file_id:fileId,file_action:action
        });
        const link=document.createElement('a');
        link.href=signed.download_url;link.rel='noopener noreferrer';
        if(action==='Download')link.download=signed.filename||'evidence';
        else link.target='_blank';
        document.body.appendChild(link);link.click();link.remove();
    }catch(error){showError(error.message)}
}

async function reviewComplianceEvidence(fileId){
    if(!canEditCompliance())return showError('Operational access required.');
    const evidence=documents.find(row=>row.file_record_id===fileId);
    if(!evidence||!readyComplianceDocument(evidence))return showError('Compliance evidence unavailable.');
    if(!confirm('Confirm that you have inspected this evidence file and it supports the recorded qualification or experience?'))return;
    try{
        await complianceFileApi('review_evidence',{file_id:fileId});
        await loadResource();setStatus('Compliance evidence confirmed ✓');
    }catch(error){showError(error.message)}
}

function renderHistory(){el('historyTbody').innerHTML=history.length?history.map(row=>`<tr><td>${row.period_start?fmtDate(row.period_start):row.project_year||'—'}${row.period_end?` – ${fmtDate(row.period_end)}`:''}</td><td>${esc(row.account_display_label||'Confidential account')}</td><td>${esc(row.source_language||'—')} → ${esc(row.target_language||'—')}</td><td>${esc(row.service_type||'—')}</td><td>${esc(specName(row.specialization_id))}</td><td>${esc(row.project_summary||'—')}</td><td><input type="checkbox" ${row.include_in_blind_cv?'checked':''} onchange="toggleHistoryCv('${row.id}',this.checked)"></td></tr>`).join(''):'<tr class="state-row"><td colspan="7">No approved Job history.</td></tr>'}
async function toggleHistoryCv(id,checked){const {error}=await _sb.from('resource_project_history').update({include_in_blind_cv:checked}).eq('id',id);if(error)return showError(error.message);setStatus('CV inclusion updated ✓')}
function renderAvailability(){el('availabilityTbody').innerHTML=availability.length?availability.map(row=>`<tr><td><span class="pill ${row.status==='Available'?'pill-green':row.status==='Limited'?'pill-amber':'pill-red'}">${esc(row.status)}</span></td><td>${fmtDateTime(row.starts_at)}</td><td>${fmtDateTime(row.ends_at)}</td><td>${esc(row.notes||'—')}</td></tr>`).join(''):'<tr class="state-row"><td colspan="4">No availability records.</td></tr>'}
function openAvailabilityModal(){const now=new Date().toISOString();el('av-status').value='Available';el('av-start-date').value=datePart(now);el('av-start-time').value=timePart(now);el('av-end-date').value='';el('av-end-time').value='';el('av-notes').value='';el('availabilityModal').classList.remove('hidden')}
async function saveAvailability(){const start=combineDateTime('av-start-date','av-start-time'),end=combineDateTime('av-end-date','av-end-time');if(!start)return modalError('availabilityError','A start date is required.');const user=(await _sb.auth.getUser()).data.user;const {error}=await _sb.from('resource_availability').insert({resource_id:resourceId,status:val('av-status'),starts_at:start,ends_at:end,notes:nullable('av-notes'),created_by:user?.id||null});if(error)return modalError('availabilityError',error.message);closeModal('availabilityModal');await loadResource();setStatus('Availability added ✓')}

function renderPrivateNotes(){if(appRole!=='admin')return;el('privateArchiveCard').classList.remove('hidden');el('privateNotesList').innerHTML=privateNotes.length?privateNotes.map(row=>`<div class="private-note"><strong>${esc(row.note_type)}</strong><span>${fmtDateTime(row.created_at)}</span><p>${esc(row.content)}</p>${row.source_record?`<small>${esc(row.source_record)}</small>`:''}</div>`).join(''):'<div class="empty-compact">No private archived notes.</div>'}
async function addPrivateNote(){if(!val('new-private-note'))return;const user=(await _sb.auth.getUser()).data.user;const {error}=await _sb.from('resource_private_notes').insert({resource_id:resourceId,note_type:'Private management note',content:val('new-private-note'),created_by:user?.id||null});if(error)return showError(error.message);el('new-private-note').value='';await loadResource();setStatus('Private note added ✓')}

function cvText(value,fallback='Not recorded'){return value&&String(value).trim()?String(value):fallback}
function blindCvExperienceLines(){const experience=cvData?.professional_experience||{};return [['Translation experience',experience.translation],['Revision experience',experience.revision],['MTPE experience',experience.mtpe]].map(([label,result])=>`${label}: ${result?.display||'Not recorded'}`)}
function renderBlindCvPreview(){const r=cvData.resource,lp=cvData.language_pairs||[],hist=cvData.project_history||[];el('blindCvPreview').innerHTML=`<div class="cv-brand"><strong>Retodo Ops</strong><span>Blind Linguist Profile</span></div><h2>${esc(r.internal_number)} · ${esc(cvText(r.initials))}</h2><div class="cv-meta"><span><b>Nationality:</b> ${esc(cvText(r.nationality))}</span><span><b>Residence:</b> ${esc(cvText(r.country_of_residence))}</span><span><b>Native language:</b> ${esc(cvText(r.native_language))}</span></div><h3>Language coverage</h3><p>${lp.length?lp.map(x=>`${esc(x.source)} → ${esc(x.target)}${x.native_target?' (native target)':''}`).join('; '):'Not recorded'}</p><h3>Professional experience</h3><ul>${blindCvExperienceLines().map(line=>`<li>${esc(line)}</li>`).join('')}</ul><h3>Services and specializations</h3><p><b>Services:</b> ${esc((cvData.services||[]).join(', ')||'Not recorded')}</p><ul>${(cvData.specializations||[]).map(x=>`<li>${esc(x.name)}${x.experience_years?` — ${x.experience_years} years`:''}</li>`).join('')||'<li>Not recorded</li>'}</ul><h3>Education</h3><ul>${(cvData.education||[]).map(x=>`<li>${esc([x.degree,x.field_of_study,x.institution].filter(Boolean).join(', '))}${x.end_year?` (${x.start_year||'—'}–${x.end_year})`:''}</li>`).join('')||'<li>Not recorded</li>'}</ul><h3>Selected project experience</h3><ul>${hist.map(x=>`<li>${esc(String(x.year||''))} · ${esc(cvText(x.account,'Confidential account'))} · ${esc(cvText(x.source_language,'—'))} → ${esc(cvText(x.target_language,'—'))} · ${esc([x.service,x.specialization].filter(Boolean).join(', '))}</li>`).join('')||'<li>No approved project history selected.</li>'}</ul><div class="cv-footer">Prepared by Retodo Ops · Personal identity and direct contact details withheld</div>`}
async function refreshBlindCvData(){const {data,error}=await _sb.rpc('get_blind_cv_data',{p_resource_id:resourceId});if(error)throw error;cvData=data;renderBlindCvPreview()}
async function openBlindCv(){el('blindCvModal').classList.remove('hidden');el('blindCvPreview').textContent='Preparing anonymized profile…';try{await refreshBlindCvData()}catch(error){modalError('blindCvError',error.message)}}
function saveBlob(blob,filename){const url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=filename;document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1000)}
function cvLines(){const r=cvData.resource;return [{heading:'Linguist profile',lines:[`${r.internal_number} · ${cvText(r.initials)}`,`Nationality: ${cvText(r.nationality)}`,`Country of residence: ${cvText(r.country_of_residence)}`,`Native language: ${cvText(r.native_language)}`]},{heading:'Language coverage',lines:(cvData.language_pairs||[]).map(x=>`${x.source} → ${x.target}${x.native_target?' (native target)':''}`)},{heading:'Professional experience',lines:blindCvExperienceLines()},{heading:'Services',lines:cvData.services||[]},{heading:'Specializations',lines:(cvData.specializations||[]).map(x=>`${x.name}${x.experience_years?` — ${x.experience_years} years`:''}`)},{heading:'Education',lines:(cvData.education||[]).map(x=>[x.degree,x.field_of_study,x.institution,x.start_year||x.end_year?`${x.start_year||'—'}–${x.end_year||'—'}`:''].filter(Boolean).join(', '))},{heading:'Selected project experience',lines:(cvData.project_history||[]).map(x=>`${x.year||''} · ${cvText(x.account,'Confidential account')} · ${cvText(x.source_language,'—')} → ${cvText(x.target_language,'—')} · ${[x.service,x.specialization].filter(Boolean).join(', ')}`)}]}
async function downloadBlindCvDocx(){if(!cvData)return;try{await refreshBlindCvData();const {Document,Packer,Paragraph,TextRun,HeadingLevel,AlignmentType}=window.docx;const children=[new Paragraph({alignment:AlignmentType.CENTER,children:[new TextRun({text:'Retodo Ops',bold:true,size:32,color:'1E1248'})]}),new Paragraph({alignment:AlignmentType.CENTER,children:[new TextRun({text:'BLIND LINGUIST PROFILE',bold:true,size:22,color:'7C3AED'})]})];cvLines().forEach(section=>{children.push(new Paragraph({text:section.heading,heading:HeadingLevel.HEADING_2,spacing:{before:240,after:80}}));(section.lines.length?section.lines:['Not recorded']).forEach(line=>children.push(new Paragraph({text:line,bullet:section.heading==='Linguist profile'?undefined:{level:0}}))) });children.push(new Paragraph({alignment:AlignmentType.CENTER,spacing:{before:320},children:[new TextRun({text:'Personal identity and direct contact details withheld',italics:true,color:'6B7280',size:18})]}));const doc=new Document({sections:[{properties:{},children}]});saveBlob(await Packer.toBlob(doc),`Blind_CV_${cvData.resource.internal_number}.docx`)}catch(error){modalError('blindCvError',`DOCX generation failed: ${error.message}`)}}
async function downloadBlindCvPdf(){if(!cvData)return;try{await refreshBlindCvData();await window.html2pdf().set({margin:[10,10,10,10],filename:`Blind_CV_${cvData.resource.internal_number}.pdf`,image:{type:'jpeg',quality:.98},html2canvas:{scale:2,useCORS:true},jsPDF:{unit:'mm',format:'a4',orientation:'portrait'},pagebreak:{mode:['css','legacy']}}).from(el('blindCvPreview')).save()}catch(error){modalError('blindCvError',`PDF generation failed: ${error.message}`)}}

async function loadResource(){
    const base=await _sb.from('resources').select('*').eq('id',resourceId).single();
    if(base.error)return showError(base.error.message);
    resource=base.data;
    const requests=[
        _sb.from('resource_language_pairs').select('*').eq('resource_id',resourceId).order('target_language'),
        _sb.from('resource_services').select('*').eq('resource_id',resourceId).order('service_type'),
        _sb.from('specializations').select('*').eq('active',true).order('name'),
        _sb.from('resource_specializations').select('*').eq('resource_id',resourceId),
        _sb.from('resource_rates').select('*').eq('resource_id',resourceId).order('created_at',{ascending:false}),
        _sb.from('resource_tests').select('*').eq('resource_id',resourceId).order('assigned_at',{ascending:false}),
        _sb.from('resource_account_qualifications').select('*').eq('resource_id',resourceId).order('updated_at',{ascending:false}),
        _sb.from('client_accounts').select('id,name').order('name'),
        _sb.from('resource_education').select('*').eq('resource_id',resourceId).order('sort_order'),
        _sb.from('resource_documents').select('*').eq('resource_id',resourceId).order('created_at',{ascending:false}),
        _sb.from('resource_project_history').select('*').eq('resource_id',resourceId).order('project_year',{ascending:false}),
        _sb.from('resource_availability').select('*').eq('resource_id',resourceId).order('starts_at',{ascending:false})
    ];
    if(appRole==='admin')requests.push(
        _sb.from('resource_private_notes').select('*').eq('resource_id',resourceId).order('created_at',{ascending:false})
    );
    const result=await Promise.all(requests);
    [pairs,services,specializations,resourceSpecializations,rates,tests,accountQualifications,accounts,education,documents,history,availability]=result.slice(0,12).map(x=>x.data||[]);
    privateNotes=appRole==='admin'?(result[12]?.data||[]):[];
    const evidenceIds=[...new Set(documents.filter(document=>['CV','Diploma / certificate'].includes(document.document_type)).map(document=>document.file_record_id).filter(Boolean))];
    if(evidenceIds.length){
        const files=await _sb.from('file_records').select('id,original_filename,upload_status,storage_provider,job_id,file_role').in('id',evidenceIds);
        if(files.error)showError(`Compliance file metadata unavailable: ${files.error.message}`);
        complianceFileRecords=files.data||[];
    }else complianceFileRecords=[];
    populateOverview();renderPairs();renderServices();renderSpecializations();renderRates();renderTests();
    renderEducation();renderHistory();renderAvailability();renderPrivateNotes();
    await refreshComplianceSummary();
}

// Update 036: an Account carries its default specializations into the
// Resource rate-card editor, preventing an Account/rate-card discrepancy.
function accountDefaultSpecializationIds(accountId){
    return accountSpecializationDefaults.filter(row=>row.account_id===accountId).sort((a,b)=>Number(b.is_default)-Number(a.is_default)).map(row=>row.specialization_id);
}
function renderRateSpecializationOptions(selected=''){
    const accountId=val('rate-account'),configured=new Set(resourceSpecializations.map(row=>row.specialization_id)),defaults=accountDefaultSpecializationIds(accountId),allowed=[...new Set([...configured,...defaults,...(selected?[selected]:[])])],chosen=selected||defaults[0]||'';
    el('rate-spec').innerHTML='<option value="">All configured specializations</option>'+specializations.filter(spec=>allowed.includes(spec.id)).map(spec=>'<option value="'+spec.id+'">'+esc(spec.name)+'</option>').join('');
    if(chosen&&allowed.includes(chosen))el('rate-spec').value=chosen;
    const help=el('rate-spec-help');if(help)help.textContent=accountId&&defaults.length?'Preselected from this Account.':'Choose the specialization configured for this rate.';
}
function openRateModal(baseId=null){
    const base=rates.find(rate=>rate.id===baseId&&!rate.base_rate_id);el('rateModalTitle').textContent=base?'Edit supplier rate card':'Add supplier rate card';el('saveRateBtn').textContent=base?'Save changes':'Save rate card';el('rate-id').value=base?.id||'';renderRateLanguageOptions(base);
    const catalog=[...TMS_REF.services];if(base?.service_type&&!catalog.includes(base.service_type))catalog.push(base.service_type);el('rate-service').innerHTML=catalog.map(service=>'<option>'+esc(service)+'</option>').join('');
    el('rate-account').innerHTML='<option value="">All Accounts</option>'+accounts.map(account=>'<option value="'+account.id+'" '+(account.id===base?.account_id?'selected':'')+'>'+esc(account.name)+'</option>').join('');
    el('rate-value').value=base?.rate??'';el('rate-minimum').value=base?.minimum_fee??'';el('rate-currency').value=base?.currency||'EUR';el('rate-unit').value=base?.unit||'Source words';el('rate-status').value=base?.status||'Pending';
    if(base)el('rate-service').value=base.service_type;
    renderRateSpecializationOptions(base?.specialization_id||'');renderCatDiscountRows(base?.id||null);toggleCatDiscounts();el('rateModal').classList.remove('hidden');
}
async function saveRate(){
    const sources=selectedRateLanguages('rate-sources'),targets=selectedRateLanguages('rate-targets');if(!sources.length||!targets.length)return modalError('rateError','Select at least one Source and one Target language.');
    if(!val('rate-service'))return modalError('rateError','Select a service from the Settings catalog.');
    if(val('rate-value')===''||Number(val('rate-value'))<0)return modalError('rateError','Enter a valid base price.');
    const discounts=[...el('catDiscountRows').querySelectorAll('.cat-discount')].filter(input=>input.value!=='').map(input=>({cat_band:input.dataset.band,discount_percent:Number(input.value)}));if(discounts.some(item=>item.discount_percent<0||item.discount_percent>100))return modalError('rateError','CAT discounts must be between 0% and 100%.');
    const specializationId=nullable('rate-spec');
    if(specializationId&&!resourceSpecializations.some(row=>row.specialization_id===specializationId)){const capability=await _sb.from('resource_specializations').insert({resource_id:resourceId,specialization_id:specializationId,qualification_status:'Not tested'});if(capability.error)return modalError('rateError','The Account specialization could not be added to this Resource: '+capability.error.message)}
    const baseId=val('rate-id'),payload={base_rate_id:baseId||null,resource_id:resourceId,account_id:nullable('rate-account'),source_languages:sources,target_languages:targets,service_type:val('rate-service'),specialization_id:specializationId,unit:val('rate-unit'),base_rate:Number(val('rate-value')),currency:val('rate-currency'),minimum_fee:val('rate-minimum')===''?null:Number(val('rate-minimum')),status:val('rate-status'),cat_discounts:['Source words','Target words'].includes(val('rate-unit'))?discounts:[]};
    const {error}=await _sb.rpc('save_scoped_resource_rate_card',{p_payload:payload});if(error)return modalError('rateError',error.message);closeModal('rateModal');await loadResource();setStatus(baseId?'Supplier rate card updated ✓':'Supplier rate card added ✓');
}
const loadResourceWithoutAccountDefaults=loadResource;
loadResource=async function(){await loadResourceWithoutAccountDefaults();const result=await _sb.from('client_account_specializations').select('account_id,specialization_id,is_default');accountSpecializationDefaults=result.data||[];renderRates();await loadPortalLinkStatus()};
document.querySelectorAll('.record-tab').forEach(tab=>tab.addEventListener('click',()=>{document.querySelectorAll('.record-tab').forEach(t=>t.classList.toggle('active',t===tab));document.querySelectorAll('.record-pane').forEach(pane=>pane.classList.toggle('active',pane.id===`pane-${tab.dataset.tab}`))}));
el('r-name').addEventListener('input',event=>{el('r-initials').value=initialsFromName(event.target.value)});
document.querySelectorAll('#r-internal-positions input').forEach(input=>input.addEventListener('change',updateInternalPositionsSummary));
el('rate-unit').addEventListener('change',toggleCatDiscounts);el('rate-value').addEventListener('input',calculateCatRates);el('rate-currency').addEventListener('change',calculateCatRates);
el('rate-account').addEventListener('change',()=>renderRateSpecializationOptions());
el('test-type').addEventListener('change',updateTestScopeFields);
document.addEventListener('visibilitychange',()=>{
    if(!document.hidden){
        refreshComplianceSummary();
        if(!el('blindCvModal').classList.contains('hidden'))refreshBlindCvData().catch(error=>showError(error.message));
    }
});
(async()=>{const user=await requireAuth();if(!user)return;await Promise.all([TMS_REF.loadLanguages(_sb),TMS_REF.loadServices(_sb)]);TMS_REF.installDatalists();TMS_REF.populateServiceSelect('service-name');resourceId=new URLSearchParams(location.search).get('id');if(!resourceId){location.href='resources.html?type=external';return}const role=await _sb.rpc('current_app_role');appRole=role.data||'user';await loadResource();scheduleComplianceRefresh()})();

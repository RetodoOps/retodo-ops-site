'use strict';
/* Sales signature controls. The renderer itself is shared with the mail worker. */
function salesSignatureFromForm(form){
 const f=Object.fromEntries(new FormData(form));
 return {...SalesSignature.DEFAULTS,closing:f.signature_closing.trim(),position:f.signature_position.trim(),website_url:f.signature_website.trim(),linkedin_url:f.signature_linkedin.trim(),confidentiality:f.signature_confidentiality.replace(/\s*[\r\n]+\s*/g,' ').trim(),show_logo:f.signature_logo==='on'};
}
function salesSignatureSettings(settings){
 if(!settings.email_signature)return '<section class="sales-card"><h2>Eli’s email signature</h2><p>Install Update 064 database migration 059, then refresh to configure the signature.</p></section>';
 const s=settings.email_signature;
 return `<section class="sales-card" id="salesSignatureSettings"><h2>Eli’s email signature</h2><p class="sales-small">Used in Sales emails from eli.s@retodo-ops.com.</p><label class="sales-check"><input type="checkbox" name="signature_enabled" ${settings.signature_enabled?'checked':''}>Include automatically in new emails, follow-ups and replies</label><div class="sales-fields sales-signature-fields">
 ${salesField('Closing','signature_closing',s.closing,'text',true,'required maxlength="80"')}
 <div class="sales-field full"><span>Name</span><strong>Eli Stoyanova</strong></div>
 ${salesField('Position','signature_position',s.position,'text',true,'required maxlength="160"')}
 ${salesField('Website link','signature_website',s.website_url,'url',true,'required maxlength="500"')}
 ${salesField('LinkedIn profile or company link (optional)','signature_linkedin',s.linkedin_url,'url',true,'maxlength="500"')}
 ${salesField('Confidentiality note (optional)','signature_confidentiality',s.confidentiality,'textarea',true,'rows="3" maxlength="300"')}
 <label class="sales-check full"><input type="checkbox" name="signature_logo" ${s.show_logo?'checked':''}>Show the compact company logo</label></div>
 <p class="sales-small">Changes apply to new drafts. Existing messages keep the signature you reviewed; use Edit draft to update one.</p>
 <p class="sales-small"><strong>Signature preview</strong></p><div class="sales-signature-preview" id="salesSignaturePreview">${SalesSignature.html(s)}</div><div class="sales-signature-error" id="salesSignatureError" role="status"></div>
 <button type="submit" class="btn-secondary">Save signature</button></section>`;
}
function salesMessageContent(message){
 try{return `<div class="sales-pre sales-email-preview">${SalesSignature.messageHtml(message.body,message.signature)}</div>`;}
 catch{return `<div class="sales-pre">${salesEsc(message.body)}</div><p class="sales-error">This signature cannot be displayed. Edit the draft and use the current Sales signature before approving.</p>`;}
}
function salesSignatureControl(bodyField,controlName,body='',message=null){
 const current=SALES.data.settings.email_signature||{},saved=message?.signature||{};
 const enabled=Boolean(SALES.data.settings.signature_enabled&&SALES.data.settings.email_signature);
 const control=message
  ? `<label class="sales-field full"><span>Signature</span><select name="${controlName}"><option value="keep">${Object.keys(saved).length?'Keep this message’s saved signature':'Keep without a signature'}</option><option value="current" ${!SALES.data.settings.email_signature?'disabled':''}>Use current Sales signature</option><option value="none">No signature</option></select></label>`
  : `<label class="sales-check"><input type="checkbox" name="${controlName}" ${enabled?'checked':''} ${!SALES.data.settings.email_signature?'disabled':''}>Include Eli’s signature</label>`;
 const sig=message?saved:enabled?current:{};
 return `<div class="sales-signature-choice">${control}<p class="sales-small">The preview includes the signature below your message. If you already typed a signature, choose no automatic signature to avoid repeating it.</p><details class="sales-compose-preview" data-message-preview data-body-field="${bodyField}" data-control-name="${controlName}" data-saved-signature="${salesEsc(JSON.stringify(saved))}"><summary>Preview complete email</summary><div class="sales-pre sales-email-preview">${SalesSignature.messageHtml(body,sig)}</div></details></div>`;
}
function salesRefreshSignaturePreviews(){
 const settings=salesEl('salesSettingsForm'),preview=salesEl('salesSignaturePreview');
 if(settings&&preview){
  try{preview.innerHTML=SalesSignature.html(salesSignatureFromForm(settings));salesEl('salesSignatureError').textContent='';}
  catch(e){preview.textContent='Complete the signature fields to see the preview.';salesEl('salesSignatureError').textContent=e.message;}
 }
 document.querySelectorAll('[data-message-preview]').forEach(container=>{
  const form=container.closest('form'),control=form.elements.namedItem(container.dataset.controlName),body=form.elements.namedItem(container.dataset.bodyField).value;
  const mode=control.type==='checkbox'?(control.checked?'current':'none'):control.value;
  const sig=mode==='keep'?JSON.parse(container.dataset.savedSignature):mode==='current'?SALES.data.settings.email_signature||{}:{};
  container.querySelector('.sales-email-preview').innerHTML=SalesSignature.messageHtml(body,sig);
 });
}

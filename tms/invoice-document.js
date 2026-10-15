/* Update 065: one saved-data model for localized PDF and native editable DOCX.
 * No network calls, machine translation, tax inference or changes to invoice records.
 * DOCX 9.6.1 is vendored under its MIT license in vendor/docx-LICENSE. */
(function(root){
'use strict';
const labels={
 en:{invoice:'Invoice',draft:'Draft',warning:'DRAFT — NOT AN ISSUED INVOICE',issue:'Issue date',due:'Due date',terms:'Payment terms',days:'days',currency:'Currency',from:'From',to:'Bill to',registration:'Registration',vat:'VAT',description:'Description',amount:'Amount',subtotal:'Subtotal',tax:'Tax',total:'Total',bank:'Bank',iban:'IBAN',swift:'SWIFT / BIC',reference:'Payment reference',po:'PO',unset:'Not set'},
 bg:{invoice:'Фактура',draft:'Чернова',warning:'ЧЕРНОВА — НЕ Е ИЗДАДЕНА ФАКТУРА',issue:'Дата на издаване',due:'Падеж',terms:'Срок за плащане',days:'дни',currency:'Валута',from:'Доставчик',to:'Получател',registration:'ЕИК / Рег. номер',vat:'ДДС номер',description:'Описание',amount:'Сума',subtotal:'Данъчна основа',tax:'ДДС',total:'Обща сума',bank:'Банка',iban:'IBAN',swift:'SWIFT / BIC',reference:'Основание за плащане',po:'Поръчка',unset:'Не е зададено'}
};
const clean=v=>String(v??'').replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g,'');
const escape=v=>clean(v).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
function model(invoice,billing,issuer,language='en'){
 const lang=language==='bg'?'bg':'en',t=labels[lang],locale=lang==='bg'?'bg-BG':'en-GB';
 const number=n=>Number(n||0).toLocaleString(locale,{minimumFractionDigits:2,maximumFractionDigits:2});
 const date=v=>/^\d{4}-\d{2}-\d{2}$/.test(v||'')?new Date(v+'T12:00:00Z').toLocaleDateString(locale,{timeZone:'UTC'}):t.unset;
 const lines=(invoice.lines||[]).map(l=>({description:clean(l.description),amount:number(l.amount),source:l.scoop_id?[l.source_snapshot?.project_number,l.source_snapshot?.client_po?t.po+' '+l.source_snapshot.client_po:null].filter(Boolean).join(' · '):''}));
 const party=(name,address,registration,vat,contact)=>[name,...address,registration?t.registration+': '+registration:null,vat?t.vat+': '+vat:null,contact].filter(Boolean).map(clean);
 const from=party(issuer.legal_name,[issuer.address],issuer.registration_number,issuer.vat_number,issuer.contact);
 const to=party(billing.legal_name,[billing.address_line_1,billing.address_line_2,[billing.postal_code,billing.city].filter(Boolean).join(' '),billing.region,billing.country_code],billing.registration_number,billing.vat_number);
 const ref=invoice.invoice_number||t.draft;
 return {lang,t,ref,title:t.invoice+' '+ref,isDraft:invoice.status==='Draft',currency:clean(invoice.currency),from,to,lines,
  metadata:[[t.issue,date(invoice.issue_date)],[t.due,date(invoice.due_date)],[t.terms,invoice.payment_terms_days==null?t.unset:invoice.payment_terms_days+' '+t.days],[t.currency,clean(invoice.currency)]],
  totals:[[t.subtotal,number(invoice.subtotal)],[t.tax+' ('+Number(invoice.tax_rate||0).toLocaleString(locale)+'%)',number(invoice.tax_amount)],[t.total,clean(invoice.currency)+' '+number(invoice.total)]],
  notes:[invoice.tax_note,invoice.notes].filter(Boolean).map(clean),bank:[[t.bank,issuer.bank||'—'],[t.iban,issuer.iban||'—'],...(issuer.swift?[[t.swift,issuer.swift]]:[]),[t.reference,ref]].map(([k,v])=>[k,clean(v)])};
}
function filename(m){return 'Invoice_'+m.ref.replace(/[^\p{L}\p{N}_-]/gu,'_')+'_'+m.lang;}
function html(m){const e=escape,kv=items=>items.map(([k,v])=>`<b>${e(k)}:</b> ${e(v)}`).join('<br>');
 return `<!doctype html><html lang="${m.lang}"><head><meta charset="UTF-8"><title>${e(m.title)}</title><style>
 body{font:12px Arial,sans-serif;color:#263248;margin:32px;overflow-wrap:anywhere}h1{font-size:27px;color:#000}h2{font-size:15px;color:#000}.parties{display:flex;justify-content:space-between;gap:35px}.parties>div{width:48%}p{line-height:1.5;white-space:pre-line}table{width:100%;border-collapse:collapse;margin-top:28px;table-layout:fixed}th,td{padding:12px 8px;border:1px solid #d9d9d9;text-align:left;overflow-wrap:anywhere}th{background:#eef2f7}td:last-child,th:last-child{text-align:right;width:26%}tr{break-inside:avoid}small{display:block;color:#646c7c;margin-top:5px}.totals{text-align:right;line-height:1.9;font-size:14px}.bank{border-top:1px solid #ccc;margin-top:24px;padding-top:14px}.draft{color:#a44;font-weight:bold}@page{size:A4;margin:18mm}@media print{body{margin:0}thead{display:table-header-group}}
 </style></head><body>${m.isDraft?`<p class="draft">${e(m.t.warning)}</p>`:''}<h1>${e(m.title)}</h1><p>${kv(m.metadata)}</p><div class="parties"><div><h2>${e(m.t.from)}</h2><p>${m.from.map(e).join('<br>')}</p></div><div><h2>${e(m.t.to)}</h2><p>${m.to.map(e).join('<br>')}</p></div></div><table><thead><tr><th>${e(m.t.description)}</th><th>${e(m.t.amount)} (${e(m.currency)})</th></tr></thead><tbody>${m.lines.map(l=>`<tr><td>${e(l.description).replace(/\n/g,'<br>')}${l.source?'<small>'+e(l.source)+'</small>':''}</td><td>${e(l.amount)}</td></tr>`).join('')}</tbody></table><p class="totals">${kv(m.totals)}</p>${m.notes.map(n=>`<p>${e(n)}</p>`).join('')}<div class="bank"><p>${kv(m.bank)}</p></div></body></html>`;
}
async function word(m,D){
 if(!D?.Document)throw new Error('Word export library could not load. Refresh and try again.');
 const {Document,Paragraph,TextRun,Table,TableRow,TableCell,WidthType,AlignmentType,BorderStyle,Packer,HeadingLevel}=D;
 const run=(text,options={})=>new TextRun({text:clean(text),...options});
 const paragraph=(text,options={})=>new Paragraph({children:clean(text).split('\n').flatMap((line,i)=>[...(i?[new TextRun({break:1})]:[]),run(line)]),spacing:{after:100},...options});
 const labeled=([k,v],right=false)=>new Paragraph({children:[run(k+': ',{bold:true}),run(v)],alignment:right?AlignmentType.RIGHT:AlignmentType.LEFT,spacing:{after:100}});
 const border={style:BorderStyle.SINGLE,size:4,color:'D9D9D9'};
 const cell=(text,width,header=false,right=false,shade=false)=>new TableCell({width:{size:width,type:WidthType.DXA},verticalAlign:'center',margins:{top:130,bottom:130,left:150,right:150},shading:header?{fill:'17365D'}:shade?{fill:'F3F6FA'}:undefined,borders:{top:border,bottom:border,left:border,right:border},children:[paragraph(text,{alignment:right?AlignmentType.RIGHT:AlignmentType.LEFT,spacing:{after:0},children:clean(text).split('\n').flatMap((line,i)=>[...(i?[new TextRun({break:1})]:[]),run(line,{bold:header,color:header?'FFFFFF':'000000'})])})]});
 const children=[];
 if(m.isDraft)children.push(paragraph(m.t.warning,{children:[run(m.t.warning,{bold:true,color:'A32638'})]}));
 children.push(paragraph(m.title,{heading:HeadingLevel.TITLE,spacing:{after:220}}));
 children.push(...m.metadata.map(x=>labeled(x)));
 children.push(paragraph(m.t.from,{heading:HeadingLevel.HEADING_2}),...m.from.map(x=>paragraph(x,{spacing:{after:60}})));
 children.push(paragraph(m.t.to,{heading:HeadingLevel.HEADING_2}),...m.to.map(x=>paragraph(x,{spacing:{after:60}})));
 children.push(paragraph(''));
 children.push(new Table({width:{size:9800,type:WidthType.DXA},columnWidths:[7200,2600],layout:'fixed',rows:[new TableRow({tableHeader:true,children:[cell(m.t.description,7200,true),cell(m.t.amount+' ('+m.currency+')',2600,true,true)]}),...m.lines.map((l,n)=>new TableRow({cantSplit:true,children:[cell(l.description+(l.source?'\n'+l.source:''),7200,false,false,n%2===1),cell(l.amount,2600,false,true,n%2===1)]}))]}));
 children.push(paragraph(''),...m.totals.map(x=>labeled(x,true)),...m.notes.map(x=>paragraph(x)));
 children.push(paragraph(''),...m.bank.map(x=>labeled(x)));
 const doc=new Document({creator:'Retodo Ops',title:m.title,description:m.t.invoice,styles:{default:{document:{run:{font:'Arial',size:21,color:'000000',language:{value:m.lang==='bg'?'bg-BG':'en-GB'}},paragraph:{spacing:{after:100,line:260}}}},paragraphStyles:[{id:'Title',name:'Title',basedOn:'Normal',next:'Normal',run:{size:42,bold:true,color:'000000'},paragraph:{spacing:{after:220}}},{id:'Heading2',name:'Heading 2',basedOn:'Normal',next:'Normal',run:{size:24,bold:true,color:'000000'},paragraph:{spacing:{before:180,after:100},keepNext:true}}]},sections:[{properties:{page:{size:{width:11906,height:16838},margin:{top:1000,bottom:1000,left:1053,right:1053}}},children}]});
 return Packer.toBlob(doc);
}
const api={model,filename,html,word};if(typeof module!=='undefined')module.exports=api;else root.InvoiceDocument=api;
})(typeof window==='undefined'?globalThis:window);

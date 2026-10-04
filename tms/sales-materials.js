/* Local exports: prospect data stays in the browser. PptxGenJS loads on demand. */
(function(root){
 'use strict';
 const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 const filename=title=>(String(title||'Retodo-Sales').replace(/[^a-z0-9-]+/gi,'-').replace(/^-|-$/g,'').slice(0,90)||'Retodo-Sales');
 function sections(material){
  const result=[];let title=material.title||'Retodo Ops',lines=[];
  const flush=()=>{if(lines.length)result.push({title,lines});lines=[];};
  for(const raw of String(material.content||'').split(/\r?\n/)){
   const line=raw.trim();if(!line)continue;
   if(/^#{1,3}\s+/.test(line)){flush();title=line.replace(/^#{1,3}\s+/,'');}
   else lines.push(line.replace(/^[-*]\s+/,''));
  }
  flush();
  const pages=[];
  for(const section of result){
   let chunk=[],length=0,part=0;
   const emit=()=>{if(chunk.length)pages.push({title:section.title+(part++?' (continued)':''),lines:chunk});chunk=[];length=0;};
   for(const line of section.lines){
    // Split on words; never silently trim user content to fit a slide.
    const pieces=[];let piece='';
    for(const word of line.split(/\s+/)){if(piece.length+word.length>220&&piece){pieces.push(piece);piece='';}piece+=(piece?' ':'')+word;}
    if(piece)pieces.push(piece);
    for(const text of pieces){if(length+text.length>600||chunk.length>=5)emit();chunk.push(text);length+=text.length;}
   }
   emit();
  }
  return pages;
 }
 function download(blob,name){const url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=name;document.body.append(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),30000);}
 function text(material){download(new Blob([material.title+'\n\n'+material.content],{type:'text/markdown;charset=utf-8'}),filename(material.title)+'.md');}
 function preview(material){return sections(material).map((s,i)=>`<section class="sales-material-preview"><span class="sales-small">SLIDE ${i+2}</span><h3>${esc(s.title)}</h3>${s.lines.map(l=>`<p>${esc(l)}</p>`).join('')}</section>`).join('')||'<p class="sales-small">Add content to preview the slides.</p>';}
 let lib;
 function load(){if(root.PptxGenJS)return Promise.resolve();if(!lib)lib=new Promise((resolve,reject)=>{const script=document.createElement('script');script.src='vendor/pptxgenjs-4.0.1.bundle.js';script.onload=resolve;script.onerror=()=>{lib=null;reject(new Error('PowerPoint exporter could not load. Refresh and retry'));};document.head.append(script);});return lib;}
 async function powerpoint(material){
  if(!material)throw new Error('Material not found');await load();
  const deck=new root.PptxGenJS();deck.layout='LAYOUT_WIDE';deck.author='Eli Stoyanova';deck.company='Retodo Ops';deck.subject='Sales presentation';deck.title=material.title;deck.lang='en-GB';
  deck.theme={headFontFace:'Aptos Display',bodyFontFace:'Aptos',lang:'en-GB'};
  const pages=sections(material),all=[{title:material.title,cover:true},...pages];
  all.forEach((page,i)=>{
   const slide=deck.addSlide();slide.background={color:page.cover?'F4EFFA':'FFFFFF'};
   slide.addImage({path:new URL('Logo-440x140.png',location.href).href,x:0.72,y:0.4,w:2.2,h:0.7});
   slide.addText(page.title,{x:0.8,y:page.cover?2.05:1.45,w:11.65,h:page.cover?2.5:1.4,fontSize:page.cover?42:32,bold:true,color:'482B66',breakLine:false,margin:0,fit:'resize',valign:'mid'});
   if(page.cover)slide.addText('Eli Stoyanova\neli.s@retodo-ops.com',{x:0.85,y:5.55,w:10,h:0.8,fontSize:18,color:'725A84',margin:0});
   else{
    const runs=page.lines.map((text,index)=>({text,options:{breakLine:index<page.lines.length-1,paraSpaceAfterPt:18}}));
    slide.addText(runs,{x:0.85,y:3.05,w:11.5,h:3.45,fontSize:22,color:'4D4357',margin:0,valign:'top',fit:'resize',paraSpaceAfterPt:18});
   }
   slide.addText(`Retodo Ops    ${i+1} / ${all.length}`,{x:0.85,y:7.05,w:11.6,h:0.2,fontSize:10,color:'8A7B98',margin:0});
  });
  await deck.writeFile({fileName:filename(material.title)+'.pptx'});
 }
 function print(material){
  const win=window.open('','_blank');if(!win)throw new Error('Allow this site to open the print preview');win.opener=null;
  const pages=[{title:material.title,lines:['Eli Stoyanova','eli.s@retodo-ops.com']},...sections(material)];
  win.document.write(`<!doctype html><html><head><meta charset="utf-8"><title>${esc(material.title)}</title><style>@page{size:A4 landscape;margin:0}*{box-sizing:border-box}body{font-family:Arial,sans-serif;margin:0;color:#4d4357;background:#eee}.slide{width:297mm;min-height:210mm;padding:20mm 23mm;page-break-after:always;background:white}.slide:last-child{page-break-after:auto}h1{font-size:30pt;color:#482b66;line-height:1.2;margin:14mm 0 12mm}p{font-size:18pt;line-height:1.5;margin:6mm 0}small{font-size:11pt;color:#8a7b98}.print{margin:20px;padding:12px 20px}@media print{.print{display:none}body{background:white}}</style></head><body><button class="print" onclick="window.print()">Print / Save as PDF</button>${pages.map((p,i)=>`<section class="slide"><small>RETODO OPS</small><h1>${esc(p.title)}</h1>${p.lines.map(l=>`<p>${esc(l)}</p>`).join('')}<small>${i+1} / ${pages.length}</small></section>`).join('')}</body></html>`);win.document.close();
 }
 root.SalesMaterials={sections,download,text,preview,powerpoint,print};
})(typeof window!=='undefined'?window:globalThis);

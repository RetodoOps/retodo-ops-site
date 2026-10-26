/* Update 070. Vector PDF invoices, local fonts and libraries; no print dialog. */
(function(root){
'use strict';
const scripts=new Map();let fonts;
function script(src,test){
 if(test())return Promise.resolve();if(scripts.has(src))return scripts.get(src);
 const task=new Promise((resolve,reject)=>{const s=document.createElement('script');s.src=src;s.onload=()=>test()?resolve():reject(new Error('Download component did not load. Please retry.'));s.onerror=()=>{s.remove();reject(new Error('Download component could not load. Please retry.'));};document.head.append(s);}).catch(e=>{scripts.delete(src);throw e;});scripts.set(src,task);return task;
}
async function fontData(){
 if(!fonts)fonts=Promise.all(['DejaVuSans','DejaVuSans-Bold'].map(async name=>{const r=await fetch('vendor/fonts/'+name+'.ttf');if(!r.ok)throw new Error('PDF font could not load. Please retry.');const bytes=new Uint8Array(await r.arrayBuffer());let s='';for(let i=0;i<bytes.length;i+=8192)s+=String.fromCharCode(...bytes.subarray(i,i+8192));return btoa(s);})).catch(e=>{fonts=null;throw e;});return fonts;
}
async function pdf(m){
 await script('vendor/jspdf-3.0.2.umd.min.js',()=>!!root.jspdf?.jsPDF);
 const [regular,bold]=await fontData(),d=new root.jspdf.jsPDF({unit:'mm',format:'a4',compress:true,putOnlyUsedFonts:true});
 d.addFileToVFS('DejaVuSans.ttf',regular);d.addFont('DejaVuSans.ttf','Invoice','normal');
 d.addFileToVFS('DejaVuSans-Bold.ttf',bold);d.addFont('DejaVuSans-Bold.ttf','Invoice','bold');
 d.setProperties({title:m.title,author:'Retodo Ops',creator:'Retodo Ops TMS'});
 const left=16,width=178,bottom=279,lineHeight=4.6;let y=16;
 const text=v=>String(v??'').replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g,'');
 function font(weight='normal',size=9){d.setFont('Invoice',weight);d.setFontSize(size);d.setTextColor(20,20,20);}
 function lines(value,w,weight='normal',size=9){font(weight,size);return d.splitTextToSize(text(value),w);}
 function next(){d.addPage();y=16;}
 function ensure(h,repeat){if(y+h>bottom){next();if(repeat)repeat();}}
 function paragraph(value,{weight='normal',size=9,color=null}={}){
  const parts=lines(value,width,weight,size);for(const line of parts){ensure(lineHeight+2);font(weight,size);if(color)d.setTextColor(...color);d.text(line,left,y+3.5);y+=lineHeight;}y+=3;
 }
 // Splits oversized rows as well as ordinary tables; every page repeats item headers.
 function row(values,widths,{header=false,align=[],repeat=null,weight='normal'}={}){
  const content=values.map((v,i)=>lines(v,widths[i]-4,header?'bold':weight));const count=Math.max(1,...content.map(l=>l.length));let start=0;
  while(start<count){ensure(9,repeat);const capacity=Math.max(1,Math.floor((bottom-y-4)/lineHeight));const take=Math.min(count-start,capacity),height=Math.max(9,take*lineHeight+4);let x=left;
   for(let i=0;i<values.length;i++){
    d.setDrawColor(155,155,155);d.setLineWidth(.2);d.setFillColor(header?234:255,header?234:255,header?234:255);d.rect(x,y,widths[i],height,'FD');font(header?'bold':weight,9);
    const part=content[i].slice(start,start+take);if(part.length)d.text(part,align[i]==='right'?x+widths[i]-2:x+2,y+5,{align:align[i]||'left',lineHeightFactor:lineHeight/(9*25.4/72)});x+=widths[i];
   }
   y+=height;start+=take;if(start<count){next();if(repeat)repeat();}
  }
 }
 if(m.isDraft)paragraph(m.t.warning,{weight:'bold',color:[156,37,55]});
 if(m.isCancelled)paragraph(m.t.cancelled,{weight:'bold',color:[156,37,55]});
 row([m.t.to,m.t.from],[89,89],{header:true});row([m.to.join('\n'),m.from.join('\n')],[89,89]);
 const titleHeight=18+m.metadata.length*5;ensure(titleHeight);d.setDrawColor(155,155,155);d.rect(left,y,width,titleHeight);
 font('bold',21);d.text(m.copyLabel,left+4,y+16);font('bold',17);d.text(m.t.invoice,left+width-4,y+10,{align:'right'});
 font('normal',9);m.metadata.forEach(([k,v],i)=>d.text(k+': '+v,left+width-4,y+19+i*5,{align:'right'}));y+=titleHeight+7;
 const widths=[9,88,23,29,29],align=['left','left','right','right','right'];
 const itemHeader=()=>row(['№',m.t.description,m.t.quantity,m.t.unitPrice,m.t.amount],widths,{header:true,align});
 ensure(20);itemHeader();
 m.lines.forEach((l,i)=>row([String(i+1),l.description+(l.source?'\n'+l.source:''),l.quantity,l.unitPrice,l.amount],widths,{align,repeat:itemHeader}));y+=7;
 for(const note of m.notes)paragraph(note);
 ensure(55);row([m.t.payment+': '+m.paymentMethod,m.t.total],[95,83],{header:true});
 const bank=m.bank.map(([k,v])=>k+': '+v),totals=m.totals.map(([k,v])=>k+': '+v);
 for(let i=0;i<Math.max(bank.length,totals.length);i++)row([bank[i]||'',totals[i]||''],[95,83],{align:['left','right'],weight:i===3?'bold':'normal'});
 y+=8;row([m.t.recipient+': '+(m.recipient||'________________'),m.t.prepared+': '+(m.preparedBy||'________________')],[89,89]);
 return d.output('blob');
}
function download(blob,filename){const url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=filename;document.body.append(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),60000);}
async function zip(files){await script('vendor/jszip-3.10.1.min.js',()=>!!root.JSZip);const z=new root.JSZip();for(const f of files)z.file(f.name,await f.blob.arrayBuffer());return z.generateAsync({type:'blob',compression:'DEFLATE',compressionOptions:{level:6}});}
root.InvoicePdf={pdf,download,zip};
})(window);

const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const D=require(path.join(process.env.CODEX_PRIMARY_RUNTIME_NODE_MODULES,'docx'));
const exporter=require('../tms/invoice-document.js');
const out=process.env.INVOICE_TEST_OUTPUT||'/tmp/invoice065';fs.mkdirSync(out,{recursive:true});
const issuer={legal_name:'Примерен доставчик ЕООД',address:'ул. Примерна 12\nСофия 1000, България',registration_number:'TEST-123',vat_number:'BG-TEST',bank:'Примерна банка',iban:'BG00 TEST 0000 0000 0000 00',swift:'TEST-BIC',contact:'billing@example.invalid'};
const billing={legal_name:'Примерен клиент ООД',address_line_1:'бул. Примерен 45',city:'София',postal_code:'1000',country_code:'BG',registration_number:'TEST-456'};
const i={id:'fixture',invoice_number:'0000000201',status:'Issued',issue_date:'2026-10-15',due_date:'2026-11-14',payment_terms_days:30,currency:'EUR',subtotal:49.6,tax_rate:20,tax_amount:9.92,total:59.52,notes:'Благодарим за доверието.',tax_note:'Примерен текст — въведен от потребителя.',lines:[{description:'Превод и редакция на документи',amount:39.6},{description:'Допълнителна услуга & проверка <тест>',amount:10}]};
(async()=>{
 for(const lang of ['en','bg']){const m=exporter.model(i,billing,issuer,lang);assert.equal(m.lines.length,2);assert.ok(m.totals.at(-1)[1].includes(lang==='bg'?'59,52':'59.52'));const html=exporter.html(m);assert.ok(html.includes('&lt;тест&gt;'));assert.ok(!html.includes('DRAFT —'));fs.writeFileSync(path.join(out,lang+'.html'),html);const blob=await exporter.word(m,D);fs.writeFileSync(path.join(out,lang+'.docx'),Buffer.from(await blob.arrayBuffer()));}
 const m=exporter.model({...i,status:'Draft',invoice_number:null,subtotal:2574,tax_amount:514.8,total:3088.8,lines:Array.from({length:65},(_,n)=>({description:'Услуга '+(n+1)+' — Подробно описание на превод, редакция и проверка на документ с дълъг текст за пренасяне на редовете.',amount:39.6}))},billing,issuer,'bg');assert.ok(exporter.html(m).includes('ЧЕРНОВА — НЕ Е ИЗДАДЕНА ФАКТУРА'));fs.writeFileSync(path.join(out,'multipage.docx'),Buffer.from(await (await exporter.word(m,D)).arrayBuffer()));
 assert.equal(exporter.model(i,billing,issuer,'other').lang,'en');console.log('PASS English/Bulgarian models, exact decimals, escaping, native Word, draft marker and 65-row document');
})().catch(e=>{console.error(e);process.exit(1)});

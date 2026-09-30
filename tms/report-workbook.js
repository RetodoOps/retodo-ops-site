/* Production browser exporter. Vendored ExcelJS 4.4.0 (MIT); no remote scripts. */
(function(root){
 async function build(data,Excel){
  if(!Excel?.Workbook)throw new Error('Excel export library could not load. Refresh and retry.');
  const book=new Excel.Workbook();book.creator='Retodo Ops';book.created=new Date(data.generated_at);
  const jobs=data.report_type==='jobs';
  const columns=[['Project','project_number',32],['Scoop',jobs?'scoop_number':'name',36],...(jobs?[['Job','name',40],['Resource','resource',25]]:[]),['Client','client',28],['Account','account',24],['PM','pm',24],['Status','status',19],['Date','date',15],['Source language','source_language',22],['Target language','target_language',22],...(jobs?[['Service','service',20],['Quantity','quantity',14],['Unit','unit',18],['Cost basis','cost_basis',19],['Supplier PO','po_number',32]]:[['Client value (EUR)','client_value',21]]),['Known cost (EUR)','eur_cost',21],...(jobs?[]:[['Profit (EUR)','profit',19],['Margin','margin_ratio',14],['Provisional profit (EUR)','provisional_profit',26]]),['Original currency','native_currency',19],...(jobs?[['Original cost','native_cost',19]]:[['Original client value','native_client_value',23]]),['Data quality','quality',55]];
  const details=book.addWorksheet('Details');details.columns=columns.map(([header,key,width])=>({header,key,width}));
  for(const row of data.rows){const quality=[];for(const d of row.cost_details||[])if(d.native_cost==null)quality.push(`${d.name}: no saved rate / PO`);if(row.currency_warning_count)quality.push('Exchange rate missing');if(row.po_warning_count)quality.push('PO snapshot conflict');if(row.estimate_count)quality.push('Includes saved estimates');if(row.unallocated_job_count)quality.push('Project has Jobs without a Scoop');if(!jobs&&row.job_count===0)quality.push('No Jobs');
   details.addRow({...row,eur_cost:row.costs?.EUR??null,margin_ratio:row.margin==null?null:row.margin/100,quality:quality.join('; ')});
  }
  const summary=book.addWorksheet('Summary');summary.columns=[{header:'Currency',key:'currency',width:15},...(!jobs?[{header:'Client value',key:'client_value',width:22}]:[]),{header:'Known supplier cost',key:'supplier_cost',width:24},...(!jobs?[{header:'Profit',key:'profit',width:22},{header:'Margin',key:'margin_ratio',width:17}]:[]),{header:'Incomplete rows',key:'incomplete_rows',width:21},{header:'Estimated costs',key:'estimate_count',width:21}];
  for(const r of data.summary_by_currency)summary.addRow({...r,incomplete_rows:jobs?data.warning_rows:r.incomplete_rows,margin_ratio:r.margin==null?null:r.margin/100});
  if(data.groups?.length){const sheet=book.addWorksheet('Groups');sheet.columns=[{header:'Group',key:'label',width:35},{header:'Currency',key:'currency',width:15},{header:'Rows',key:'row_count',width:12},...(!jobs?[{header:'Client value',key:'client_value',width:22}]:[]),{header:'Known supplier cost',key:'supplier_cost',width:24},...(!jobs?[{header:'Profit',key:'profit',width:22},{header:'Margin',key:'margin_ratio',width:17}]:[]),{header:'Need attention',key:'issue_count',width:19}];for(const r of data.groups)sheet.addRow({...r,margin_ratio:r.margin==null?null:r.margin/100});}
  const info=book.addWorksheet('Report information');info.columns=[{header:'Setting',key:'label',width:30},{header:'Value',key:'value',width:95}];
  const metadata=[['Report',jobs?'Jobs':'Scoops'],['Generated',data.generated_at],['Date basis',data.date_basis],['Matching rows',data.total_count],['Reporting currency','EUR'],['Exchange-rate source',data.fx_source||'ECB'],['Exchange-rate date',data.fx_date||'No non-EUR rates available'],['Calculation','Original amount divided by currency units per EUR. Known cost excludes missing costs. Provisional profit excludes missing costs; it is not final margin.']];
  for(const [k,v] of Object.entries(data.filters||{}))metadata.push([k.replaceAll('_',' '),Array.isArray(v)?v.join(', '):String(v)]);
  for(const [k,v] of Object.entries(data.fx_rates||{}))metadata.push(['1 EUR in '+k,v]);
  for(const [label,value] of metadata)info.addRow({label,value});
  for(const sheet of book.worksheets){sheet.views=[{state:'frozen',ySplit:1}];sheet.autoFilter={from:{row:1,column:1},to:{row:sheet.rowCount,column:sheet.columnCount}};sheet.getRow(1).height=32;
   sheet.getRow(1).eachCell(c=>{c.font={bold:true,color:{argb:'FFFFFFFF'},size:11};c.fill={type:'pattern',pattern:'solid',fgColor:{argb:'FF4C287F'}};c.alignment={vertical:'middle',wrapText:true};});
   sheet.eachRow((r,n)=>{if(n===1)return;r.height=34;r.eachCell(c=>{c.font={name:'Calibri',size:11};c.alignment={vertical:'top',wrapText:true};if(n%2===0)c.fill={type:'pattern',pattern:'solid',fgColor:{argb:'FFF5F2FA'}};if(typeof c.value==='number')c.numFmt=['row_count','incomplete_rows','estimate_count','issue_count'].includes(sheet.getColumn(c.col).key)?'0':sheet.getColumn(c.col).key==='margin_ratio'?'0.00%':'#,##0.00;[Red](#,##0.00)';});});
  }
  info.getRow(9).height=64;
  return book.xlsx.writeBuffer();
 }
 if(typeof module!=='undefined')module.exports={build};else root.ReportWorkbook={build};
})(typeof window==='undefined'?globalThis:window);

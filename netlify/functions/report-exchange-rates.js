'use strict';
const {verifyUser,request,serviceRpc,requireSameOrigin,jsonResponse,publicError}=require('./_shared/supabase');
let cached=null;
function parseRates(xml){
 const date=xml.match(/time=['"](\d{4}-\d{2}-\d{2})['"]/)?.[1];
 const rates={EUR:1};
 for(const m of xml.matchAll(/currency=['"]([A-Z]{3})['"]\s+rate=['"]([0-9.]+)['"]/g)){const n=Number(m[2]);if(!Number.isFinite(n)||n<=0)throw new Error('Invalid ECB rate');rates[m[1]]=n;}
 if(!date||Object.keys(rates).length<10)throw new Error('ECB response did not contain a complete rate snapshot');
 const age=Date.now()-Date.parse(date+'T00:00:00Z');if(age<0||age>7*86400000)throw new Error('ECB snapshot is outside the allowed date range');
 return {date,rates,source:'ECB'};
}
exports.handler=async event=>{
 try{
  if(event.httpMethod!=='POST')return jsonResponse(405,{error:'POST required'});
  const {headers}=requireSameOrigin(event);const bearer=headers.authorization;await verifyUser(bearer);
  const role=await request('/rest/v1/rpc/current_app_role',{method:'POST',body:{},bearer});
  const enabled=await request('/rest/v1/rpc/current_user_access_enabled',{method:'POST',body:{},bearer});
  if(!enabled||!['admin','pm','qa','client_relations'].includes(role))return jsonResponse(403,{error:'Company access required'});
  if(!cached||Date.now()-cached.loaded>3600000){
   const response=await fetch('https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml',{signal:AbortSignal.timeout(10000)});
   if(!response.ok)throw new Error('ECB rates are temporarily unavailable');
   const snapshot=parseRates(await response.text());
   await serviceRpc('store_report_fx_061',{p_date:snapshot.date,p_rates:snapshot.rates});
   cached={...snapshot,loaded:Date.now()};
  }
  return jsonResponse(200,{date:cached.date,source:cached.source});
 }catch(error){return jsonResponse(error.status||503,{error:publicError(error,'Exchange rates could not be refreshed. The report will use its latest saved snapshot.')});}
};
exports.parseRates=parseRates;

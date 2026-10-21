// ARCHIVE ONLY — source copied from live Supabase function redeem-reward v1 on 2026-10-22.
// Do not deploy this legacy route. It has not been retired because caller traffic has not been conclusively ruled out.
// Canonical replacement: supabase/functions/rewardloop-api/index.ts.
// Live source SHA-256 (Supabase metadata): 7d93c3b8dd42234e5e667534116d57b8344687322b18ccd886e3aff2976b3c35

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
const corsHeaders={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
const respond=(status:number,body:Record<string,unknown>)=>new Response(JSON.stringify(body),{status,headers:{...corsHeaders,"Content-Type":"application/json; charset=utf-8"}});
Deno.serve(async(req:Request)=>{
 if(req.method==="OPTIONS")return new Response("ok",{headers:corsHeaders});
 if(req.method!=="POST")return respond(405,{ok:false,error:"method_not_allowed"});
 const authorization=req.headers.get("Authorization");
 if(!authorization?.startsWith("Bearer "))return respond(401,{ok:false,error:"unauthorized"});
 const url=Deno.env.get("SUPABASE_URL"),anonKey=Deno.env.get("SUPABASE_ANON_KEY"),serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
 if(!url||!anonKey||!serviceKey)return respond(503,{ok:false,error:"service_not_configured"});
 const auth=createClient(url,anonKey,{global:{headers:{Authorization:authorization}},auth:{persistSession:false,autoRefreshToken:false}});
 const {data:{user},error:authError}=await auth.auth.getUser();
 if(authError||!user)return respond(401,{ok:false,error:"unauthorized"});
 let body:Record<string,unknown>;try{body=await req.json()}catch{return respond(400,{ok:false,error:"invalid_json"})}
 const rewardId=typeof body.reward_id==="string"?body.reward_id:"";
 const requestKey=typeof body.request_key==="string"?body.request_key:"";
 if(!/^[0-9a-f-]{36}$/i.test(rewardId)||requestKey.length<8||requestKey.length>160||!/^[A-Za-z0-9:_-]+$/.test(requestKey))return respond(400,{ok:false,error:"invalid_request"});
 const admin=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data,error}=await admin.rpc("rewardloop_redeem_internal",{p_actor_user_id:user.id,p_reward_id:rewardId,p_request_key:requestKey});
 if(error){console.error("rewardloop_redeem_failed",{code:error.code});return respond(500,{ok:false,error:"redemption_processing_failed"})}
 const result=data as Record<string,unknown>;
 const status=result.ok===true?200:result.error==="partner_not_verified"?403:result.error==="insufficient_points"?409:result.error==="reward_unavailable"||result.error==="out_of_stock"?409:400;
 return respond(status,result);
});
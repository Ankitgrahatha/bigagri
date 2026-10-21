// ARCHIVE ONLY — source copied from live Supabase function claim-qr v1 on 2026-10-22.
// Do not deploy this legacy route. It has not been retired because caller traffic has not been conclusively ruled out.
// Canonical replacement: supabase/functions/rewardloop-api/index.ts.
// Live source SHA-256 (Supabase metadata): c64b053cb5ff327b08f75f089a94130a55257c991877623e3f20ec2d42eaff45

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
const corsHeaders={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
const json=(status:number,body:Record<string,unknown>)=>new Response(JSON.stringify(body),{status,headers:{...corsHeaders,"Content-Type":"application/json; charset=utf-8"}});
Deno.serve(async(req:Request)=>{
 if(req.method==="OPTIONS") return new Response("ok",{headers:corsHeaders});
 if(req.method!=="POST") return json(405,{ok:false,error:"method_not_allowed"});
 const authorization=req.headers.get("Authorization");
 if(!authorization?.startsWith("Bearer ")) return json(401,{ok:false,error:"unauthorized"});
 const url=Deno.env.get("SUPABASE_URL"),anonKey=Deno.env.get("SUPABASE_ANON_KEY"),serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
 if(!url||!anonKey||!serviceKey) return json(503,{ok:false,error:"service_not_configured"});
 const authClient=createClient(url,anonKey,{global:{headers:{Authorization:authorization}},auth:{persistSession:false,autoRefreshToken:false}});
 const {data:{user},error:authError}=await authClient.auth.getUser();
 if(authError||!user) return json(401,{ok:false,error:"unauthorized"});
 let body:{token?:unknown;request_id?:unknown;app_version?:unknown;device_ref_hash?:unknown};
 try{body=await req.json()}catch{return json(400,{ok:false,error:"invalid_json"})}
 const token=typeof body.token==="string"?body.token.trim():"",requestId=typeof body.request_id==="string"?body.request_id:"";
 if(token.length<16||token.length>512||!/^[0-9a-f-]{36}$/i.test(requestId)) return json(400,{ok:false,error:"invalid_request"});
 const appVersion=typeof body.app_version==="string"?body.app_version.slice(0,40):null;
 const deviceRefHash=typeof body.device_ref_hash==="string"&&/^[a-f0-9]{64}$/i.test(body.device_ref_hash)?body.device_ref_hash:null;
 const admin=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data,error}=await admin.rpc("rewardloop_claim_qr_internal",{p_actor_user_id:user.id,p_token:token,p_request_id:requestId,p_app_version:appVersion,p_device_ref_hash:deviceRefHash});
 if(error){console.error("rewardloop_claim_failed",{code:error.code,message:error.message});return json(500,{ok:false,error:"claim_processing_failed"})}
 return json(200,data as Record<string,unknown>);
});
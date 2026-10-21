// ARCHIVE ONLY — source copied from live Supabase function verify-partner v1 on 2026-10-22.
// Do not deploy this legacy route. It has not been retired because caller traffic has not been conclusively ruled out.
// Canonical replacement: supabase/functions/rewardloop-api/index.ts.
// Live source SHA-256 (Supabase metadata): fd0745ba9a872c298f9ebfc4c371ad9e972270aeeef6384c59b4da68c7b95871

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
const corsHeaders={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
const respond=(status:number,body:Record<string,unknown>)=>new Response(JSON.stringify(body),{status,headers:{...corsHeaders,"Content-Type":"application/json; charset=utf-8"}});
Deno.serve(async(req:Request)=>{
 if(req.method==="OPTIONS")return new Response("ok",{headers:corsHeaders});if(req.method!=="POST")return respond(405,{ok:false,error:"method_not_allowed"});
 const authorization=req.headers.get("Authorization");if(!authorization?.startsWith("Bearer "))return respond(401,{ok:false,error:"unauthorized"});
 const url=Deno.env.get("SUPABASE_URL"),anonKey=Deno.env.get("SUPABASE_ANON_KEY"),serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");if(!url||!anonKey||!serviceKey)return respond(503,{ok:false,error:"service_not_configured"});
 const auth=createClient(url,anonKey,{global:{headers:{Authorization:authorization}},auth:{persistSession:false,autoRefreshToken:false}});const {data:{user},error:authError}=await auth.auth.getUser();if(authError||!user)return respond(401,{ok:false,error:"unauthorized"});
 let body:Record<string,unknown>;try{body=await req.json()}catch{return respond(400,{ok:false,error:"invalid_json"})}
 const tenantId=typeof body.tenant_id==="string"?body.tenant_id:"",partnerId=typeof body.partner_id==="string"?body.partner_id:"",status=typeof body.status==="string"?body.status:"",reason=typeof body.reason==="string"?body.reason.trim().slice(0,500):"",uuid=/^[0-9a-f-]{36}$/i;
 if(!uuid.test(tenantId)||!uuid.test(partnerId)||!["verified","rejected","suspended"].includes(status))return respond(400,{ok:false,error:"invalid_request"});
 if(["rejected","suspended"].includes(status)&&reason.length<5)return respond(400,{ok:false,error:"reason_required"});
 const admin=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});const {data,error}=await admin.rpc("rewardloop_verify_partner_internal",{p_actor_user_id:user.id,p_tenant_id:tenantId,p_partner_id:partnerId,p_new_status:status,p_reason:reason||null});
 if(error){console.error("rewardloop_partner_verification_failed",{code:error.code});return respond(500,{ok:false,error:"verification_failed"})}
 const result=data as Record<string,unknown>;return respond(result.ok===true?200:result.error==="forbidden"?403:result.error==="partner_not_found"?404:400,result);
});
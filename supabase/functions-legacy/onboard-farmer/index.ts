// ARCHIVE ONLY — source copied from live Supabase function onboard-farmer v2 on 2026-10-22.
// Do not deploy this legacy route. It has not been retired because caller traffic has not been conclusively ruled out.
// Canonical replacement: supabase/functions/rewardloop-api/index.ts.
// Live source SHA-256 (Supabase metadata): 04af8dd6ebd04c4768b5e0ec64f29f2d2622cb1931066ceb6fabaeab563281dd

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
const corsHeaders={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
const respond=(status:number,body:Record<string,unknown>)=>new Response(JSON.stringify(body),{status,headers:{...corsHeaders,"Content-Type":"application/json; charset=utf-8"}});
Deno.serve(async(req:Request)=>{
 if(req.method==="OPTIONS")return new Response("ok",{headers:corsHeaders});
 if(req.method!=="POST")return respond(405,{ok:false,error:"method_not_allowed"});
 const authorization=req.headers.get("Authorization");if(!authorization?.startsWith("Bearer "))return respond(401,{ok:false,error:"unauthorized"});
 const url=Deno.env.get("SUPABASE_URL"),anonKey=Deno.env.get("SUPABASE_ANON_KEY"),serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");if(!url||!anonKey||!serviceKey)return respond(503,{ok:false,error:"service_not_configured"});
 const auth=createClient(url,anonKey,{global:{headers:{Authorization:authorization}},auth:{persistSession:false,autoRefreshToken:false}});
 const {data:{user},error:authError}=await auth.auth.getUser();if(authError||!user)return respond(401,{ok:false,error:"unauthorized"});
 let body:Record<string,unknown>;try{body=await req.json()}catch{return respond(400,{ok:false,error:"invalid_json"})}
 const name=typeof body.display_name==="string"?body.display_name.trim().slice(0,160):"",locale=typeof body.preferred_locale==="string"?body.preferred_locale:"hi-IN";
 if(!["hi-IN","en-IN","bn-IN","mr-IN","pa-IN","gu-IN","ta-IN","te-IN","kn-IN","ml-IN","or-IN","as-IN"].includes(locale))return respond(400,{ok:false,error:"invalid_locale"});
 const admin=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:tenant,error:tenantErr}=await admin.from("tenants").select("id").eq("slug","growta-rewardloop").eq("status","active").single();if(tenantErr||!tenant)return respond(503,{ok:false,error:"tenant_not_configured"});
 const {data:existing,error:readErr}=await admin.from("partners").select("id,display_name,role,verification_status,preferred_locale,created_at").eq("tenant_id",tenant.id).eq("user_id",user.id).maybeSingle();
 if(readErr)return respond(500,{ok:false,error:"profile_lookup_failed"});if(existing)return respond(200,{ok:true,profile:existing,existing:true});
 if(name.length<1)return respond(400,{ok:false,error:"display_name_required"});
 const {data:profile,error}=await admin.from("partners").insert({tenant_id:tenant.id,user_id:user.id,role:"farmer",display_name:name,phone_e164:user.phone??null,preferred_locale:locale,verification_status:"unverified"}).select("id,display_name,role,verification_status,preferred_locale,created_at").single();
 if(error){if(error.code==="23505")return respond(409,{ok:false,error:"profile_already_exists"});console.error("rewardloop_onboarding_failed",{code:error.code});return respond(500,{ok:false,error:"profile_creation_failed"})}
 return respond(201,{ok:true,profile,verification_required:true});
});
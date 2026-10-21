import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.0";
const URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const PUBLIC = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ?? "";
const TENANT = "growta-rewardloop";
const headers = {"Access-Control-Allow-Origin":"https://bigagri.vercel.app","Access-Control-Allow-Headers":"authorization, apikey, content-type, x-client-info","Access-Control-Allow-Methods":"POST, OPTIONS","Content-Type":"application/json; charset=utf-8","Cache-Control":"no-store"};
const respond=(status:number,body:Record<string,unknown>)=>new Response(JSON.stringify(body),{status,headers});
Deno.serve(async(req:Request)=>{
 if(req.method==="OPTIONS") return new Response("ok",{headers});
 if(req.method!=="POST") return respond(405,{ok:false,error:"method_not_allowed"});
 try{
  const auth=req.headers.get("Authorization"); if(!auth?.startsWith("Bearer ")) return respond(401,{ok:false,error:"authentication_required"});
  const userClient=createClient(URL,PUBLIC,{auth:{persistSession:false,autoRefreshToken:false},global:{headers:{Authorization:auth}}});
  const {data:{user},error:userErr}=await userClient.auth.getUser(); if(userErr||!user) return respond(401,{ok:false,error:"invalid_session"});
  const admin=createClient(URL,SERVICE,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:tenant,error:te}=await admin.from("tenants").select("id,status").eq("slug",TENANT).maybeSingle();
  if(te||!tenant||tenant.status!=="active") return respond(503,{ok:false,error:"tenant_unavailable"});
  const {data:member,error:me}=await admin.from("tenant_memberships").select("role").eq("tenant_id",tenant.id).eq("user_id",user.id).eq("status","active").in("role",["brand_admin","super_admin"]).maybeSingle();
  if(me) return respond(500,{ok:false,error:"admin_authorization_check_failed"});
  if(!member) return respond(403,{ok:false,error:"admin_access_required"});
  const body=await req.json().catch(()=>({})); const action=String(body.action||"");
  if(action==="admin_settings_get"){
   const {data,error}=await admin.from("rewardloop_admin_settings").select("email_provider,sender_email,sender_name,smtp_host,smtp_port,smtp_username,site_url,redirect_urls,signup_enabled,email_confirmation_required,confirmation_subject,confirmation_body,recovery_subject,recovery_body,smtp_configured,updated_at").eq("tenant_id",tenant.id).maybeSingle();
   if(error) return respond(500,{ok:false,error:"settings_load_failed"});
   return respond(200,{ok:true,settings:data||{}});
  }
  if(action==="admin_settings_save"){
   const s=body.settings||{}; const allowed:Record<string,unknown>={};
   if(s.email_provider!==undefined){if(!["gmail","resend","custom"].includes(s.email_provider))return respond(400,{ok:false,error:"invalid_email_provider"});allowed.email_provider=s.email_provider;}
   for(const [input,column,max] of [["sender_email","sender_email",254],["sender_name","sender_name",120],["smtp_host","smtp_host",255],["smtp_username","smtp_username",254],["site_url","site_url",500],["confirmation_subject","confirmation_subject",180],["confirmation_body","confirmation_body",8000],["recovery_subject","recovery_subject",180],["recovery_body","recovery_body",8000]] as string[][]){
    if(s[input]!==undefined){if(typeof s[input]!=="string"||s[input].length>Number(max))return respond(400,{ok:false,error:"invalid_"+input});allowed[column]=s[input].trim();}
   }
   if(s.smtp_port!==undefined){const p=Number(s.smtp_port);if(!Number.isInteger(p)||p<1||p>65535)return respond(400,{ok:false,error:"invalid_smtp_port"});allowed.smtp_port=p;}
   if(s.redirect_urls!==undefined){if(!Array.isArray(s.redirect_urls)||s.redirect_urls.length>30||s.redirect_urls.some((x:unknown)=>typeof x!=="string"||x.length>500||!/^https:\/\//.test(x)))return respond(400,{ok:false,error:"invalid_redirect_urls"});allowed.redirect_urls=s.redirect_urls;}
   for(const key of ["signup_enabled","email_confirmation_required"])if(s[key]!==undefined){if(typeof s[key]!=="boolean")return respond(400,{ok:false,error:"invalid_"+key});allowed[key]=s[key];}
   // Never persist SMTP passwords in application tables. Live Auth SMTP needs a privileged Management API integration.
   const passwordProvided=typeof s.smtp_password==="string"&&s.smtp_password.length>0;
   if(passwordProvided&&!Deno.env.get("SUPABASE_ACCESS_TOKEN"))return respond(409,{ok:false,error:"smtp_management_integration_not_configured",message:"Non-secret preferences are saved separately; live SMTP changes require a server-side Supabase Management API token."});
   if(passwordProvided) return respond(409,{ok:false,error:"smtp_management_integration_not_configured",message:"The Management API integration must be explicitly installed before applying SMTP credentials. Password was not stored."});
   allowed.updated_by=user.id;allowed.updated_at=new Date().toISOString();
   const {error}=await admin.from("rewardloop_admin_settings").upsert({tenant_id:tenant.id,...allowed},{onConflict:"tenant_id"});
   if(error)return respond(500,{ok:false,error:"settings_save_failed"});
   return respond(200,{ok:true,message:"Settings preferences saved. Live Supabase Auth configuration remains unchanged until the privileged Management API integration is installed."});
  }
  return respond(400,{ok:false,error:"unknown_action"});
 }catch{return respond(500,{ok:false,error:"unexpected_server_error"});}
});
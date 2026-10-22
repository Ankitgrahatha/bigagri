import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.0";
const supabase = createClient("https://guhhuqxrobhuumwrypnc.supabase.co","sb_publishable_6dr2KACqmGBM2AWZS6NTDw_1Kf3e8ru",{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}});
const $ = id => document.getElementById(id);
const status = (message, bad=false) => { $("status").textContent=message; $("status").style.background=bad?"#fff0ed":"#f2f5f2"; };
let session=null;
async function api(action, extra={}) {
  const {data,error}=await supabase.functions.invoke("rewardloop-admin-settings",{body:{action,...extra}});
  if(error) throw error;
  if(!data?.ok) throw new Error(data?.error||"Request failed");
  return data;
}
async function boot(){
  $("year").textContent=new Date().getFullYear();
  const {data}=await supabase.auth.getSession(); session=data.session;
  if(!session){status("Please sign in to the customer app first, then open this admin page. Only authorized administrators can continue.",true); return;}
  try{
    const result=await api("admin_settings_get");
    $("console").hidden=false;
    const s=result.settings;
    $("provider").value=s.email_provider||"gmail"; $("sender").value=s.sender_email||""; $("senderName").value=s.sender_name||"Growta RewardLoop";
    $("host").value=s.smtp_host||""; $("port").value=s.smtp_port||587; $("username").value=s.smtp_username||"";
    $("siteUrl").value=s.site_url||"https://bigagri.vercel.app"; $("redirects").value=(s.redirect_urls||[]).join("\n");
    $("signupEnabled").checked=s.signup_enabled!==false; $("emailConfirm").checked=s.email_confirmation_required!==false;
    $("confirmSubject").value=s.confirmation_subject||$("confirmSubject").value; $("confirmBody").value=s.confirmation_body||$("confirmBody").value;
    $("recoverySubject").value=s.recovery_subject||$("recoverySubject").value; $("recoveryBody").value=s.recovery_body||$("recoveryBody").value;
    $("configSummary").textContent="Preferences loaded. SMTP live-configuration status: "+(s.smtp_configured?"configured":"not connected to Supabase Auth yet")+". Updated: "+(s.updated_at||"not available")+".";
    status("Admin access verified. These are saved preferences only; live Supabase Auth SMTP and Auth settings are not changed by this page.");
  }catch(e){status("Admin console unavailable: "+e.message+". Ensure your account has an active brand_admin or super_admin membership.",true);}
}
async function save(action,payload){
  try{status("Saving preferences…");const result=await api(action,payload);status(result.message||"Preferences saved.");if(action==="admin_settings_save"&&payload.settings?.smtp_password){$("password").value="";}await boot();}
  catch(e){if(action==="admin_settings_save"&&payload.settings?.smtp_password){$("password").value="";}status("Save failed: "+e.message+(payload.settings?.smtp_password?" The SMTP credential was not saved; the live Auth integration is not installed. The password field has been cleared.":""),true);}
}
$("saveEmail").addEventListener("click",()=>save("admin_settings_save",{settings:{email_provider:$("provider").value,sender_email:$("sender").value.trim(),sender_name:$("senderName").value.trim(),smtp_host:$("host").value.trim(),smtp_port:Number($("port").value),smtp_username:$("username").value.trim(),smtp_password:$("password").value}}));
$("saveAuth").addEventListener("click",()=>save("admin_settings_save",{settings:{site_url:$("siteUrl").value.trim(),redirect_urls:$("redirects").value.split("\n").map(x=>x.trim()).filter(Boolean),signup_enabled:$("signupEnabled").checked,email_confirmation_required:$("emailConfirm").checked}}));
$("saveTemplates").addEventListener("click",()=>save("admin_settings_save",{settings:{confirmation_subject:$("confirmSubject").value.trim(),confirmation_body:$("confirmBody").value,recovery_subject:$("recoverySubject").value.trim(),recovery_body:$("recoveryBody").value}}));
$("testEmail").addEventListener("click",()=>status("Test email is not enabled until the privileged Supabase Auth configuration integration is installed.",true));
$("refresh").addEventListener("click",boot);
$("signout").addEventListener("click",async()=>{await supabase.auth.signOut();location.href="/";});
supabase.auth.onAuthStateChange((_event,s)=>{session=s;if(!s)status("Session ended. Sign in again.",true);});
boot();

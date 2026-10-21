import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.0";

// Publishable key is intended for browser use; row-level security protects data.
const SUPABASE_URL = "https://guhhuqxrobhuumwrypnc.supabase.co";
const SUPABASE_PUBLISHABLE_KEY = "sb_publishable_6dr2KACqmGBM2AWZS6NTDw_1Kf3e8ru";
const TENANT_SLUG = "growta-rewardloop";
const API_FUNCTION = "rewardloop-api";
const supabase = createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
});

const i18n = {
  hi: {
    connecting:"कनेक्ट हो रहा है",online:"सिस्टम ऑनलाइन",offline:"कनेक्शन नहीं है",secureByDesign:"सुरक्षित और पारदर्शी रिवॉर्ड सिस्टम",
    eyebrow:"किसानों के लिए रिवॉर्ड प्रोग्राम",heroTitle:"हर असली पैक से जुड़ें। हर पॉइंट का हिसाब रखें।",heroCopy:"Growta RewardLoop में अपने उत्पाद के QR कोड से पॉइंट कमाएँ और उपलब्ध इनाम देखें।",
    points:"आपके पॉइंट",pointsSub:"आपके खाते में उपलब्ध पॉइंट",welcome:"नमस्ते",catalog:"इनाम कैटलॉग",catalogSub:"पॉइंट से उपलब्ध इनाम देखें",scan:"QR स्कैन करें",scanSub:"पैक पर दिया असली रिवॉर्ड कोड दर्ज करें या कैमरे से स्कैन करें",history:"हाल की गतिविधि",historySub:"आपके पॉइंट खाते का रिकॉर्ड",profile:"आपकी प्रोफ़ाइल",signIn:"लॉग इन",signUp:"नया खाता",email:"ईमेल",password:"पासवर्ड",name:"पूरा नाम",phone:"मोबाइल नंबर (+91…)",login:"लॉग इन करें",createAccount:"खाता बनाएँ",signOut:"लॉग आउट",noAccount:"नया खाता चाहिए?",hasAccount:"पहले से खाता है?",authTitle:"आपके भरोसे का रिवॉर्ड साथी",authCopy:"अपना खाता बनाएँ, उत्पाद का QR कोड स्कैन करें और अपने पॉइंट का सुरक्षित रिकॉर्ड रखें।",benefit1:"हर पॉइंट का स्पष्ट रिकॉर्ड",benefit2:"हिंदी और अंग्रेज़ी में उपयोग",benefit3:"एक QR कोड का दोबारा दावा नहीं",language:"भाषा",hindi:"हिंदी",english:"English",profileTitle:"अपनी जानकारी पूरी करें",profileSub:"आपकी प्रोफ़ाइल रिवॉर्ड खाते से जोड़ी जाएगी।",saveProfile:"प्रोफ़ाइल सेव करें",verificationPending:"प्रोफ़ाइल सत्यापन लंबित है",verificationPendingText:"आपका खाता बन गया है। QR पॉइंट और रिडेम्पशन के लिए टीम द्वारा सत्यापन आवश्यक है।",verified:"सत्यापित खाता",unverified:"सत्यापन लंबित",demo:"डेमो",demoNotice:"ये नमूना इनाम हैं; अभी वास्तविक रिडेम्पशन उपलब्ध नहीं है।",pointsCost:"पॉइंट",notAvailable:"अभी उपलब्ध नहीं",redeem:"इनाम लें",scanStart:"कैमरा खोलें",scanStop:"कैमरा बंद करें",enterCode:"QR कोड या टोकन दर्ज करें",claim:"पॉइंट क्लेम करें",cameraUnsupported:"इस ब्राउज़र में QR कैमरा उपलब्ध नहीं है। कोड मैन्युअल दर्ज करें।",cameraPermission:"कैमरा अनुमति नहीं मिली। कोड मैन्युअल दर्ज करें।",scanSuccess:"QR कोड पढ़ लिया गया",scanDetected:"QR कोड मिल गया",scanNoCode:"अभी तक QR कोड नहीं मिला",noActivity:"अभी कोई गतिविधि नहीं",noRewards:"अभी कोई इनाम उपलब्ध नहीं",profileSaved:"प्रोफ़ाइल सेव हो गई",signedIn:"सफलतापूर्वक लॉग इन",signedOut:"आप लॉग आउट हो गए",signupSuccess:"खाता बन गया। अगर ईमेल पुष्टि माँगी जाए तो अपना ईमेल सत्यापित करें, फिर लॉग इन करें।",invalidCredentials:"ईमेल या पासवर्ड सही नहीं है।",claimAccepted:"बधाई! पॉइंट आपके खाते में जुड़ गए।",claimInvalid:"यह QR कोड मान्य नहीं है या सक्रिय नहीं है।",claimDuplicate:"यह QR कोड पहले इस्तेमाल हो चुका है।",claimIneligible:"खाता सत्यापन के बाद QR पॉइंट क्लेम कर सकेंगे।",claimCampaign:"यह कैंपेन अभी सक्रिय नहीं है।",claimError:"QR क्लेम पूरा नहीं हुआ। कृपया दोबारा जाँचें।",redeemDemo:"यह डेमो इनाम है और वास्तविक रिडेम्पशन के लिए उपलब्ध नहीं है।",insufficientPoints:"आपके पास पर्याप्त पॉइंट नहीं हैं।",redeemSuccess:"रिडेम्पशन अनुरोध दर्ज हो गया।",redemptionReserved:"लंबित",redemptionApproved:"स्वीकृत",redemptionFulfilled:"पूरा हुआ",redemptionCancelled:"रद्द · पॉइंट वापस",redemptionRejected:"अस्वीकृत · पॉइंट वापस",redeemError:"रिडेम्पशन पूरा नहीं हुआ।",networkError:"कनेक्शन में समस्या है। इंटरनेट जाँचकर फिर कोशिश करें।",loading:"लोड हो रहा है…",retry:"फिर कोशिश करें",cancel:"रद्द करें",scanTab:"QR स्कैन",homeTab:"होम",rewardsTab:"इनाम",accountTab:"खाता",pointsEarned:"पॉइंट मिले",pointsSpent:"पॉइंट इस्तेमाल",status:"स्थिति",date:"तारीख",history:"गतिविधि",emailConfirm:"आपका ईमेल सत्यापन लंबित है। ईमेल लिंक खोलकर फिर लॉग इन करें।",unknownError:"अनुरोध पूरा नहीं हो सका।",phoneInvalid:"मोबाइल नंबर अंतरराष्ट्रीय फ़ॉर्मेट में लिखें, जैसे +919876543210।",emailRateLimit:"बहुत अधिक पुष्टि ईमेल भेजने की कोशिश हुई है। कृपया कुछ समय प्रतीक्षा करें या ऐप मालिक से ईमेल सेवा कॉन्फ़िगर करवाएँ।",
    forgotPassword:"पासवर्ड भूल गए?",resendConfirmation:"पुष्टि ईमेल दोबारा भेजें",recoverTitle:"पासवर्ड रीसेट करें",recoverCopy:"अपने ईमेल पर सुरक्षित रीसेट लिंक भेजें।",resetTitle:"नया पासवर्ड बनाएँ",resetCopy:"नया पासवर्ड दर्ज करें और पुष्टि करें।",sendReset:"रीसेट लिंक भेजें",saveNewPassword:"नया पासवर्ड सेव करें",recoverySent:"अगर यह ईमेल पंजीकृत है, तो पासवर्ड रीसेट लिंक भेज दिया गया है।",recoveryHint:"ईमेल लिंक खोलने के बाद इस पेज पर वापस आएँ।",passwordMismatch:"दोनों पासवर्ड एक जैसे होने चाहिए।",passwordResetSuccess:"पासवर्ड अपडेट हो गया। नए पासवर्ड से लॉग इन करें।",confirmationResent:"अगर यह खाता मौजूद है, तो पुष्टि ईमेल भेज दिया गया है।",backToSignIn:"लॉग इन पर वापस जाएँ"
  },
  en: {
    connecting:"Connecting",online:"System online",offline:"Offline",secureByDesign:"Secure and transparent rewards",
    eyebrow:"Rewards for farmers",heroTitle:"Every genuine pack counts. Every point is tracked.",heroCopy:"Earn points by claiming eligible product QR codes and explore rewards in Growta RewardLoop.",
    points:"Your points",pointsSub:"Available points in your account",welcome:"Welcome",catalog:"Rewards catalogue",catalogSub:"Explore rewards available for points",scan:"Scan a QR code",scanSub:"Enter the genuine reward code from your pack or scan it with your camera",history:"Recent activity",historySub:"Your points account record",profile:"Your profile",signIn:"Sign in",signUp:"Create account",email:"Email",password:"Password",name:"Full name",phone:"Mobile number (+91…)",login:"Sign in",createAccount:"Create account",signOut:"Sign out",noAccount:"New here?",hasAccount:"Already have an account?",authTitle:"A rewards partner you can trust",authCopy:"Create your account, scan product QR codes and keep a secure record of your points.",benefit1:"Transparent points history",benefit2:"Hindi and English support",benefit3:"One-time QR claim protection",language:"Language",hindi:"हिंदी",english:"English",profileTitle:"Complete your profile",profileSub:"Your profile will be linked to your rewards account.",saveProfile:"Save profile",verificationPending:"Profile verification pending",verificationPendingText:"Your account is created. Team verification is required before claiming QR points or redeeming rewards.",verified:"Verified account",unverified:"Verification pending",demo:"DEMO",demoNotice:"These are sample rewards; real redemption is not enabled yet.",pointsCost:"points",notAvailable:"Not available yet",redeem:"Redeem reward",scanStart:"Open camera",scanStop:"Stop camera",enterCode:"Enter QR code or token",claim:"Claim points",cameraUnsupported:"QR camera is not supported in this browser. Enter the code manually.",cameraPermission:"Camera permission was not granted. Enter the code manually.",scanSuccess:"QR code captured",scanDetected:"QR code detected",scanNoCode:"No QR code detected yet",noActivity:"No activity yet",noRewards:"No rewards available yet",profileSaved:"Profile saved",signedIn:"Signed in successfully",signedOut:"You are signed out",signupSuccess:"Account created. If email confirmation is required, verify your email, then sign in.",invalidCredentials:"Email or password is incorrect.",claimAccepted:"Success! Points have been added to your account.",claimInvalid:"This QR code is invalid or inactive.",claimDuplicate:"This QR code has already been used.",claimIneligible:"QR claims are available after account verification.",claimCampaign:"This campaign is not active.",claimError:"The QR claim did not complete. Please try again.",redeemDemo:"This is a demo reward and cannot be redeemed for real.",insufficientPoints:"You do not have enough points.",redeemSuccess:"Your redemption request has been recorded.",redemptionReserved:"Pending",redemptionApproved:"Approved",redemptionFulfilled:"Fulfilled",redemptionCancelled:"Cancelled · refunded",redemptionRejected:"Rejected · refunded",redeemError:"Redemption could not be completed.",networkError:"Connection problem. Check your internet and try again.",loading:"Loading…",retry:"Retry",cancel:"Cancel",scanTab:"Scan QR",homeTab:"Home",rewardsTab:"Rewards",accountTab:"Account",pointsEarned:"Points earned",pointsSpent:"Points used",status:"Status",date:"Date",history:"Activity",emailConfirm:"Email verification is pending. Open the email link, then sign in.",unknownError:"The request could not be completed.",phoneInvalid:"Use international phone format, for example +919876543210.",emailRateLimit:"Too many confirmation emails were requested. Please wait before trying again, or ask the app owner to configure a production email provider.",
    forgotPassword:"Forgot password?",resendConfirmation:"Resend confirmation email",recoverTitle:"Reset your password",recoverCopy:"We’ll email you a secure password-reset link.",resetTitle:"Choose a new password",resetCopy:"Enter and confirm your new password.",sendReset:"Send reset link",saveNewPassword:"Save new password",recoverySent:"If an account exists for this email, a password reset link has been sent.",recoveryHint:"Open the link from your email, then return to this page.",passwordMismatch:"The two passwords do not match.",passwordResetSuccess:"Your password has been updated. Sign in with your new password.",confirmationResent:"If this account exists, a confirmation email has been sent.",backToSignIn:"Back to sign in"
  }
};

const state = { lang: localStorage.getItem("growta-lang") || "hi", session: null, tenant: null, profile: null, rewards: [], ledger: [], redemptions: [], balance: 0, view: "home", authMode: "signin", cameraStream: null, scanFrame: null, barcodeDetector: null, busy: false };
if (new URLSearchParams(window.location.search).get("auth") === "reset") state.authMode = "reset";
const app = document.getElementById("app");
const pill = document.getElementById("connection-pill");
const t = (key) => (i18n[state.lang] && i18n[state.lang][key]) || i18n.en[key] || key;
document.getElementById("year").textContent = new Date().getFullYear();
document.getElementById("language-toggle").addEventListener("click", () => { state.lang = state.lang === "hi" ? "en" : "hi"; localStorage.setItem("growta-lang", state.lang); render(); if (state.session) loadDashboard(); });
window.addEventListener("online", updateConnection);
window.addEventListener("offline", updateConnection);
updateConnection();

function updateConnection() {
  pill.classList.toggle("online", navigator.onLine);
  pill.classList.toggle("offline", !navigator.onLine);
  const span = pill.querySelector("span");
  if (span) span.textContent = navigator.onLine ? t("online") : t("offline");
}
function esc(value) { return String(value ?? "").replace(/[&<>"']/g, c => ({ "&":"&amp;", "<":"&lt;", ">":"&gt;", '"':"&quot;", "'":"&#39;" }[c])); }
function moneylessPoints(n) { return new Intl.NumberFormat(state.lang === "hi" ? "hi-IN" : "en-IN").format(Number(n || 0)); }
function toast(message, type = "") {
  const region = document.getElementById("toast-region");
  const node = document.createElement("div"); node.className = "toast " + type; node.textContent = message; region.appendChild(node);
  setTimeout(() => node.remove(), 4200);
}
function friendlyError(error, fallback = "unknownError") {
  const msg = String(error?.message || error || "");
  if (/invalid login credentials|invalid email or password/i.test(msg)) return t("invalidCredentials");
  if (/network|fetch/i.test(msg)) return t("networkError");
  if (/phone_must_be_e164/i.test(msg)) return t("phoneInvalid");
  if (/over_email_send_rate_limit|email rate limit exceeded|too many requests/i.test(msg)) return t("emailRateLimit");
  if (/email_not_confirmed|email not confirmed/i.test(msg)) return t("emailConfirm");
  if (/password_mismatch/.test(msg)) return t("passwordMismatch");
  return t(fallback);
}
function stopCamera() {
  if (state.scanFrame) cancelAnimationFrame(state.scanFrame);
  state.scanFrame = null;
  if (state.cameraStream) state.cameraStream.getTracks().forEach(track => track.stop());
  state.cameraStream = null;
}
async function api(action, payload = {}) {
  const { data, error } = await supabase.functions.invoke(API_FUNCTION, { body: { action, ...payload } });
  if (error) throw error;
  if (data?.ok === false) return data;
  return data;
}
async function getTenant() {
  if (state.tenant) return state.tenant;
  const { data, error } = await supabase.from("tenants").select("id,name,slug,status,default_locale").eq("slug", TENANT_SLUG).maybeSingle();
  if (error) throw error;
  if (!data || data.status !== "active") throw new Error("tenant_unavailable");
  state.tenant = data;
  return data;
}
// Sum every ledger page for the account balance; the visible activity feed stays capped at 30.
async function loadPointsBalance(tenantId, partnerId) {
  const pageSize = 1000;
  let offset = 0;
  let balance = 0;
  while (true) {
    const { data, error } = await supabase.from("points_ledger")
      .select("id,points_delta,created_at")
      .eq("tenant_id", tenantId)
      .eq("partner_id", partnerId)
      .order("created_at", { ascending: true })
      .order("id", { ascending: true })
      .range(offset, offset + pageSize - 1);
    if (error) throw error;
    const rows = data || [];
    balance += rows.reduce((sum, item) => sum + Number(item.points_delta || 0), 0);
    if (rows.length < pageSize) break;
    offset += pageSize;
  }
  return balance;
}

async function loadDashboard() {
  if (!state.session) return;
  try {
    const tenant = await getTenant();
    const [profileRes, rewardsRes] = await Promise.all([
      supabase.from("partners").select("id,role,display_name,phone_e164,preferred_locale,verification_status").eq("tenant_id", tenant.id).eq("user_id", state.session.user.id).maybeSingle(),
      supabase.from("rewards").select("id,name,name_hi,description,description_hi,category,points_cost,stock_quantity,active,is_demo,sort_order").eq("tenant_id", tenant.id).eq("active", true).order("sort_order")
    ]);
    if (profileRes.error) throw profileRes.error;
    if (rewardsRes.error) throw rewardsRes.error;
    state.profile = profileRes.data;
    state.rewards = rewardsRes.data || [];
    if (state.profile) {
      const [ledgerRes, redemptionRes, balance] = await Promise.all([
        supabase.from("points_ledger").select("id,entry_type,points_delta,reason_code,created_at").eq("tenant_id", tenant.id).eq("partner_id", state.profile.id).order("created_at", { ascending: false }).limit(30),
        supabase.from("redemptions").select("id,reward_id,points_cost,status,created_at,fulfilled_at").eq("tenant_id", tenant.id).eq("partner_id", state.profile.id).order("created_at", { ascending: false }).limit(10),
        loadPointsBalance(tenant.id, state.profile.id)
      ]);
      if (ledgerRes.error) throw ledgerRes.error;
      if (redemptionRes.error) throw redemptionRes.error;
      state.ledger = ledgerRes.data || [];
      state.redemptions = redemptionRes.data || [];
      state.balance = balance;
    } else { state.ledger = []; state.redemptions = []; state.balance = 0; }
    render();
  } catch (error) {
    render();
    toast(friendlyError(error, "networkError"), "error");
  }
}
function render() {
  updateConnection();
  document.documentElement.lang = state.lang === "hi" ? "hi" : "en";
  document.title = "Growta RewardLoop";
  if (!state.session) renderAuth();
  else if (!state.profile) renderProfileSetup();
  else renderDashboard();
}
function authSubmitLabel() {
  return ({ signin:t("login"), signup:t("createAccount"), recover:t("sendReset"), reset:t("saveNewPassword") })[state.authMode] || t("login");
}
function renderAuth() {
  const signup = state.authMode === "signup";
  const recovering = state.authMode === "recover";
  const resetting = state.authMode === "reset";
  const title = resetting ? t("resetTitle") : recovering ? t("recoverTitle") : signup ? t("signUp") : t("signIn");
  const subtitle = resetting ? t("resetCopy") : recovering ? t("recoverCopy") : signup ? t("profileSub") : t("welcome");
  app.innerHTML = `
    <section class="auth-layout">
      <div class="auth-intro">
        <div class="eyebrow">${t("eyebrow")}</div><h1>${resetting ? t("resetTitle") : t("authTitle")}</h1><p>${resetting ? t("resetCopy") : t("authCopy")}</p>
        <div class="benefit-list"><div class="benefit"><span class="benefit-icon">✓</span><span>${t("benefit1")}</span></div><div class="benefit"><span class="benefit-icon">✓</span><span>${t("benefit2")}</span></div><div class="benefit"><span class="benefit-icon">✓</span><span>${t("benefit3")}</span></div></div>
      </div>
      <section class="panel auth-panel"><h2>${title}</h2><p class="muted small">${subtitle}</p>
        ${(!recovering && !resetting) ? `<div class="tabs"><button class="tab ${!signup ? "active" : ""}" data-mode="signin" type="button">${t("signIn")}</button><button class="tab ${signup ? "active" : ""}" data-mode="signup" type="button">${t("signUp")}</button></div>` : ""}
        <form id="auth-form" class="form-stack">
          ${signup ? `<div class="field"><label for="auth-name">${t("name")}</label><input id="auth-name" name="name" autocomplete="name" required minlength="2" maxlength="160"></div>` : ""}
          ${!resetting ? `<div class="field"><label for="auth-email">${t("email")}</label><input id="auth-email" name="email" type="email" autocomplete="email" required></div>` : ""}
          ${!recovering ? `<div class="field"><label for="auth-password">${t("password")}</label><input id="auth-password" name="password" type="password" autocomplete="${resetting || signup ? "new-password" : "current-password"}" minlength="8" required></div>` : ""}
          ${resetting ? `<div class="field"><label for="auth-password-confirm">${t("saveNewPassword")}</label><input id="auth-password-confirm" name="password_confirm" type="password" autocomplete="new-password" minlength="8" required></div>` : ""}
          ${signup ? `<div class="field"><label for="auth-phone">${t("phone")}</label><input id="auth-phone" name="phone" type="tel" autocomplete="tel" placeholder="+919876543210"></div>` : ""}
          <button class="primary-button wide" type="submit" id="auth-submit">${authSubmitLabel()}</button>
          <p id="auth-message" class="auth-switch" role="status" aria-live="polite"></p>
        </form>
        ${(!signup && !recovering && !resetting) ? `<div class="auth-switch"><button class="text-button" id="forgot-password" type="button">${t("forgotPassword")}</button><button class="text-button" id="resend-confirmation" type="button">${t("resendConfirmation")}</button></div>` : ""}
        ${recovering ? `<button class="text-button" data-mode="signin" type="button">${t("backToSignIn")}</button>` : ""}
        ${resetting ? `<button class="text-button" id="reset-cancel" type="button">${t("backToSignIn")}</button>` : ""}
      </section>
    </section>`;
  app.querySelectorAll("[data-mode]").forEach(btn => btn.addEventListener("click", () => { state.authMode = btn.dataset.mode; renderAuth(); }));
  document.getElementById("auth-form").addEventListener("submit", handleAuth);
  const forgot = document.getElementById("forgot-password");
  if (forgot) forgot.addEventListener("click", () => { state.authMode = "recover"; renderAuth(); });
  const resetCancel = document.getElementById("reset-cancel");
  if (resetCancel) resetCancel.addEventListener("click", async () => {
    state.authMode = "signin";
    history.replaceState({}, "", window.location.pathname);
    await supabase.auth.signOut();
    state.session = null; state.profile = null; renderAuth();
  });
  const resend = document.getElementById("resend-confirmation");
  if (resend) resend.addEventListener("click", async () => {
    const emailInput = document.getElementById("auth-email");
    const email = String(emailInput?.value || "").trim().toLowerCase();
    if (!email) { toast(t("email")+" required", "error"); emailInput?.focus(); return; }
    resend.disabled = true;
    try {
      const { error } = await supabase.auth.resend({ type:"signup", email, options:{ emailRedirectTo:window.location.origin } });
      if (error) throw error;
      const message = document.getElementById("auth-message");
      if (message) message.textContent = t("confirmationResent");
      toast(t("confirmationResent"), "success");
    } catch (error) { toast(friendlyError(error), "error"); }
    finally { if (document.getElementById("resend-confirmation")) resend.disabled = false; }
  });
}
async function handleAuth(event) {
  event.preventDefault();
  if (state.busy) return;
  state.busy = true;
  const form = event.currentTarget, button = document.getElementById("auth-submit");
  button.disabled = true; button.textContent = t("loading");
  const fd = new FormData(form), email = String(fd.get("email") || "").trim().toLowerCase(), password = String(fd.get("password") || "");
  try {
    if (state.authMode === "signup") {
      const displayName = String(fd.get("name") || "").trim();
      const phone = String(fd.get("phone") || "").trim();
      if (phone && !/^\+[1-9]\d{7,14}$/.test(phone)) throw new Error("phone_must_be_e164");
      const { data, error } = await supabase.auth.signUp({ email, password, options: { emailRedirectTo: window.location.origin, data: { display_name: displayName, preferred_locale: state.lang } } });
      if (error) throw error;
      if (data.session) {
        state.session = data.session;
        const profile = await api("profile", { display_name: displayName, phone_e164: phone, preferred_locale: state.lang === "hi" ? "hi-IN" : "en-IN" });
        if (!profile.ok) throw new Error(profile.error || "profile_create_failed");
        state.profile = profile.profile;
        toast(t("signupSuccess"), "success");
        await loadDashboard();
      } else {
        document.getElementById("auth-message").textContent = t("emailConfirm");
        toast(t("signupSuccess"), "success");
      }
    } else {
      const { data, error } = await supabase.auth.signInWithPassword({ email, password });
      if (error) throw error;
      state.session = data.session;
      toast(t("signedIn"), "success");
      await loadDashboard();
    }
  } catch (error) { toast(friendlyError(error), "error"); }
  finally { state.busy = false; const btn = document.getElementById("auth-submit"); if (btn) { btn.disabled = false; btn.textContent = state.authMode === "signup" ? t("createAccount") : t("login"); } }
}
function renderProfileSetup() {
  const meta = state.session?.user?.user_metadata || {};
  app.innerHTML = `
    <section class="auth-layout"><div class="auth-intro"><div class="eyebrow">${t("eyebrow")}</div><h1>${t("profileTitle")}</h1><p>${t("profileSub")}</p><div class="alert warn">${t("verificationPendingText")}</div></div>
    <section class="panel auth-panel"><h2>${t("profileTitle")}</h2><p class="muted small">${esc(state.session.user.email || "")}</p><form id="profile-form" class="form-stack">
      <div class="field"><label for="profile-name">${t("name")}</label><input id="profile-name" name="name" required minlength="2" maxlength="160" value="${esc(meta.display_name || meta.full_name || "")}"></div>
      <div class="field"><label for="profile-phone">${t("phone")}</label><input id="profile-phone" name="phone" type="tel" placeholder="+919876543210"></div>
      <div class="field"><label for="profile-locale">${t("language")}</label><select id="profile-locale" name="locale"><option value="hi-IN" ${state.lang === "hi" ? "selected" : ""}>${t("hindi")}</option><option value="en-IN" ${state.lang === "en" ? "selected" : ""}>${t("english")}</option></select></div>
      <button class="primary-button wide" type="submit">${t("saveProfile")}</button><button class="text-button" id="setup-signout" type="button">${t("signOut")}</button>
    </form></section></section>`;
  document.getElementById("profile-form").addEventListener("submit", async e => {
    e.preventDefault(); const fd = new FormData(e.currentTarget); const name = String(fd.get("name") || "").trim(); const phone = String(fd.get("phone") || "").trim(); const locale = String(fd.get("locale") || "hi-IN");
    try {
      const result = await api("profile", { display_name: name, phone_e164: phone, preferred_locale: locale });
      if (!result.ok) throw new Error(result.error || "profile_create_failed");
      state.profile = result.profile; state.view = "home"; toast(t("profileSaved"), "success"); await loadDashboard();
    } catch (err) { toast(friendlyError(err), "error"); }
  });
  document.getElementById("setup-signout").addEventListener("click", signOut);
}
function rewardName(reward) { return state.lang === "hi" ? (reward.name_hi || reward.name) : reward.name; }
function rewardDescription(reward) { return state.lang === "hi" ? (reward.description_hi || reward.description || "") : (reward.description || ""); }
function categoryIcon(category) { return ({farm_essentials:"🌱",vouchers:"🎟️",services:"🧪",tools:"🛠️"})[category] || "🎁"; }
function renderRewards() {
  if (!state.rewards.length) return `<div class="empty-state"><strong>${t("noRewards")}</strong></div>`;
  return `<div class="reward-grid">${state.rewards.map(r => {
    const isDemo = r.is_demo;
    const inStock = r.stock_quantity === null || Number(r.stock_quantity) > 0;
    const available = !isDemo && inStock && state.profile.verification_status === "verified" && state.balance >= Number(r.points_cost);
    return `<article class="reward-card"><div class="reward-visual">${categoryIcon(r.category)}</div><div class="reward-category">${esc(r.category || "general").replace(/_/g," ")}</div><h3>${esc(rewardName(r))}</h3><p>${esc(rewardDescription(r))}</p><div class="reward-meta"><span class="points-cost">${moneylessPoints(r.points_cost)} ${t("pointsCost")}</span><span class="tag ${isDemo ? "demo" : ""}">${isDemo ? t("demo") : (available ? t("verified") : t("notAvailable"))}</span></div>${isDemo ? `<p class="small">${t("demoNotice")}</p>` : `<button class="secondary-button wide" data-redeem="${esc(r.id)}" ${available ? "" : "disabled"}>${t("redeem")}</button>`}</article>`;
  }).join("")}</div>`;
}
function renderHistory() {
  if (!state.ledger.length && !state.redemptions.length) return `<div class="empty-state"><strong>${t("noActivity")}</strong>${t("historySub")}</div>`;
  const locale = state.lang === "hi" ? "hi-IN" : "en-IN";
  const ledger = state.ledger.slice(0,12).map(item => {
    const delta = Number(item.points_delta || 0);
    const label = delta > 0 ? t("pointsEarned") : t("pointsSpent");
    return {created_at:item.created_at, sort: new Date(item.created_at).getTime(), html:`<div class="history-item"><div><div class="history-title">${esc(item.reason_code || item.entry_type || label)}</div><div class="history-sub">${new Date(item.created_at).toLocaleString(locale,{dateStyle:"medium",timeStyle:"short"})}</div></div><div class="delta ${delta >= 0 ? "plus" : "minus"}">${delta > 0 ? "+" : ""}${moneylessPoints(delta)}</div></div>`};
  });
  const redemptions = state.redemptions.map(item => {
    const statusLabel = ({reserved:t("redemptionReserved"),approved:t("redemptionApproved"),fulfilled:t("redemptionFulfilled"),cancelled:t("redemptionCancelled"),rejected:t("redemptionRejected")})[item.status] || item.status;
    return {created_at:item.created_at,sort:new Date(item.created_at).getTime(),html:`<div class="history-item"><div><div class="history-title">${t("redeem")}</div><div class="history-sub">${new Date(item.created_at).toLocaleString(locale,{dateStyle:"medium",timeStyle:"short"})} · ${esc(statusLabel)}</div></div><div class="delta minus">−${moneylessPoints(item.points_cost)}</div></div>`};
  });
  return `<div class="history-list">${[...ledger,...redemptions].sort((x,y)=>y.sort-x.sort).slice(0,12).map(item=>item.html).join("")}</div>`;
}
function renderScan() {
  return `<div class="panel"><h3>${t("scan")}</h3><p class="muted small">${t("scanSub")}</p><div class="scan-box">
    <video id="scan-video" class="scan-camera hidden" playsinline muted></video>
    <div class="scan-actions"><button class="primary-button" id="camera-start" type="button">▣ ${t("scanStart")}</button><button class="secondary-button hidden" id="camera-stop" type="button">${t("scanStop")}</button></div>
    <div id="scan-message" class="alert info hidden"></div>
    <form id="claim-form" class="form-stack"><div class="field"><label for="qr-token">${t("enterCode")}</label><input id="qr-token" class="scan-input" name="token" autocomplete="off" autocapitalize="off" spellcheck="false" required minlength="16" maxlength="512"></div><button class="primary-button wide" type="submit">${t("claim")}</button></form>
    <p class="qr-note">${t("claimIneligible")}</p>
  </div></div>`;
}
function renderDashboard() {
  const profile = state.profile;
  const isVerified = profile.verification_status === "verified";
  const isHome = state.view === "home";
  const content = state.view === "scan" ? `<div class="section-heading"><div><h2>${t("scan")}</h2><p>${t("scanSub")}</p></div></div>${renderScan()}` :
    state.view === "account" ? `<div class="section-heading"><div><h2>${t("profile")}</h2><p>${t("profileSub")}</p></div></div><section class="panel"><div class="profile-row"><div class="avatar">${esc((profile.display_name || "G").slice(0,1).toUpperCase())}</div><div class="profile-meta"><strong>${esc(profile.display_name)}</strong><span>${esc(state.session.user.email || "")}</span></div><span class="tag ${isVerified ? "verified" : "pending"}">${isVerified ? t("verified") : t("unverified")}</span></div><div class="section-heading"><div><h2>${t("profile")}</h2></div></div><div class="pill-row"><span class="pill">${esc(profile.role)}</span><span class="pill">${esc(profile.preferred_locale || "hi-IN")}</span><span class="pill">${esc(profile.phone_e164 || "—")}</span></div><div class="alert ${isVerified ? "success" : "warn"}">${isVerified ? t("verified") : t("verificationPendingText")}</div><button class="danger-button" id="signout-button" type="button">${t("signOut")}</button></section>` :
    state.view === "rewards" ? `<div class="section-heading"><div><h2>${t("catalog")}</h2><p>${t("catalogSub")}</p></div></div>${renderRewards()}` :
    `<section class="hero"><div class="hero-copy"><div class="eyebrow">${t("eyebrow")}</div><h1>${t("heroTitle")}</h1><p>${t("heroCopy")}</p><div class="pill-row" style="margin-top:20px"><span class="pill">✓ ${t("benefit1")}</span><span class="pill">✓ ${t("benefit2")}</span></div></div><div class="hero-art"><div class="art-label">GROWTA REWARDLOOP</div><div><div class="points-big">${moneylessPoints(state.balance)}</div><div class="points-caption">${t("points")}</div></div><div class="art-bottom"><span class="points-caption">${esc(profile.display_name)}</span><span class="art-icon">✳</span></div></div></section>
      ${!isVerified ? `<div class="alert warn"><strong>${t("verificationPending")}</strong><br>${t("verificationPendingText")}</div>` : ""}
      <div class="layout-grid"><section><div class="section-heading"><div><h2>${t("catalog")}</h2><p>${t("catalogSub")}</p></div><button class="text-button" data-view="rewards">${t("rewardsTab")} →</button></div>${renderRewards()}</section><aside><div class="section-heading"><div><h2>${t("history")}</h2><p>${t("historySub")}</p></div></div><section class="panel">${renderHistory()}</section><div class="section-heading"><div><h2>${t("scan")}</h2><p>${t("scanSub")}</p></div></div><section class="panel"><div class="status-card"><span style="font-size:22px">⌗</span><div><strong>${t("scan")}</strong><span>${t("scanSub")}</span></div></div><button class="primary-button wide" style="margin-top:14px" data-view="scan">${t("scanTab")} →</button></section></aside></div>`;
  app.innerHTML = `${content}<nav class="bottom-nav" aria-label="Main navigation"><button data-view="home" class="${state.view === "home" ? "active" : ""}">⌂ ${t("homeTab")}</button><button data-view="scan" class="${state.view === "scan" ? "active" : ""}">⌗ ${t("scanTab")}</button><button data-view="rewards" class="${state.view === "rewards" ? "active" : ""}">✳ ${t("rewardsTab")}</button><button data-view="account" class="${state.view === "account" ? "active" : ""}">◉ ${t("accountTab")}</button></nav>`;
  app.querySelectorAll("[data-view]").forEach(btn => btn.addEventListener("click", async () => { stopCamera(); state.view = btn.dataset.view; renderDashboard(); }));
  app.querySelectorAll("[data-redeem]").forEach(btn => btn.addEventListener("click", () => redeemReward(btn.dataset.redeem)));
  const signout = document.getElementById("signout-button"); if (signout) signout.addEventListener("click", signOut);
  const claimForm = document.getElementById("claim-form"); if (claimForm) claimForm.addEventListener("submit", claimQr);
  const startCamera = document.getElementById("camera-start"); if (startCamera) startCamera.addEventListener("click", startQrScanner);
  const stop = document.getElementById("camera-stop"); if (stop) stop.addEventListener("click", () => { stopCamera(); renderDashboard(); });
}
async function claimQr(event) {
  event.preventDefault();
  const form = event.currentTarget, button = form.querySelector("button[type=submit]"), tokenInput = document.getElementById("qr-token");
  const token = String(tokenInput.value || "").trim();
  if (token.length < 16) return toast(t("claimInvalid"), "error");
  button.disabled = true; button.textContent = t("loading");
  try {
    const result = await api("claim", { token, request_id: crypto.randomUUID() });
    if (result.ok && result.outcome === "accepted") { toast(t("claimAccepted"), "success"); tokenInput.value = ""; await loadDashboard(); }
    else {
      const key = ({ invalid_code:"claimInvalid", already_claimed:"claimDuplicate", ineligible:"claimIneligible", campaign_inactive:"claimCampaign", revoked:"claimInvalid", expired:"claimInvalid", not_activated:"claimInvalid" })[result.outcome] || "claimError";
      toast(t(key), "error");
    }
  } catch (error) { toast(friendlyError(error, "claimError"), "error"); }
  finally { button.disabled = false; button.textContent = t("claim"); }
}
async function redeemReward(rewardId) {
  if (!confirm(t("redeem") + "?")) return;
  try {
    const result = await api("redeem", { reward_id: rewardId, request_key: crypto.randomUUID() });
    if (result.ok) { toast(t("redeemSuccess"), "success"); await loadDashboard(); }
    else {
      const key = result.error === "demo_reward_not_redeemable" ? "redeemDemo" : result.error === "insufficient_points" ? "insufficientPoints" : "redeemError";
      toast(t(key), "error");
    }
  } catch (error) { toast(friendlyError(error, "redeemError"), "error"); }
}
async function startQrScanner() {
  if (!("BarcodeDetector" in window) || !navigator.mediaDevices?.getUserMedia) return toast(t("cameraUnsupported"), "error");
  try {
    state.barcodeDetector = new BarcodeDetector({ formats: ["qr_code"] });
    state.cameraStream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: { ideal: "environment" } }, audio: false });
    renderDashboard();
    const video = document.getElementById("scan-video");
    const start = document.getElementById("camera-start"), stop = document.getElementById("camera-stop");
    video.classList.remove("hidden"); video.srcObject = state.cameraStream; await video.play();
    start.classList.add("hidden"); stop.classList.remove("hidden");
    const msg = document.getElementById("scan-message"); msg.classList.remove("hidden"); msg.textContent = t("scanNoCode");
    const scan = async () => {
      if (!state.cameraStream || !video || video.readyState < 2) { state.scanFrame = requestAnimationFrame(scan); return; }
      try {
        const codes = await state.barcodeDetector.detect(video);
        if (codes.length && codes[0].rawValue) {
          const raw = codes[0].rawValue;
          let token = raw;
          try { const u = new URL(raw); token = u.searchParams.get("token") || u.searchParams.get("code") || raw; } catch {}
          const input = document.getElementById("qr-token"); if (input) input.value = token;
          msg.textContent = t("scanDetected"); stopCamera(); toast(t("scanSuccess"), "success"); return;
        }
      } catch {}
      state.scanFrame = requestAnimationFrame(scan);
    };
    state.scanFrame = requestAnimationFrame(scan);
  } catch { stopCamera(); toast(t("cameraPermission"), "error"); }
}
async function signOut() {
  stopCamera();
  await supabase.auth.signOut();
  state.session = null; state.profile = null; state.ledger = []; state.redemptions = []; state.balance = 0; state.view = "home"; state.authMode = "signin";
  render(); toast(t("signedOut"));
}
supabase.auth.onAuthStateChange((_event, session) => {
  state.session = session;
  if (!session) { state.profile = null; state.ledger = []; state.balance = 0; render(); }
  else { queueMicrotask(() => loadDashboard()); }
});
const { data: { session } } = await supabase.auth.getSession();
state.session = session;
if (session) await loadDashboard(); else render();

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.0";
const supabase = createClient("https://guhhuqxrobhuumwrypnc.supabase.co", "sb_publishable_6dr2KACqmGBM2AWZS6NTDw_1Kf3e8ru", { auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true } });
const root = document.getElementById("billing-app"), signout = document.getElementById("billing-signout"), toastRoot = document.getElementById("billing-toast");
let tenants = [], selectedTenant = "", plans = [], subscription = null, checkouts = [], loading = false, busy = false, note = "";
const esc = value => String(value ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
function toast(message, error = false) { const el = document.createElement("div"); el.className = "toast" + (error ? " error" : ""); el.textContent = message; toastRoot.appendChild(el); setTimeout(() => el.remove(), 4000); }
function money(minor, currency) { try { return new Intl.NumberFormat("en-IN", { style: "currency", currency, maximumFractionDigits: 2 }).format(Number(minor) / 100); } catch { return `${currency} ${(Number(minor) / 100).toFixed(2)}`; } }
async function invoke(name, body) { const { data, error } = await supabase.functions.invoke(name, { body }); if (error) { let message = error.message || "Request failed"; try { const payload = await error.context.clone().json(); if (typeof payload?.error === "string") message = payload.error; } catch {} throw new Error(message); } if (data?.ok === false) throw new Error(data.error || "Request failed"); return data; }
function login(message = "") { signout.classList.add("hidden"); root.innerHTML = `<section class="panel admin-panel"><div class="eyebrow">GROWTA · BILLING</div><h1>Sign in to manage billing</h1>${message ? `<div class="alert warn">${esc(message)}</div>` : ""}<p>Use your existing RewardLoop administrator session. Billing access requires an active tenant brand-admin or super-admin membership.</p><div class="admin-actions"><a class="primary-button" href="/admin.html">Open admin sign-in ↗</a><button id="billing-retry" class="secondary-button" type="button">I am signed in · Retry</button></div></section>`; document.getElementById("billing-retry").addEventListener("click", boot); }
async function loadPortal() { loading = true; draw(); try { const result = await invoke("saas-billing-portal", { tenant_id: selectedTenant }); plans = Array.isArray(result.plans) ? result.plans : []; subscription = result.subscription || null; note = "";
    const tenant = tenants.find(t => t.id === selectedTenant);
    checkouts = [];
    if (tenant?.role === "super_admin") {
      try { const queue = await invoke("saas-checkout-reconciliation", { tenant_id: selectedTenant, min_age_minutes: 10 }); checkouts = Array.isArray(queue.checkouts) ? queue.checkouts : []; }
      catch (error) { note = `Billing loaded, but reconciliation queue is unavailable: ${error.message || "request failed"}`; }
    } } catch (error) { note = error.message || "Billing information could not be loaded."; plans = []; subscription = null; } finally { loading = false; draw(); } }
function statusLabel(value) { return String(value || "unknown").replace(/_/g, " "); }
function draw() {
  const tenant = tenants.find(t => t.id === selectedTenant);
  root.innerHTML = `<div class="admin-title"><div><div class="eyebrow">GROWTA REWARDLOOP · BILLING</div><h1>Subscription and billing</h1><p class="muted small">${esc(tenant?.name || "Select a tenant")}</p></div><button id="billing-refresh" class="secondary-button" ${loading || busy ? "disabled" : ""}>↻ Refresh</button></div>
  ${tenants.length > 1 ? `<section class="panel admin-panel"><div class="field"><label for="billing-tenant">Tenant workspace</label><select id="billing-tenant">${tenants.map(t => `<option value="${esc(t.id)}" ${t.id === selectedTenant ? "selected" : ""}>${esc(t.name)} · ${esc(t.role)}</option>`).join("")}</select></div></section>` : ""}
  ${note ? `<section class="panel admin-panel"><div class="alert warn">${esc(note)}</div></section>` : ""}
  ${subscription ? `<section class="panel admin-panel"><h2>Current / latest subscription</h2><p><strong>${esc(subscription.plan_name || "Plan")}</strong> · ${esc(statusLabel(subscription.status))} · ${esc(subscription.billing_interval)}</p><p class="history-sub">${money(subscription.amount_minor, subscription.currency)} per ${subscription.billing_interval === "yearly" ? "year" : "month"} · Created ${esc(new Date(subscription.created_at).toLocaleString())}</p>${subscription.current_period_end ? `<p class="history-sub">Current period ends ${esc(new Date(subscription.current_period_end).toLocaleString())}</p>` : ""}${subscription.cancel_at_period_end ? `<div class="alert warn">Cancellation is scheduled for the end of the current period.</div>` : ""}${subscription.checkout_url ? `<p><a href="${esc(subscription.checkout_url)}" rel="noopener noreferrer" target="_blank">Open saved Razorpay checkout ↗</a></p>` : ""}${subscription.status === "incomplete" ? `<div class="alert warn">This subscription is incomplete. If the provider request timed out, do not start a new checkout. Contact a super-admin to reconcile the provider subscription first.</div>` : ""}</section>` : `<section class="panel admin-panel"><h2>No subscription record</h2><p class="muted">Choose a published plan below to start a subscription.</p></section>`}
  ${tenant?.role === "super_admin" ? `<section class="panel admin-panel"><h2>Checkout reconciliation queue</h2><p>Read-only list of incomplete checkouts older than 10 minutes. This page does not alter subscription state. Confirm ambiguous outcomes in Razorpay before authorizing a retry.</p>${checkouts.length ? checkouts.map(item => `<div class="history-item"><div><div class="history-title">Subscription ${esc(String(item.subscription_id || "").slice(0, 8))}… · ${esc(item.billing_interval)} · ${esc(item.status)}</div><div class="history-sub">Age ${Math.floor(Number(item.age_seconds || 0) / 60)} minutes · ${item.provider_subscription_id ? `Provider ${esc(item.provider_subscription_id)}` : "Provider subscription ID not recorded"}</div>${item.needs_provider_reconciliation ? `<div class="alert warn">Check Razorpay for a subscription using the Growta subscription ID in the provider notes. Do not retry blindly.</div>` : ""}${item.checkout_url ? `<a href="${esc(item.checkout_url)}" target="_blank" rel="noopener noreferrer">Open hosted checkout ↗</a>` : ""}</div></div>`).join("") : `<div class="admin-empty">No aged incomplete checkouts currently need review.</div>`}</section>` : ""}
  <section class="panel admin-panel"><h2>Published plans</h2><p>Prices are supplied by the billing service. Checkout opens on Razorpay; this page never collects payment credentials.</p>${loading ? `<p role="status">Loading billing details…</p>` : plans.length ? `<div class="admin-columns">${plans.map(plan => `<article class="panel"><h3>${esc(plan.display_name)}</h3><p class="history-sub">Version ${esc(plan.version_no)} · ${esc(plan.trial_days)} trial days</p><div class="field"><label for="interval-${esc(plan.plan_version_id)}">Billing interval</label><select id="interval-${esc(plan.plan_version_id)}" data-interval-for="${esc(plan.plan_version_id)}"><option value="monthly" ${plan.monthly_available ? "selected" : "disabled"}>Monthly · ${money(plan.monthly_amount_minor, plan.currency)}${plan.monthly_available ? "" : " (unavailable)"}</option><option value="yearly" ${plan.yearly_available ? (plan.monthly_available ? "" : "selected") : "disabled"}>Yearly · ${money(plan.yearly_amount_minor, plan.currency)}${plan.yearly_available ? "" : " (unavailable)"}</option></select></div><p class="history-sub">${esc(plan.currency)} pricing · Published version</p><button type="button" class="primary-button wide" data-checkout="${esc(plan.plan_version_id)}" ${(busy || (!plan.monthly_available && !plan.yearly_available) || (subscription && ["incomplete", "trialing", "active", "past_due", "paused"].includes(subscription.status))) ? "disabled" : ""}>${busy ? "Opening checkout…" : "Continue to checkout"}</button></article>`).join("")}</div>` : `<div class="admin-empty">No published plans are available yet. A platform super-admin must publish a plan and configure its Razorpay monthly/yearly plan IDs first.</div>`}</section>
  <section class="panel admin-panel"><h2>Payment safety</h2><ul><li>Payment credentials are entered only on Razorpay-hosted checkout.</li><li>Repeated checkout requests use an idempotency key to avoid duplicate subscriptions.</li><li>Ambiguous provider responses remain blocked for reconciliation; do not retry with a new key.</li><li>This portal does not yet issue GST invoices, process refunds, change plans mid-cycle, or cancel subscriptions.</li></ul></section>`;
  document.getElementById("billing-refresh")?.addEventListener("click", loadPortal);
  document.getElementById("billing-tenant")?.addEventListener("change", async e => { selectedTenant = e.currentTarget.value; await loadPortal(); });
  root.querySelectorAll("[data-checkout]").forEach(button => button.addEventListener("click", async () => {
    if (busy) return;
    const planVersionId = button.dataset.checkout;
    const interval = root.querySelector(`[data-interval-for="${CSS.escape(planVersionId)}"]`)?.value;
    if (!planVersionId || !["monthly", "yearly"].includes(interval)) return toast("Choose a valid plan interval.", true);
    const keyName = `growta-checkout:${selectedTenant}:${planVersionId}:${interval}`;
    let key = sessionStorage.getItem(keyName);
    if (!key) { key = crypto.randomUUID(); sessionStorage.setItem(keyName, key); }
    busy = true; draw();
    try {
      const result = await supabase.functions.invoke("create-razorpay-subscription", { body: { tenant_id: selectedTenant, plan_version_id: planVersionId, billing_interval: interval }, headers: { "Idempotency-Key": key } });
      if (result.error) { let message = result.error.message || "Checkout request failed"; try { const payload = await result.error.context.clone().json(); if (payload?.error) message = payload.error; } catch {} if (message === "checkout_reconciliation_required") note = "Checkout needs provider reconciliation. Do not retry with a new key."; throw new Error(message); }
      if (!result.data?.ok || typeof result.data.checkout_url !== "string") throw new Error(result.data?.error || "checkout_response_invalid");
      sessionStorage.removeItem(keyName);
      window.location.assign(result.data.checkout_url);
    } catch (error) { toast(error.message || "Checkout failed", true); busy = false; await loadPortal(); }
  }));
}
async function boot() {
  const { data: sessionData } = await supabase.auth.getSession();
  if (!sessionData.session) { login(); return; }
  signout.classList.remove("hidden");
  try {
    const result = await invoke("rewardloop-api", { action: "admin_tenants" });
    tenants = Array.isArray(result.tenants) ? result.tenants : [];
    if (!tenants.length) { login("This account has no active tenant-admin membership."); return; }
    if (!tenants.some(t => t.id === selectedTenant)) selectedTenant = tenants.find(t => t.role === "super_admin")?.id || tenants[0].id;
    await loadPortal();
  } catch (error) { login(error.message === "admin_access_required" ? "This account has no active tenant-admin membership." : error.message); }
}
signout.addEventListener("click", async () => { await supabase.auth.signOut(); tenants = []; selectedTenant = ""; login("You have signed out."); });
supabase.auth.onAuthStateChange((_event, session) => { if (!session) { tenants = []; selectedTenant = ""; login(); } });
boot();

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.0";
const db=createClient("https://guhhuqxrobhuumwrypnc.supabase.co","sb_publishable_6dr2KACqmGBM2AWZS6NTDw_1Kf3e8ru",{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}});
const root=document.getElementById("admin-app"),out=document.getElementById("admin-toast"),signout=document.getElementById("admin-signout");let data=null,partnerQuery="",partnerStatus="all",selectedTenantSlug="",adminTenants=[],tenantContextFallback=false,pendingQrExport=null;const ADMIN_SCOPED_ACTIONS=new Set(["admin_dashboard","admin_audit_logs","admin_record_export","verify_partner","issue_qr_batch","revoke_qr_batch","resolve_redemption","set_campaign_status","create_campaign","set_point_value","create_product","set_product_status","update_product"]);const pages={partners:0,products:0,campaigns:0,batches:0,redemptions:0,audit:0};
const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
function toast(s,bad=false){const e=document.createElement("div");e.className="toast"+(bad?" error":"");e.textContent=s;out.appendChild(e);setTimeout(()=>e.remove(),4000)}
async function call(action,payload={}){const tenantScope=ADMIN_SCOPED_ACTIONS.has(action)&&selectedTenantSlug?{tenant_slug:selectedTenantSlug}:{};const {data,error}=await db.functions.invoke("rewardloop-api",{body:{action,...tenantScope,...payload}});if(error){let message=error.message||"Request failed";try{const body=await error.context.clone().json();if(typeof body?.error==="string")message=body.error}catch{}throw new Error(message)}if(data?.ok===false)throw new Error(data.error||"Request failed");return data}
function loginView(note=""){signout.classList.add("hidden");root.innerHTML=`<section class="auth-layout"><div class="auth-intro"><div class="eyebrow">GROWTA · OPERATIONS</div><h1>RewardLoop control room</h1><p>Review partner verification and manage QR issuance. Access requires approved tenant-admin membership.</p><div class="benefit-list"><div class="benefit"><span class="benefit-icon">✓</span><span>Server-verified permissions</span></div><div class="benefit"><span class="benefit-icon">✓</span><span>Audited QR issuance and revocation</span></div></div></div><section class="panel auth-panel"><h2>Administrator sign in</h2>${note?`<div class="alert warn">${esc(note)}</div>`:""}<form id="login-form" class="form-stack"><div class="field"><label>Email</label><input name="email" type="email" required autocomplete="username"></div><div class="field"><label>Password</label><input name="password" type="password" required minlength="8" autocomplete="current-password"></div><button class="primary-button wide">Sign in securely</button></form></section></section>`;document.getElementById("login-form").addEventListener("submit",async e=>{e.preventDefault();const f=new FormData(e.currentTarget);const {data,error}=await db.auth.signInWithPassword({email:String(f.get("email")).trim().toLowerCase(),password:String(f.get("password"))});if(error){loginView(/invalid login/i.test(error.message)?"Email or password is incorrect.":error.message);return}await refresh()})}
function pager(name,info){if(!info)return "";const page=Math.max(0,Number(info.page)||0),size=Math.max(1,Number(info.page_size)||1),total=Math.max(0,Number(info.total)||0);if(total<=size)return "";const totalPages=Math.max(1,Math.ceil(total/size));return `<div class="history-item admin-pager"><span class="history-sub">Page ${page+1} of ${totalPages} · ${total.toLocaleString("en-IN")} total</span><div class="admin-actions"><button type="button" class="secondary-button" data-page-group="${esc(name)}" data-page-dir="-1" ${page<=0?"disabled":""}>Previous</button><button type="button" class="secondary-button" data-page-group="${esc(name)}" data-page-dir="1" ${page+1>=totalPages?"disabled":""}>Next</button></div></div>`;}
function renderPartnerRows(){
  if(!data) return "";
  const q=partnerQuery.trim().toLowerCase();
  const rows=data.partners.filter(p=>{
    const matchesQuery=!q||[p.display_name,p.phone_e164,p.role,p.id].some(v=>String(v||"").toLowerCase().includes(q));
    const matchesStatus=partnerStatus==="all"||(partnerStatus==="pending"?["pending","unverified"].includes(p.verification_status):p.verification_status===partnerStatus);
    return matchesQuery&&matchesStatus;
  });
  if(!rows.length)return '<tr><td colspan="4">No matching partners.</td></tr>';
  return rows.map(p=>`<tr><td><strong>${esc(p.display_name)}</strong><br>${esc(p.phone_e164||"No phone")}</td><td>${badge(p.verification_status)}</td><td>${esc(new Date(p.created_at).toLocaleDateString())}</td><td><div class="admin-actions"><button class="secondary-button" data-verify="${esc(p.id)}" data-status="verified">Verify</button><button class="danger-button" data-verify="${esc(p.id)}" data-status="rejected">Reject</button></div></td></tr>`).join("");
}
function csvCell(value){
  let text=String(value??"");
  // Prevent spreadsheet formula execution from untrusted names, SKU values or notes.
  // Prefix an apostrophe before leading whitespace/control characters and formula sigils.
  if(/^[\u0000-\u0020]*[=+\-@]/.test(text))text="'"+text;
  return '"'+text.replace(/"/g,'""')+'"';
}
function downloadCsv(filename,rows){
  const csv=rows.map(row=>row.map(csvCell).join(",")).join("\r\n");
  const url=URL.createObjectURL(new Blob(["\uFEFF"+csv],{type:"text/csv;charset=utf-8"}));
  const a=document.createElement("a");a.href=url;a.download=filename;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
}
function qrExportCsv(batch){
  const rows=[["ordinal","qr_id","token","qr_payload"],...batch.codes.map(c=>[c.ordinal,c.qr_id,c.token,c.qr_payload])];
  return "\uFEFF"+rows.map(row=>row.map(csvCell).join(",")).join("\r\n");
}
function downloadPendingQrExport(){
  if(!pendingQrExport||!Array.isArray(pendingQrExport.codes)||!pendingQrExport.codes.length){toast("No QR export is available in this browser session.",true);return;}
  const url=URL.createObjectURL(new Blob([qrExportCsv(pendingQrExport)],{type:"text/csv;charset=utf-8"}));
  const a=document.createElement("a");a.href=url;a.download="growta-qr-batch-"+pendingQrExport.batch_id+".csv";
  document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);
  toast("QR CSV download requested. Verify the file before clearing this one-time export.");
}
function renderQrExportNotice(){
  if(!pendingQrExport)return "";
  const complete=pendingQrExport.complete===true;
  const title=complete?"One-time QR export ready":"QR batch export needs attention";
  const message=complete?"These QR tokens exist only in this browser memory until cleared or page exit. Download and securely store the CSV first.":"The batch was created, but the API returned fewer codes than requested or one or more token payloads are incomplete. Do not issue a replacement batch automatically. Record the batch ID and reconcile before packaging.";
  const action=complete?"Download CSV again":"Download returned codes";
  const clear=complete?"I secured the file — clear tokens":"Clear in-memory tokens";
  return '<section class="panel admin-panel qr-export-notice" role="alert"><h2>'+title+'</h2><p>'+message+'</p><p class="history-sub">Batch '+esc(pendingQrExport.batch_id)+' · Tenant '+esc(pendingQrExport.tenant_slug)+' · '+pendingQrExport.codes.length+' of '+pendingQrExport.expected_count+' codes returned</p><div class="admin-actions"><button type="button" class="primary-button" id="download-qr-export">'+action+'</button><button type="button" class="secondary-button" id="clear-qr-export">'+clear+'</button></div></section>';
}
const badge=s=>`<span class="admin-badge ${["pending","unverified","paused","draft"].includes(s)?"warn":["rejected","suspended","failed"].includes(s)?"bad":""}">${esc(s)}</span>`;
async function refresh(){try{let context;try{context=await call("admin_tenants");tenantContextFallback=false}catch(e){if(e.message!=="unknown_action")throw e;tenantContextFallback=true;context={tenants:[{slug:"growta-rewardloop",name:"Growta RewardLoop",role:"legacy-backend"}]}}adminTenants=Array.isArray(context.tenants)?context.tenants:[];if(!adminTenants.length){signout.classList.remove("hidden");loginView("This account has no active tenant-admin memberships.");return}if(!adminTenants.some(t=>t.slug===selectedTenantSlug)){selectedTenantSlug=adminTenants.some(t=>t.slug==="growta-rewardloop")?"growta-rewardloop":adminTenants[0].slug}data=await call("admin_dashboard",{tenant_slug:selectedTenantSlug,partner_query:partnerQuery,partner_status:partnerStatus,partners_page:pages.partners,products_page:pages.products,campaigns_page:pages.campaigns,batches_page:pages.batches,redemptions_page:pages.redemptions});if(data.capabilities?.audit_log_viewer){const audit=await call("admin_audit_logs",{tenant_slug:selectedTenantSlug,audit_page:pages.audit});data.audit_logs=Array.isArray(audit.logs)?audit.logs:[];data.pagination={...(data.pagination||{}),audit:audit.pagination}}signout.classList.remove("hidden");draw()}catch(e){loginView(e.message==="admin_access_required"?"This account has no active brand-admin/super-admin membership. Grant access to an approved operator first.":e.message);}}
function draw(){const pending=Number(data.metrics?.partners_pending??data.partners.filter(p=>["pending","unverified"].includes(p.verification_status)).length);const tenantPicker=adminTenants.length>1?`<label class="tenant-picker">Tenant<select id="admin-tenant-select">${adminTenants.map(t=>`<option value="${esc(t.slug)}" ${t.slug===selectedTenantSlug?"selected":""}>${esc(t.name)} · ${esc(t.role)}</option>`).join("")}</select></label>`:"";root.innerHTML=`${pendingQrExport?renderQrExportNotice():""}${tenantContextFallback?`<div class="tenant-compat-warning" role="status">Tenant switching is temporarily unavailable while the backend is updated. This session is limited to Growta RewardLoop; server-side membership checks still apply.</div>`:""}<div class="admin-title"><div><div class="eyebrow">GROWTA REWARDLOOP · OPERATIONS</div><h1>Control room</h1><p class="muted small">${esc(data.tenant.name)} · ${esc(data.role)}</p>${tenantPicker}</div><button id="refresh" class="secondary-button">↻ Refresh</button></div><div class="admin-stats"><div class="admin-stat"><span>Partners</span><strong>${Number(data.metrics?.partners_total??data.pagination?.partners?.total??data.partners.length).toLocaleString("en-IN")}</strong></div><div class="admin-stat"><span>Pending verification</span><strong>${pending}</strong></div><div class="admin-stat"><span>Active campaigns</span><strong>${Number(data.metrics?.campaigns_active??data.campaigns.filter(c=>c.status==="active").length).toLocaleString("en-IN")}</strong></div><div class="admin-stat"><span>Active products</span><strong>${Number(data.metrics?.products_active??data.products.filter(p=>p.active).length).toLocaleString("en-IN")}</strong></div><div class="admin-stat"><span>Codes issued</span><strong>${Number(data.metrics?.qr_codes_issued_total??data.batches.filter(b=>["issued","revoked"].includes(b.status)).reduce((n,b)=>n+Number(b.requested_count||0),0)).toLocaleString("en-IN")}</strong></div><div class="admin-stat"><span>Open redemptions</span><strong>${Number(data.metrics?.redemptions_open??data.redemptions.filter(r=>["reserved","approved"].includes(r.status)).length).toLocaleString("en-IN")}</strong></div></div>
<section class="panel admin-panel"><h2>Partner verification</h2><p>Complete your identity and eligibility checks before approving a partner. Rejection or suspension requires a reason.</p>${(data.pagination?.partners?.total??data.partners.length)>0?`<div class="admin-form"><div class="field"><label for="partner-search">Search partners</label><input id="partner-search" type="search" placeholder="Name or phone" value="${esc(partnerQuery)}"><button type="button" id="partner-search-submit" class="secondary-button">Search all</button></div><div class="field"><label for="partner-status">Verification status</label><select id="partner-status"><option value="all" ${partnerStatus==="all"?"selected":""}>All statuses</option><option value="pending" ${partnerStatus==="pending"?"selected":""}>Pending</option><option value="verified" ${partnerStatus==="verified"?"selected":""}>Verified</option><option value="rejected" ${partnerStatus==="rejected"?"selected":""}>Rejected</option><option value="suspended" ${partnerStatus==="suspended"?"selected":""}>Suspended</option></select></div><div class="field"><label>Export current page</label><button type="button" id="export-partners" class="secondary-button">Download page CSV</button></div></div><div class="admin-table-wrap"><table class="admin-table"><thead><tr><th>Partner</th><th>Status</th><th>Joined</th><th>Action</th></tr></thead><tbody id="partner-rows">${renderPartnerRows()}</tbody></table></div>${pager("partners",data.pagination?.partners)}<p class="muted small">Search and status filters apply to the current page. Use Previous/Next to browse older partners.</p>`:`<div class="admin-empty">No partner profiles yet.</div>`}</section>
${data.capabilities?.product_management===true ? `<section class="panel admin-panel"><h2>Product catalogue</h2><p>Create a product for the selected tenant. SKU uniqueness and tenant authorization are enforced server-side and every creation is audited.</p><form id="product-create" class="admin-form"><div class="field"><label for="product-sku">SKU / product code</label><input id="product-sku" name="sku" required minlength="1" maxlength="64" pattern="[A-Za-z0-9][A-Za-z0-9._/-]*" placeholder="e.g. TOMATO-HYB-10G"></div><div class="field"><label for="product-name">Product name</label><input id="product-name" name="name" required minlength="2" maxlength="160" placeholder="Hybrid Tomato Seed"></div><div class="field"><label for="product-pack-size">Pack size (optional)</label><input id="product-pack-size" name="pack_size" maxlength="80" placeholder="10 g"></div><button class="primary-button wide-field" type="submit">Create product</button><p id="product-create-status" class="history-sub wide-field" role="status" aria-live="polite"></p></form><div class="divider"></div><h3>Existing products</h3>${data.products.length?data.products.map(p=>`<div class="history-item"><div><div class="history-title">${esc(p.name)} · ${esc(p.sku)}</div><div class="history-sub">${esc(p.pack_size||"Pack size not set")} · ${p.active?"Active":"Inactive"}</div></div><div class="admin-actions"><button type="button" class="secondary-button" data-product-edit="${esc(p.id)}" data-name="${esc(p.name)}" data-pack-size="${esc(p.pack_size||"")}">Edit details</button><button type="button" class="${p.active?"danger-button":"secondary-button"}" data-product-status="${esc(p.id)}" data-active="${p.active?"false":"true"}">${p.active?"Deactivate":"Reactivate"}</button></div></div>`).join(""):"<div class=\"admin-empty\">No products yet.</div>"}</section>` : ""}
<div class="admin-columns"><section class="panel admin-panel"><h2>Issue QR codes</h2><p>Tokens are returned once. Secure the downloaded CSV and use it only for approved packaging.</p><form id="issue" class="admin-form"><div class="field wide-field"><label>Active campaign</label><select name="campaign" required><option value="">Select campaign</option>${data.campaigns.filter(c=>c.status==="active").map(c=>`<option value="${esc(c.id)}">${esc(c.name)}</option>`).join("")}</select></div><div class="field wide-field"><label>Product</label><select name="product" required><option value="">Select product</option>${data.products.filter(p=>p.active).map(p=>`<option value="${esc(p.id)}">${esc(p.name)} · ${esc(p.sku)}</option>`).join("")}</select>${pager("products",data.pagination?.products)}</div><div class="field"><label>Count (1–1000)</label><input name="count" type="number" min="1" max="1000" value="25" required></div><div class="field"><label>Points per code</label><input name="points" type="number" min="1" max="1000000" value="10" required></div><div class="field wide-field"><label>Eligible partner</label><select name="role"><option value="farmer">Farmer</option><option value="retailer">Retailer</option><option value="distributor">Distributor</option></select></div><button class="primary-button wide-field" ${!data.campaigns.some(c=>c.status==="active")||!data.products.some(p=>p.active)?"disabled":""}>Generate one-time codes</button></form>${!data.campaigns.some(c=>c.status==="active")?`<div class="alert warn">No active campaign. The demo campaign is paused intentionally; approve a real campaign before issuing production codes.</div>`:""}</section>
<section class="panel admin-panel"><h2>QR batches</h2><p>Revocation disables unclaimed codes; it does not reverse claims already posted.</p>${(data.pagination?.batches?.total??data.batches.length)>0?data.batches.map(b=>`<div class="history-item"><div><div class="history-title">${esc(b.id.slice(0,8))}… · ${esc(b.requested_count)} codes</div><div class="history-sub">${esc(b.points_value)} points each · ${badge(b.status)}</div></div>${b.status==="issued"?`<button class="danger-button" data-revoke="${esc(b.id)}">Revoke</button>`:""}</div>`).join(""):`<div class="admin-empty">No QR batches issued yet.</div>`}${pager("batches",data.pagination?.batches)}</section></div>
<div class="admin-columns"><section class="panel admin-panel"><h2>Campaign point valuation</h2><p class="muted small">A campaign budget is measured in currency minor units (INR uses paise). Set the value of one point explicitly. Active budgeted campaigns lock this value until they are paused.</p><p class="history-sub">Current valuation: <strong>${data.metrics?.point_value_minor_units ? esc(data.metrics.point_value_minor_units) + " " + esc(data.metrics.point_value_currency) + " minor units per point" : "Not configured"}</strong></p><form id="point-value-form" class="admin-form"><div class="field"><label for="point-value-minor-units">Minor units per point</label><input id="point-value-minor-units" name="point_value_minor_units" type="number" min="1" max="1000000" step="1" required value="${data.metrics?.point_value_minor_units ? esc(data.metrics.point_value_minor_units) : ""}" placeholder="Enter approved valuation"></div><div class="field"><label for="point-value-currency">Currency</label><select id="point-value-currency" name="point_value_currency" required><option value="INR" ${(data.metrics?.point_value_currency||"INR")==="INR"?"selected":""}>INR — Indian Rupee (paise)</option><option value="USD" ${data.metrics?.point_value_currency==="USD"?"selected":""}>USD — US Dollar (cents)</option><option value="EUR" ${data.metrics?.point_value_currency==="EUR"?"selected":""}>EUR — Euro (minor units)</option><option value="GBP" ${data.metrics?.point_value_currency==="GBP"?"selected":""}>GBP — Pound Sterling (pence)</option></select></div><div class="field"><label>Save valuation</label><button type="submit" class="primary-button wide">Save point value</button></div><p id="point-value-status" class="history-sub wide-field" role="status" aria-live="polite"></p></form></section></div>
<div class="admin-columns"><section class="panel admin-panel"><h2>Campaign operations</h2><p>Create campaigns in draft first. Activation is explicit and only allowed inside the configured date window. Demo campaigns are permanently blocked from activation.</p><form id="campaign-create" class="admin-form"><div class="field wide-field"><label>Campaign name</label><input name="name" required minlength="3" maxlength="120" placeholder="e.g. Kharif pack rewards"></div><div class="field"><label>Starts at (optional)</label><input name="starts_at" type="datetime-local"></div><div class="field"><label>Ends at (optional)</label><input name="ends_at" type="datetime-local"></div><div class="field wide-field"><label>Budget (₹, optional value; 0 means not budgeted)</label><input name="budget" type="number" min="0" step="0.01" value="0" required></div><button class="primary-button wide-field">Create draft campaign</button></form><div class="divider"></div>${data.campaigns.map(c=>`<div class="history-item"><div><div class="history-title">${esc(c.name)} ${c.rules?.demo?'<span class="admin-badge warn">DEMO · NOT FOR PRODUCTION</span>':""}</div><div class="history-sub">${esc(c.starts_at?new Date(c.starts_at).toLocaleString():"No start")} – ${esc(c.ends_at?new Date(c.ends_at).toLocaleString():"No end")} · Budget ${esc(c.currency||"INR")} ${(Number(c.budget_minor_units||0)/100).toLocaleString("en-IN",{minimumFractionDigits:2,maximumFractionDigits:2})}</div></div><div class="admin-actions">${badge(c.status)}${c.status==="active"?`<button type="button" class="danger-button" data-campaign-status="${esc(c.id)}" data-status="paused">Pause</button>`:["draft","scheduled","paused"].includes(c.status)&&!c.rules?.demo?`<button type="button" class="secondary-button" data-campaign-status="${esc(c.id)}" data-status="active">Activate</button>`:""}${["draft","paused"].includes(c.status)?`<button type="button" class="danger-button" data-campaign-status="${esc(c.id)}" data-status="archived">Archive</button>`:""}</div></div>`).join("")||"No campaigns."}${pager("campaigns",data.pagination?.campaigns)}</section><section class="panel admin-panel"><div class="row admin-section-title"><h2>Redemption queue</h2><button type="button" id="export-redemptions" class="secondary-button">Export current page</button></div><p>Fulfil approved requests or cancel with a reason. Cancellations refund points and restore finite reward stock exactly once.</p>${data.redemptions.map(r=>`<div class="history-item"><div><div class="history-title">${esc(r.reward_name)} · ${esc(r.points_cost)} points</div><div class="history-sub">${esc(r.partner_name)} ${r.partner_phone?"· "+esc(r.partner_phone):""} · ${esc(new Date(r.created_at).toLocaleString())}</div>${r.reward_is_demo?'<div class="small muted">Demo reward record</div>':""}</div><div class="admin-actions admin-redemption-actions">${badge(r.status)}${["reserved","approved"].includes(r.status)?`<button class="secondary-button" data-resolve="${esc(r.id)}" data-status="fulfilled">Mark fulfilled</button><button class="danger-button" data-resolve="${esc(r.id)}" data-status="cancelled">Cancel &amp; refund</button>`:""}</div></div>`).join("")||"No redemption requests."}${pager("redemptions",data.pagination?.redemptions)}</section></div>${data.capabilities?.audit_log_viewer?`<section class="panel admin-panel"><h2>Recent audit activity</h2><p>Tenant-scoped operational history. Sensitive before/after payloads are not exposed in this view.</p>${(data.audit_logs||[]).length?data.audit_logs.map(log=>`<div class="history-item"><div><div class="history-title">${esc(log.action)} · ${esc(log.entity_type)}</div><div class="history-sub">${esc(new Date(log.created_at).toLocaleString())} · Actor ${esc(String(log.actor_user_id||"system").slice(0,8))} · Record ${esc(String(log.entity_id||"—").slice(0,8))}</div>${log.reason?`<div class="small muted">Reason: ${esc(log.reason)}</div>`:""}</div></div>`).join(""):"<div class=\"admin-empty\">No audit events recorded for this tenant yet.</div>"}${pager("audit",data.pagination?.audit)}</section>`:""}`;
const adminSections=[...root.querySelectorAll(".admin-panel")];
const sectionNav=document.createElement("nav");
sectionNav.className="admin-section-nav";
sectionNav.setAttribute("aria-label","Admin sections");
const sectionLinks=adminSections.map(section=>{
  const heading=section.querySelector("h2");
  if(!heading)return "";
  const label=heading.textContent.trim();
  const slug=label.toLowerCase().normalize("NFKD").replace(/[\u0300-\u036f]/g,"").replace(/[^a-z0-9]+/g,"-").replace(/^-|-$/g,"");
  const id="admin-section-"+slug;
  section.id=id;
  return '<a href="#'+id+'">'+esc(label)+'</a>';
}).filter(Boolean);
if(sectionLinks.length){
  sectionNav.innerHTML='<span class="admin-section-nav-label">Jump to section</span>'+sectionLinks.join("");
  root.querySelector(".admin-title")?.insertAdjacentElement("afterend",sectionNav);
}
document.getElementById("refresh").addEventListener("click",refresh);
document.getElementById("download-qr-export")?.addEventListener("click",downloadPendingQrExport);
document.getElementById("clear-qr-export")?.addEventListener("click",()=>{
  if(!pendingQrExport)return;
  const complete=pendingQrExport.complete===true;
  const prompt=complete
    ?"Confirm you have securely saved and verified the downloaded QR CSV. The one-time tokens will be cleared from this browser session."
    :"This export is incomplete. Clearing it is irreversible and missing tokens cannot be recovered. Continue only if you have recorded the batch ID for reconciliation.";
  if(!confirm(prompt))return;
  pendingQrExport=null;draw();
});root.querySelector("#admin-tenant-select")?.addEventListener("change",async event=>{selectedTenantSlug=event.currentTarget.value;for(const key of Object.keys(pages))pages[key]=0;partnerQuery="";partnerStatus="all";await refresh()});
root.querySelectorAll("[data-product-edit]").forEach(button=>button.addEventListener("click",async()=>{
  const currentName=button.dataset.name||"";
  const currentPack=button.dataset.packSize||"";
  const name=prompt("Product name (SKU remains unchanged):",currentName);
  if(name===null)return;
  const pack_size=prompt("Pack size (leave blank to clear):",currentPack);
  if(pack_size===null)return;
  if(name.trim().length<2||name.trim().length>160||pack_size.trim().length>80)return toast("Check the product name and pack size.",true);
  if(!confirm("Save product details? The change will be recorded in the audit log."))return;
  button.disabled=true;
  try{
    await call("update_product",{product_id:button.dataset.productEdit,name:name.trim(),pack_size:pack_size.trim()});
    toast("Product details updated.");
    await refresh();
  }catch(error){toast(String(error?.message||error),true)}
  finally{if(button.isConnected)button.disabled=false}
}));
root.querySelectorAll("[data-product-status]").forEach(button=>button.addEventListener("click",async()=>{
  const active=button.dataset.active==="true";
  const reason=active?"":(prompt("Reason for deactivating this product (minimum 5 characters):")||"");
  if(!active&&reason.trim().length<5)return toast("A reason is required.",true);
  if(!confirm(active?"Reactivate this product for future use?":"Deactivate this product? Existing QR history will be retained."))return;
  button.disabled=true;
  try{
    await call("set_product_status",{product_id:button.dataset.productStatus,active,reason});
    toast(active?"Product reactivated.":"Product deactivated.");
    await refresh();
  }catch(error){toast(String(error?.message||error),true)}
  finally{if(button.isConnected)button.disabled=false}
}));
root.querySelector("#product-create")?.addEventListener("submit",async event=>{
  event.preventDefault();
  const form=event.currentTarget;
  const button=form.querySelector('button[type="submit"]');
  const status=form.querySelector("#product-create-status");
  const fd=new FormData(form);
  const sku=String(fd.get("sku")||"").trim().toUpperCase();
  const name=String(fd.get("name")||"").trim();
  const pack_size=String(fd.get("pack_size")||"").trim();
  if(!/^[A-Z0-9][A-Z0-9._/-]{0,63}$/.test(sku)||name.length<2||name.length>160||pack_size.length>80){
    if(status)status.textContent="Check the SKU, product name and pack size.";
    return;
  }
  button.disabled=true;
  if(status)status.textContent="Creating product…";
  try{
    await call("create_product",{sku,name,pack_size});
    if(status)status.textContent="Product created and audit recorded.";
    toast("Product created.");
    pages.products=0;
    await refresh();
  }catch(error){
    const message=String(error?.message||error);
    if(status)status.textContent=message==="sku_exists"?"That SKU already exists in this tenant.":message;
    toast(message==="sku_exists"?"That SKU already exists in this tenant.":message,true);
  }finally{
    if(form.isConnected)button.disabled=false;
  }
});
root.querySelector("#point-value-form")?.addEventListener("submit",async event=>{event.preventDefault();const form=event.currentTarget;const button=form.querySelector('button[type="submit"]');const status=form.querySelector("#point-value-status");const fd=new FormData(form);const point_value_minor_units=Number(fd.get("point_value_minor_units"));const point_value_currency=String(fd.get("point_value_currency")||"").trim().toUpperCase();if(!Number.isSafeInteger(point_value_minor_units)||point_value_minor_units<1||point_value_minor_units>1000000||! /^[A-Z]{3}$/.test(point_value_currency)){if(status)status.textContent="Enter a valid positive point value and currency.";return;}button.disabled=true;if(status)status.textContent="Saving…";try{const result=await call("set_point_value",{point_value_minor_units,point_value_currency});if(!result?.ok)throw new Error(result?.error||"point_value_save_failed");if(status)status.textContent="Point valuation saved.";toast("Point valuation saved.");await refresh();}catch(error){const message=String(error?.message||error);if(status)status.textContent=message.includes("pause_budgeted_campaigns_before_changing_point_value")?"Pause active budgeted campaigns before changing the point value.":message.includes("currency_must_match")?"Currency must match every active budgeted campaign.":message;toast(message,"error");}finally{if(form.isConnected)button.disabled=false;}});
root.querySelectorAll("[data-page-group]").forEach(button=>button.addEventListener("click",()=>{const group=button.dataset.pageGroup,info=data?.pagination?.[group];if(!info)return;const maxPage=Math.max(0,Math.ceil(Number(info.total||0)/Math.max(1,Number(info.page_size||1)))-1);pages[group]=Math.max(0,Math.min(maxPage,pages[group]+Number(button.dataset.pageDir||0)));void refresh()}));
const partnerSearch=document.getElementById("partner-search"),partnerStatusSelect=document.getElementById("partner-status");
const updatePartnerRows=()=>{const body=document.getElementById("partner-rows");if(body)body.innerHTML=renderPartnerRows();root.querySelectorAll("[data-verify]").forEach(b=>b.addEventListener("click",verifyHandler));};
if(partnerSearch){
  partnerSearch.addEventListener("input",()=>{partnerQuery=partnerSearch.value;updatePartnerRows()});
  const submitPartnerSearch=async()=>{partnerQuery=partnerSearch.value.trim().slice(0,80);pages.partners=0;await refresh()};
  document.getElementById("partner-search-submit")?.addEventListener("click",submitPartnerSearch);
  partnerSearch.addEventListener("keydown",event=>{if(event.key==="Enter"){event.preventDefault();void submitPartnerSearch()}});
}
if(partnerStatusSelect)partnerStatusSelect.addEventListener("change",async()=>{partnerStatus=partnerStatusSelect.value;pages.partners=0;await refresh()});
const exportPartners=document.getElementById("export-partners");
if(exportPartners)exportPartners.addEventListener("click",async()=>{
  const rows=data.partners.filter(p=>{const q=partnerQuery.trim().toLowerCase();return (!q||[p.display_name,p.phone_e164,p.role,p.id].some(v=>String(v||"").toLowerCase().includes(q)))&&(partnerStatus==="all"||(partnerStatus==="pending"?["pending","unverified"].includes(p.verification_status):p.verification_status===partnerStatus))});
  exportPartners.disabled=true;
  try{
    await call("admin_record_export",{export_type:"partners",row_count:rows.length,page:pages.partners});
    downloadCsv("growta-partners-"+new Date().toISOString().slice(0,10)+".csv",[["partner_id","display_name","phone","role","verification_status","created_at"],...rows.map(p=>[p.id,p.display_name,p.phone_e164,p.role,p.verification_status,p.created_at])]);
    toast("Current-page partner CSV downloaded; export request audited.");
  }catch(error){toast("Export was not started because audit logging failed: "+String(error?.message||error),true)}
  finally{if(exportPartners.isConnected)exportPartners.disabled=false}
});

const verifyHandler=async b=>{let reason=null;if(b.dataset.status!=="verified"){reason=prompt("Reason (minimum 5 characters):")||"";if(reason.trim().length<5)return toast("A reason is required.",true)}if(!confirm("Change partner status to "+b.dataset.status+"?"))return;try{await call("verify_partner",{partner_id:b.dataset.verify,status:b.dataset.status,reason});toast("Partner status updated.");await refresh()}catch(e){toast(e.message,true)}};
root.querySelectorAll("[data-verify]").forEach(b=>b.addEventListener("click",()=>verifyHandler(b)));
const exportRedemptions=document.getElementById("export-redemptions");
if(exportRedemptions)exportRedemptions.addEventListener("click",async()=>{
  exportRedemptions.disabled=true;
  try{
    await call("admin_record_export",{export_type:"redemptions",row_count:data.redemptions.length,page:pages.redemptions});
    downloadCsv("growta-redemptions-"+new Date().toISOString().slice(0,10)+".csv",[["redemption_id","partner","phone","reward","points_cost","status","created_at","fulfilled_at"],...data.redemptions.map(r=>[r.id,r.partner_name,r.partner_phone,r.reward_name,r.points_cost,r.status,r.created_at,r.fulfilled_at])]);
    toast("Current-page redemption CSV downloaded; export request audited.");
  }catch(error){toast("Export was not started because audit logging failed: "+String(error?.message||error),true)}
  finally{if(exportRedemptions.isConnected)exportRedemptions.disabled=false}
});
root.querySelectorAll("[data-revoke]").forEach(b=>b.addEventListener("click",async()=>{const reason=prompt("Reason for revocation (minimum 5 characters):")||"";if(reason.trim().length<5)return toast("A reason is required.",true);if(!confirm("Revoke all unclaimed codes in this batch?"))return;try{await call("revoke_qr_batch",{batch_id:b.dataset.revoke,reason});toast("Batch revoked.");await refresh()}catch(e){toast(e.message,true)}}));
root.querySelectorAll("[data-resolve]").forEach(b=>b.addEventListener("click",async()=>{
  const status=b.dataset.status;
  let reason="";
  if(status!=="fulfilled"){reason=prompt("Reason for cancellation and refund (minimum 5 characters):")||"";if(reason.trim().length<5)return toast("A reason is required.",true)}
  if(!confirm(status==="fulfilled"?"Mark this redemption as fulfilled? Points will remain spent.":"Cancel this redemption, refund points, and restore reward stock?"))return;
  try{await call("resolve_redemption",{redemption_id:b.dataset.resolve,status,reason});toast(status==="fulfilled"?"Redemption marked fulfilled.":"Redemption cancelled and points refunded.");await refresh()}catch(e){toast(e.message,true)}
}));
root.querySelectorAll("[data-campaign-status]").forEach(b=>b.addEventListener("click",async()=>{
  const status=b.dataset.status;
  let reason="";
  if(status!=="active"){reason=prompt("Reason for "+status+" (minimum 5 characters):")||"";if(reason.trim().length<5)return toast("A reason is required.",true)}
  if(!confirm(status==="active"?"Activate this campaign? QR claims will become eligible within the campaign dates.":status==="paused"?"Pause this campaign? New claims should stop.":"Archive this draft/paused campaign?"))return;
  try{await call("set_campaign_status",{campaign_id:b.dataset.campaignStatus,status,reason});toast("Campaign status updated.");await refresh()}catch(e){toast(e.message,true)}
}));
document.getElementById("campaign-create").addEventListener("submit",async e=>{
  e.preventDefault();
  const f=new FormData(e.currentTarget),name=String(f.get("name")||"").trim(),budget=Number(f.get("budget"));
  if(!Number.isFinite(budget)||budget<0||budget>10000000000)return toast("Enter a valid budget.",true);
  const starts=String(f.get("starts_at")||""),ends=String(f.get("ends_at")||"");
  if(starts&&ends&&new Date(ends)<=new Date(starts))return toast("End time must be after start time.",true);
  if(!confirm("Create this campaign as a draft? It will not accept QR claims until activated."))return;
  try{await call("create_campaign",{name,starts_at:starts?new Date(starts).toISOString():null,ends_at:ends?new Date(ends).toISOString():null,budget_minor_units:Math.round(budget*100)});toast("Draft campaign created.");await refresh()}catch(e){toast(e.message,true)}
});
document.getElementById("issue").addEventListener("submit",async e=>{
  e.preventDefault();
  if(pendingQrExport){toast("Secure or explicitly clear the previous one-time QR export before issuing another batch.",true);return;}
  const f=new FormData(e.currentTarget),count=Number(f.get("count")),points_value=Number(f.get("points"));
  if(!confirm("Issue "+count+" unique tokens worth "+points_value+" points each?"))return;
  const submit=e.currentTarget.querySelector("button[type=submit]");
  if(submit)submit.disabled=true;
  try{
    const r=await call("issue_qr_batch",{campaign_id:String(f.get("campaign")),product_id:String(f.get("product")),count,points_value,entitlement_role:String(f.get("role"))});
    const codes=Array.isArray(r.codes)?r.codes:[];
    const complete=codes.length===count&&codes.every(c=>c&&typeof c.qr_id==="string"&&typeof c.token==="string"&&c.token.length>=16&&typeof c.qr_payload==="string"&&c.qr_payload.length>0);
    pendingQrExport={batch_id:String(r.batch_id||"unknown"),tenant_slug:selectedTenantSlug,expected_count:count,codes,complete};
    if(!r.batch_id||!codes.length){toast("Batch response did not include recoverable QR tokens. Do not issue a replacement batch; reconcile batch "+String(r.batch_id||"unknown")+" with an administrator.",true);await refresh();return;}
    downloadPendingQrExport();
    if(!complete)toast("QR export response is incomplete or invalid ("+codes.length+" of "+count+" codes). Do not reissue; reconcile batch "+r.batch_id+".",true);
    else toast("Batch issued. Verify and securely store the CSV; the one-time export remains available for retry.");
    await refresh();
  }catch(e){toast(e.message,true)}
  finally{if(submit&&submit.isConnected)submit.disabled=false}
});
}
signout.addEventListener("click",async()=>{pendingQrExport=null;await db.auth.signOut();loginView()});
const {data:{session}}=await db.auth.getSession();if(session)await refresh();else loginView();

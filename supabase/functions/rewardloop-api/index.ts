import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const PUBLIC_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ?? "";
const TENANT_SLUG = "growta-rewardloop";
// Production is the only built-in browser origin. Add preview/custom origins
// explicitly through ALLOWED_ORIGINS in Edge Function secrets.
const DEFAULT_ALLOWED_ORIGINS = ["https://bigagri.vercel.app"];
const CONFIGURED_ALLOWED_ORIGINS = (Deno.env.get("ALLOWED_ORIGINS") ?? "")
  .split(",").map((origin) => origin.trim()).filter(Boolean);
const ALLOWED_ORIGINS = new Set([
  ...DEFAULT_ALLOWED_ORIGINS,
  ...CONFIGURED_ALLOWED_ORIGINS,
]);
const corsHeaders = {
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
};

function respond(status: number, payload: Record<string, unknown>, origin?: string | null) {
  const headers = new Headers(corsHeaders);
  if (origin && ALLOWED_ORIGINS.has(origin)) headers.set("Access-Control-Allow-Origin", origin);
  return new Response(JSON.stringify(payload), { status, headers });
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin");
  const originAllowed = !origin || ALLOWED_ORIGINS.has(origin);
  const reply = (status: number, payload: Record<string, unknown>) => respond(status, payload, origin);
  if (!originAllowed) return new Response(null, { status: 403, headers: { "Vary": "Origin", "Cache-Control": "no-store" } });
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: { ...corsHeaders, ...(origin ? { "Access-Control-Allow-Origin": origin } : {}) } });
  if (req.method !== "POST") return reply(405, { ok: false, error: "method_not_allowed" });

  try {
    if (!SUPABASE_URL || !SERVICE_ROLE_KEY || !PUBLIC_KEY) {
      return reply(500, { ok: false, error: "server_configuration_missing" });
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) return reply(401, { ok: false, error: "authentication_required" });

    // Verify the caller's JWT with Supabase Auth. Never accept a user ID from request data.
    const userClient = createClient(SUPABASE_URL, PUBLIC_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userError } = await userClient.auth.getUser();
    const user = userData?.user;
    if (userError || !user) return reply(401, { ok: false, error: "invalid_session" });

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const body = await req.json().catch(() => ({}));
    const action = typeof body.action === "string" ? body.action : "";

    // List only active tenants for which this authenticated user has an active
    // tenant-admin membership. Client-provided tenant IDs/slugs never grant access.
    if (action === "admin_tenants") {
      const { data: memberships, error: membershipsError } = await admin
        .from("tenant_memberships")
        .select("tenant_id,role")
        .eq("user_id", user.id)
        .eq("status", "active")
        .in("role", ["brand_admin", "super_admin"]);
      if (membershipsError) return reply(500, { ok: false, error: "admin_tenant_context_failed" });

      const roleByTenant = new Map<string, string>();
      for (const membership of memberships || []) {
        if (!roleByTenant.has(membership.tenant_id)) roleByTenant.set(membership.tenant_id, membership.role);
      }
      const tenantIds = [...roleByTenant.keys()];
      if (!tenantIds.length) return reply(200, { ok: true, tenants: [] });

      const { data: tenants, error: tenantsError } = await admin
        .from("tenants")
        .select("id,name,slug,status")
        .in("id", tenantIds)
        .eq("status", "active")
        .order("name", { ascending: true });
      if (tenantsError) return reply(500, { ok: false, error: "admin_tenant_context_failed" });
      return reply(200, {
        ok: true,
        tenants: (tenants || []).map((tenant) => ({
          ...tenant,
          role: roleByTenant.get(tenant.id) || "brand_admin",
        })),
      });
    }

    if (action === "profile") {
      const requestedTenantSlug = typeof body.tenant_slug === "string" ? body.tenant_slug.trim() : TENANT_SLUG;
      if (!/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(requestedTenantSlug)) {
        return reply(400, { ok: false, error: "tenant_slug_invalid" });
      }
      const displayName = typeof body.display_name === "string" ? body.display_name.trim() : "";
      const phone = typeof body.phone_e164 === "string" ? body.phone_e164.trim() : "";
      const locale = body.preferred_locale === "en-IN" ? "en-IN" : "hi-IN";
      if (displayName.length < 2 || displayName.length > 160) {
        return reply(400, { ok: false, error: "display_name_invalid" });
      }
      if (phone && !/^\+[1-9]\d{7,14}$/.test(phone)) {
        return reply(400, { ok: false, error: "phone_must_be_e164" });
      }

      const { data: tenant, error: tenantError } = await admin
        .from("tenants").select("id,status,default_locale,public_catalog_enabled").eq("slug", requestedTenantSlug).maybeSingle();
      if (tenantError || !tenant || tenant.status !== "active" || tenant.public_catalog_enabled !== true) {
        return reply(503, { ok: false, error: "tenant_unavailable" });
      }

      const { data: existing, error: existingError } = await admin
        .from("partners").select("id,role,display_name,phone_e164,preferred_locale,verification_status")
        .eq("tenant_id", tenant.id).eq("user_id", user.id).maybeSingle();
      if (existingError) return reply(500, { ok: false, error: "profile_lookup_failed" });

      if (existing) {
        const { data: updated, error: updateError } = await admin.from("partners")
          .update({ display_name: displayName, phone_e164: phone || null, preferred_locale: locale, updated_at: new Date().toISOString() })
          .eq("id", existing.id)
          .select("id,role,display_name,phone_e164,preferred_locale,verification_status").single();
        if (updateError) return reply(500, { ok: false, error: "profile_update_failed" });
        return reply(200, { ok: true, profile: updated });
      }

      const { data: created, error: createError } = await admin.from("partners").insert({
        tenant_id: tenant.id,
        user_id: user.id,
        role: "farmer",
        display_name: displayName,
        phone_e164: phone || null,
        preferred_locale: locale,
        verification_status: "pending",
      }).select("id,role,display_name,phone_e164,preferred_locale,verification_status").single();

      if (createError) {
        // A concurrent onboarding request may have created the profile first.
        const { data: raced } = await admin.from("partners")
          .select("id,role,display_name,phone_e164,preferred_locale,verification_status")
          .eq("tenant_id", tenant.id).eq("user_id", user.id).maybeSingle();
        if (raced) return reply(200, { ok: true, profile: raced });
        return reply(500, { ok: false, error: "profile_create_failed" });
      }
      return reply(200, { ok: true, profile: created });
    }

    if (action === "claim") {
      const token = typeof body.token === "string" ? body.token.trim() : "";
      const requestId = typeof body.request_id === "string" ? body.request_id : "";
      if (token.length < 16 || token.length > 512) return reply(400, { ok: false, error: "invalid_code" });
      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(requestId)) {
        return reply(400, { ok: false, error: "invalid_request_id" });
      }
      const { data, error } = await admin.rpc("rewardloop_claim_qr_internal", {
        p_actor_user_id: user.id,
        p_token: token,
        p_request_id: requestId,
        p_app_version: "growta-rewardloop-pwa/1.0.0",
        p_device_ref_hash: null,
      });
      if (error) return reply(500, { ok: false, error: "claim_processing_failed" });
      return reply(200, data && typeof data === "object" ? data : { ok: false, error: "unexpected_claim_response" });
    }

    if (action === "redeem") {
      const rewardId = typeof body.reward_id === "string" ? body.reward_id : "";
      const requestKey = typeof body.request_key === "string" ? body.request_key : "";
      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(rewardId)) {
        return reply(400, { ok: false, error: "invalid_reward" });
      }
      if (requestKey.length < 8 || requestKey.length > 160) return reply(400, { ok: false, error: "invalid_request_key" });
      const { data, error } = await admin.rpc("rewardloop_redeem_internal", {
        p_actor_user_id: user.id,
        p_reward_id: rewardId,
        p_request_key: requestKey,
      });
      if (error) return reply(500, { ok: false, error: "redemption_processing_failed" });
      return reply(200, data && typeof data === "object" ? data : { ok: false, error: "unexpected_redemption_response" });
    }

    if (["admin_dashboard", "admin_audit_logs", "verify_partner", "issue_qr_batch", "revoke_qr_batch", "resolve_redemption", "set_campaign_status", "create_campaign", "set_point_value", "create_product", "set_product_status", "update_product"].includes(action)) {
      // Keep legacy callers working on the original tenant, but allow an explicit
      // tenant context only after checking active membership below.
      const requestedTenantSlug = typeof body.tenant_slug === "string" ? body.tenant_slug.trim() : TENANT_SLUG;
      if (!/^[a-z0-9][a-z0-9-]{1,62}$/.test(requestedTenantSlug)) {
        return reply(400, { ok: false, error: "invalid_tenant_context" });
      }
      const { data: tenant, error: tenantError } = await admin.from("tenants").select("id,name,slug,status").eq("slug", requestedTenantSlug).maybeSingle();
      if (tenantError || !tenant || tenant.status !== "active") return reply(503, { ok: false, error: "tenant_unavailable" });
      const { data: membership, error: membershipError } = await admin.from("tenant_memberships").select("role,status")
        .eq("tenant_id", tenant.id).eq("user_id", user.id).eq("status", "active").in("role", ["brand_admin", "super_admin"]).maybeSingle();
      if (membershipError) return reply(500, { ok: false, error: "admin_authorization_check_failed" });
      if (!membership) return reply(403, { ok: false, error: "admin_access_required" });

      if (action === "admin_audit_logs") {
        const rawPage = Number(body.audit_page ?? 0);
        if (!Number.isSafeInteger(rawPage) || rawPage < 0 || rawPage > 100000) {
          return reply(400, { ok: false, error: "invalid_audit_page" });
        }
        const pageSize = 20;
        const { data: rows, error: auditError, count } = await admin
          .from("audit_logs")
          .select("id,actor_user_id,action,entity_type,entity_id,request_id,reason,created_at", { count: "exact" })
          .eq("tenant_id", tenant.id)
          .order("created_at", { ascending: false })
          .order("id", { ascending: false })
          .range(rawPage * pageSize, (rawPage + 1) * pageSize - 1);
        if (auditError) return reply(500, { ok: false, error: "admin_audit_logs_load_failed" });
        return reply(200, {
          ok: true,
          logs: rows || [],
          pagination: { page: rawPage, page_size: pageSize, total: count || 0 },
        });
      }

      if (action === "set_point_value") {
        const pointValue = Number(body.point_value_minor_units);
        const currency = String(body.point_value_currency || "").trim().toUpperCase();
        if (!Number.isSafeInteger(pointValue) || pointValue < 1 || pointValue > 1000000 || !/^[A-Z]{3}$/.test(currency)) {
          return reply(400, { ok: false, error: "invalid_point_value" });
        }
        const { data, error } = await admin.rpc("rewardloop_set_point_value_internal", {
          p_actor_user_id: user.id,
          p_tenant_id: tenant.id,
          p_point_value_minor_units: pointValue,
          p_point_value_currency: currency,
        });
        if (error) return reply(500, { ok: false, error: "point_value_save_failed" });
        if (!data || data.ok !== true) {
          return reply(data?.error === "forbidden" ? 403 : 400, {
            ok: false, error: data?.error || "point_value_save_failed"
          });
        }
        return reply(200, data);
      }

      if (action === "update_product") {
        const productId = typeof body.product_id === "string" ? body.product_id : "";
        const name = typeof body.name === "string" ? body.name.trim() : "";
        const packSize = typeof body.pack_size === "string" ? body.pack_size.trim() : "";
        if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(productId) ||
            name.length < 2 || name.length > 160 || packSize.length > 80) {
          return reply(400, { ok: false, error: "invalid_product_details" });
        }
        const { data, error } = await admin.rpc("rewardloop_update_product_internal", {
          p_actor_user_id: user.id,
          p_tenant_id: tenant.id,
          p_product_id: productId,
          p_name: name,
          p_pack_size: packSize || null,
        });
        if (error) return reply(500, { ok: false, error: "product_update_failed" });
        if (!data || data.ok !== true) {
          const status = data?.error === "forbidden" ? 403 : data?.error === "product_not_found" ? 404 : 400;
          return reply(status, { ok: false, error: data?.error || "product_update_failed" });
        }
        return reply(200, data);
      }

      if (action === "set_product_status") {
        const productId = typeof body.product_id === "string" ? body.product_id : "";
        const active = body.active;
        const reason = typeof body.reason === "string" ? body.reason.trim().slice(0, 500) : "";
        if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(productId) ||
            typeof active !== "boolean" || (!active && reason.length < 5)) {
          return reply(400, { ok: false, error: "invalid_product_status_request" });
        }
        const { data, error } = await admin.rpc("rewardloop_set_product_status_internal", {
          p_actor_user_id: user.id,
          p_tenant_id: tenant.id,
          p_product_id: productId,
          p_active: active,
          p_reason: reason || null,
        });
        if (error) return reply(500, { ok: false, error: "product_status_update_failed" });
        if (!data || data.ok !== true) {
          const status = data?.error === "forbidden" ? 403 : data?.error === "product_not_found" ? 404 : 400;
          return reply(status, { ok: false, error: data?.error || "product_status_update_failed" });
        }
        return reply(200, data);
      }

      if (action === "create_product") {
        const sku = typeof body.sku === "string" ? body.sku.trim().toUpperCase() : "";
        const name = typeof body.name === "string" ? body.name.trim() : "";
        const packSize = typeof body.pack_size === "string" ? body.pack_size.trim() : "";
        if (!/^[A-Z0-9][A-Z0-9._/-]{0,63}$/.test(sku) ||
            name.length < 2 || name.length > 160 || packSize.length > 80) {
          return reply(400, { ok: false, error: "invalid_product_details" });
        }
        const { data, error } = await admin.rpc("rewardloop_create_product_internal", {
          p_actor_user_id: user.id,
          p_tenant_id: tenant.id,
          p_sku: sku,
          p_name: name,
          p_pack_size: packSize || null,
        });
        if (error) return reply(500, { ok: false, error: "product_create_failed" });
        if (!data || data.ok !== true) {
          const status = data?.error === "forbidden" ? 403 : data?.error === "sku_exists" ? 409 : 400;
          return reply(status, { ok: false, error: data?.error || "product_create_failed" });
        }
        return reply(201, data);
      }

      if (action === "admin_dashboard") {
        const pageSpecs = {
          partners: { key: "partners_page", size: 50 },
          campaigns: { key: "campaigns_page", size: 20 },
          products: { key: "products_page", size: 50 },
          batches: { key: "batches_page", size: 20 },
          redemptions: { key: "redemptions_page", size: 20 },
        } as const;

        const pages: Record<keyof typeof pageSpecs, number> = {
          partners: 0, campaigns: 0, products: 0, batches: 0, redemptions: 0,
        };
        for (const [name, spec] of Object.entries(pageSpecs) as [keyof typeof pageSpecs, typeof pageSpecs[keyof typeof pageSpecs]][]) {
          const raw = body[spec.key];
          if (raw === undefined || raw === null || raw === "") continue;
          const value = Number(raw);
          if (!Number.isSafeInteger(value) || value < 0 || value > 10000) {
            return reply(400, { ok: false, error: "invalid_dashboard_page" });
          }
          pages[name] = value;
        }

        const [partners, campaigns, products, batches, redemptions] = await Promise.all([
          admin.from("partners")
            .select("id,display_name,phone_e164,role,verification_status,preferred_locale,created_at", { count: "exact" })
            .eq("tenant_id", tenant.id).order("created_at", { ascending: false }).order("id", { ascending: false })
            .range(pages.partners * pageSpecs.partners.size, (pages.partners + 1) * pageSpecs.partners.size - 1),
          admin.from("campaigns")
            .select("id,name,status,starts_at,ends_at,budget_minor_units,currency,rules,created_at", { count: "exact" })
            .eq("tenant_id", tenant.id).order("created_at", { ascending: false }).order("id", { ascending: false })
            .range(pages.campaigns * pageSpecs.campaigns.size, (pages.campaigns + 1) * pageSpecs.campaigns.size - 1),
          admin.from("products")
            .select("id,sku,name,pack_size,active,created_at", { count: "exact" })
            .eq("tenant_id", tenant.id).order("name").order("id")
            .range(pages.products * pageSpecs.products.size, (pages.products + 1) * pageSpecs.products.size - 1),
          admin.from("qr_issuance_batches")
            .select("id,product_id,campaign_id,requested_count,points_value,entitlement_role,status,created_at,completed_at", { count: "exact" })
            .eq("tenant_id", tenant.id).order("created_at", { ascending: false }).order("id", { ascending: false })
            .range(pages.batches * pageSpecs.batches.size, (pages.batches + 1) * pageSpecs.batches.size - 1),
          admin.from("redemptions")
            .select("id,partner_id,reward_id,points_cost,status,created_at,fulfilled_at", { count: "exact" })
            .eq("tenant_id", tenant.id).order("created_at", { ascending: false }).order("id", { ascending: false })
            .range(pages.redemptions * pageSpecs.redemptions.size, (pages.redemptions + 1) * pageSpecs.redemptions.size - 1),
        ]);
        if ([partners, campaigns, products, batches, redemptions].some(x => x.error)) {
          return reply(500, { ok: false, error: "admin_dashboard_load_failed" });
        }

        const redemptionRows = redemptions.data || [];
        const partnerIds = [...new Set(redemptionRows.map(r => r.partner_id))];
        const rewardIds = [...new Set(redemptionRows.map(r => r.reward_id))];
        const [redemptionPartners, redemptionRewards, metricsResult] = await Promise.all([
          admin.from("partners").select("id,display_name,phone_e164").eq("tenant_id", tenant.id)
            .in("id", partnerIds.length ? partnerIds : ["00000000-0000-0000-0000-000000000000"]),
          admin.from("rewards").select("id,name,name_hi,is_demo").eq("tenant_id", tenant.id)
            .in("id", rewardIds.length ? rewardIds : ["00000000-0000-0000-0000-000000000000"]),
          admin.rpc("rewardloop_admin_dashboard_metrics_internal", {
            p_actor_user_id: user.id,
            p_tenant_id: tenant.id,
          }),
        ]);
        if (redemptionPartners.error || redemptionRewards.error) {
          return reply(500, { ok: false, error: "admin_dashboard_enrichment_failed" });
        }
        if (metricsResult.error || !metricsResult.data || metricsResult.data.ok !== true) {
          return reply(500, { ok: false, error: "admin_dashboard_metrics_failed" });
        }

        const partnerById = new Map((redemptionPartners.data || []).map(p => [p.id, p]));
        const rewardById = new Map((redemptionRewards.data || []).map(r => [r.id, r]));
        const enrichedRedemptions = redemptionRows.map(r => ({
          ...r,
          partner_name: partnerById.get(r.partner_id)?.display_name || "Partner",
          partner_phone: partnerById.get(r.partner_id)?.phone_e164 || "",
          reward_name: rewardById.get(r.reward_id)?.name || "Reward",
          reward_is_demo: rewardById.get(r.reward_id)?.is_demo ?? false,
        }));

        const pagination = Object.fromEntries(
          (Object.keys(pageSpecs) as (keyof typeof pageSpecs)[]).map(name => [
            name,
            {
              page: pages[name],
              page_size: pageSpecs[name].size,
              total: ({
                partners: partners.count,
                campaigns: campaigns.count,
                products: products.count,
                batches: batches.count,
                redemptions: redemptions.count,
              })[name] ?? 0,
            },
          ]),
        );

        return reply(200, {
          ok: true,
          tenant,
          role: membership.role,
          capabilities: { product_management: true, audit_log_viewer: true },
          metrics: metricsResult.data,
          pagination,
          partners: partners.data || [],
          campaigns: campaigns.data || [],
          products: products.data || [],
          batches: batches.data || [],
          redemptions: enrichedRedemptions,
        });
      }
      if (action === "verify_partner") {
        const partnerId = typeof body.partner_id === "string" ? body.partner_id : "";
        const status = typeof body.status === "string" ? body.status : "";
        const reason = typeof body.reason === "string" ? body.reason.trim().slice(0, 500) : "";
        if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(partnerId) || !["verified", "rejected", "suspended"].includes(status)) return reply(400, { ok: false, error: "invalid_verification_request" });
        const { data, error } = await admin.rpc("rewardloop_verify_partner_internal", { p_actor_user_id: user.id, p_tenant_id: tenant.id, p_partner_id: partnerId, p_new_status: status, p_reason: reason || null });
        if (error) return reply(500, { ok: false, error: "partner_verification_failed" });
        return reply(200, data && typeof data === "object" ? data : { ok: false, error: "unexpected_verification_response" });
      }
      if (action === "issue_qr_batch") {
        const campaignId = typeof body.campaign_id === "string" ? body.campaign_id : "";
        const productId = typeof body.product_id === "string" ? body.product_id : "";
        const count = Number(body.count), pointsValue = Number(body.points_value);
        const role = typeof body.entitlement_role === "string" ? body.entitlement_role : "farmer";
        const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
        if (!uuid.test(campaignId) || !uuid.test(productId) || !Number.isInteger(count) || count < 1 || count > 1000 || !Number.isInteger(pointsValue) || pointsValue < 1 || pointsValue > 1000000 || !["farmer", "retailer", "distributor"].includes(role)) return reply(400, { ok: false, error: "invalid_batch_request" });
        const { data, error } = await admin.rpc("rewardloop_issue_qr_batch_internal", { p_actor_user_id: user.id, p_tenant_id: tenant.id, p_campaign_id: campaignId, p_product_id: productId, p_count: count, p_points_value: pointsValue, p_entitlement_role: role });
        if (error) return reply(500, { ok: false, error: "qr_batch_issue_failed" });
        return reply(200, data && typeof data === "object" ? data : { ok: false, error: "unexpected_batch_response" });
      }
      if (action === "revoke_qr_batch") {
        const batchId = typeof body.batch_id === "string" ? body.batch_id : "";
        const reason = typeof body.reason === "string" ? body.reason.trim().slice(0, 500) : "";
        if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(batchId) || reason.length < 5) return reply(400, { ok: false, error: "invalid_revoke_request" });
        const { data, error } = await admin.rpc("rewardloop_revoke_qr_batch_internal", { p_actor_user_id: user.id, p_tenant_id: tenant.id, p_batch_id: batchId, p_reason: reason });
        if (error) return reply(500, { ok: false, error: "qr_batch_revoke_failed" });
        return reply(200, data && typeof data === "object" ? data : { ok: false, error: "unexpected_revoke_response" });
      }
      if (action === "create_campaign") {
        const name = typeof body.name === "string" ? body.name.trim().slice(0, 120) : "";
        const startsAt = typeof body.starts_at === "string" && body.starts_at ? new Date(body.starts_at) : null;
        const endsAt = typeof body.ends_at === "string" && body.ends_at ? new Date(body.ends_at) : null;
        const budget = Number(body.budget_minor_units);
        if (name.length < 3 || !Number.isSafeInteger(budget) || budget < 0 || budget > 1000000000000 ||
            (startsAt && !Number.isFinite(startsAt.getTime())) || (endsAt && !Number.isFinite(endsAt.getTime()))) {
          return reply(400, { ok: false, error: "invalid_campaign_details" });
        }
        const { data, error } = await admin.rpc("rewardloop_create_campaign_internal", {
          p_actor_user_id: user.id, p_tenant_id: tenant.id, p_name: name,
          p_starts_at: startsAt ? startsAt.toISOString() : null,
          p_ends_at: endsAt ? endsAt.toISOString() : null, p_budget_minor_units: budget
        });
        if (error) return reply(500, { ok: false, error: "campaign_create_failed" });
        return reply(200, data && typeof data === "object" ? data : { ok: false, error: "unexpected_campaign_response" });
      }
      if (action === "set_campaign_status") {
        const campaignId = typeof body.campaign_id === "string" ? body.campaign_id : "";
        const status = typeof body.status === "string" ? body.status : "";
        const reason = typeof body.reason === "string" ? body.reason.trim().slice(0, 500) : "";
        if (!/^[0-9a-f-]{36}$/i.test(campaignId) || !["active", "paused", "archived"].includes(status) || (status !== "active" && reason.length < 5)) {
          return reply(400, { ok: false, error: "invalid_campaign_status_request" });
        }
        const { data, error } = await admin.rpc("rewardloop_set_campaign_status_internal", {
          p_actor_user_id: user.id, p_tenant_id: tenant.id, p_campaign_id: campaignId, p_new_status: status, p_reason: reason || null
        });
        if (error) return reply(500, { ok: false, error: "campaign_status_update_failed" });
        return reply(200, data && typeof data === "object" ? data : { ok: false, error: "unexpected_campaign_response" });
      }
      if (action === "resolve_redemption") {
        const redemptionId = typeof body.redemption_id === "string" ? body.redemption_id : "";
        const status = typeof body.status === "string" ? body.status : "";
        const reason = typeof body.reason === "string" ? body.reason.trim().slice(0, 500) : "";
        if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(redemptionId) || !["fulfilled", "cancelled", "rejected"].includes(status) || (status !== "fulfilled" && reason.length < 5)) {
          return reply(400, { ok: false, error: "invalid_redemption_resolution" });
        }
        const { data, error } = await admin.rpc("rewardloop_resolve_redemption_internal", {
          p_actor_user_id: user.id,
          p_tenant_id: tenant.id,
          p_redemption_id: redemptionId,
          p_new_status: status,
          p_reason: reason || null,
        });
        if (error) return reply(500, { ok: false, error: "redemption_resolution_failed" });
        return reply(200, data && typeof data === "object" ? data : { ok: false, error: "unexpected_redemption_response" });
      }
    }

    return reply(400, { ok: false, error: "unknown_action" });
  } catch {
    // Avoid returning raw exception details or credentials to the client.
    return reply(500, { ok: false, error: "unexpected_server_error" });
  }
});
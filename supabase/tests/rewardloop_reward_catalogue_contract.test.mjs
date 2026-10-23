import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const migration = readFileSync(new URL("../migrations/20261023210000_audited_reward_catalogue_management.sql", import.meta.url), "utf8");
const api = readFileSync(new URL("../functions/rewardloop-api/index.ts", import.meta.url), "utf8");
const admin = readFileSync(new URL("../../admin.js", import.meta.url), "utf8");
const release = readFileSync(new URL("../../.github/workflows/rewardloop-production-release.yml", import.meta.url), "utf8");
const dbWorkflow = readFileSync(new URL("../../.github/workflows/rewardloop-claim-replay-db.yml", import.meta.url), "utf8");
const behavior = readFileSync(new URL("rewardloop_reward_catalogue_behavior.test.sql", import.meta.url), "utf8");

test("reward catalogue RPCs validate tenant membership, input bounds and explicit activation", () => {
  assert.match(migration, /CREATE OR REPLACE FUNCTION private\.create_rewardloop_reward/);
  assert.match(migration, /CREATE OR REPLACE FUNCTION private\.update_rewardloop_reward/);
  assert.match(migration, /CREATE OR REPLACE FUNCTION private\.set_rewardloop_reward_status/);
  assert.match(migration, /rewards_tenant_catalogue_order_idx/);
  assert.match(migration, /m\.status='active' AND m\.role IN \('brand_admin','super_admin'\)/);
  assert.match(migration, /tenant_inactive/);
  assert.match(migration, /reward_slug_exists/);
  assert.match(migration, /demo_reward_read_only/);
  assert.match(migration, /demo_reward_not_activatable/);
  assert.match(migration, /reward_out_of_stock/);
  assert.match(migration, /deactivate_reward_before_zero_stock/);
  assert.match(migration, /reward_created/);
  assert.match(migration, /reward_updated/);
  assert.match(migration, /reward_activated/);
  assert.match(migration, /reward_deactivated/);
});

test("reward API is rate-limited, tenant-authorized, validated and routed through service RPCs", () => {
  assert.match(api, /create_reward: \{ limit: 15, windowSeconds: 60 \}/);
  assert.match(api, /update_reward: \{ limit: 30, windowSeconds: 60 \}/);
  assert.match(api, /set_reward_status: \{ limit: 20, windowSeconds: 60 \}/);
  assert.match(api, /"create_reward", "update_reward", "set_reward_status"/);
  assert.match(api, /rewardloop_create_reward_internal/);
  assert.match(api, /rewardloop_update_reward_internal/);
  assert.match(api, /rewardloop_set_reward_status_internal/);
  assert.match(api, /rewards: { key: "rewards_page", size: 50 }/);
  assert.match(api, /\.from\("rewards"\)[\s\S]*?\.eq\("tenant_id", tenant\.id\)/);
  assert.match(api, /reward_management: true/);
});

test("admin reward catalogue supports create/edit/activate with guarded confirmation", () => {
  assert.match(admin, /data\.capabilities\?\.reward_management===true/);
  assert.match(admin, /id="reward-create"/);
  assert.match(admin, /call\("create_reward"/);
  assert.match(admin, /call\("update_reward"/);
  assert.match(admin, /call\("set_reward_status"/);
  assert.match(admin, /confirmAdminAction\(\{title:active\?"Activate reward\?"/);
  assert.match(admin, /name:"description",label:"Description",type:"textarea"/);
  assert.match(admin, /pages\.rewards/);
});

test("reward catalogue migration is protected by release allowlist and disposable behavior coverage", () => {
  assert.match(release, /20261023210000/);
  assert.match(dbWorkflow, /rewardloop_reward_catalogue_behavior\.test\.sql/);
  assert.match(behavior, /cross-tenant reward creation was not rejected/);
  assert.match(behavior, /zero-stock reward activation was accepted/);
  assert.match(behavior, /demo reward activation was accepted/);
  assert.match(behavior, /create\/update\/activate\/deactivate audit count mismatch/);
});

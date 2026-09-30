import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { createHash } from "node:crypto";

const BASE = process.env.AGENTHANSA_API || "https://www.agenthansa.com";
const KEY = process.env.AGENTHANSA_API_KEY || "";
const STATE = "HANSA_ONLINE/state.json";
const EVIDENCE = "HANSA_ONLINE/evidence/latest.json";

const now = new Date();
const nowIso = now.toISOString();
const today = nowIso.toISOString().slice(0, 10);

function loadState() {
  if (!existsSync(STATE)) return {};
  return JSON.parse(readFileSync(STATE, "utf8"));
}
function save(path, value) {
  const dir = path.slice(0, path.lastIndexOf("/"));
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
  writeFileSync(path, JSON.stringify(value, null, 2) + "\n");
}
async function call(method, path, body, auth = true) {
  const headers = { accept: "application/json", "content-type": "application/json" };
  if (auth) headers.authorization = `Bearer ${KEY}`;
  const res = await fetch(BASE + path, {
    method, headers,
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(12000)
  });
  const text = await res.text();
  let data;
  try { data = JSON.parse(text); } catch { data = { raw_type: typeof text, raw_length: text.length }; }
  return { http_status: res.status, ok: res.ok, data };
}
function hash(v) {
  return createHash("sha256").update(JSON.stringify(v)).digest("hex");
}
function compactProfile(p) {
  if (!p || typeof p !== "object") return null;
  return {
    id: p.id ?? p.agent_id ?? null,
    name: p.name ?? null,
    level: p.level ?? null,
    xp: p.xp ?? null,
    reputation: p.reputation ?? p.reputation_score ?? null,
    alliance: p.alliance ?? null,
    rank: p.rank ?? p.leaderboard_rank ?? null
  };
}

const state = loadState();
let checkinChallenge = false;
const evidence = {
  schema_version: "HANSA-EVIDENCE/v1",
  captured_at: nowIso,
  source: "AgentHansa HTTPS API",
  run_mode: "scheduled_online",
  checks: {},
  mutations: [],
  verification: { verified: false, reason: "" }
};

try {
  evidence.checks.health = await call("GET", "/health", undefined, false);

  if (!KEY) {
    state.runtime_status = "BLOCKED";
    state.auth_status = "BLOCKED_AUTH";
    state.last_run_at = nowIso;
    state.verification = { verified: false, reason: "AGENTHANSA_API_KEY is not available to the online worker." };
    state.next_action = "PROVISION_AGENTHANSA_API_KEY_AS_GITHUB_ACTIONS_SECRET";
    evidence.verification = state.verification;
    save(EVIDENCE, evidence);
    save(STATE, state);
    console.log(JSON.stringify({ state, evidence_summary: { health: evidence.checks.health.http_status, auth: "BLOCKED_AUTH" } }, null, 2));
    process.exit(0);
  }

  evidence.checks.me = await call("GET", "/api/agents/me");
  if (!evidence.checks.me.ok) throw new Error(`Authenticated /api/agents/me failed: HTTP ${evidence.checks.me.http_status}`);

  state.agent = compactProfile(evidence.checks.me.data);
  state.auth_status = "AUTHENTICATED";

  // Only endpoints documented by the current AgentHansa integration are polled.
  // Unknown/legacy endpoints are intentionally excluded so one stale endpoint
  // cannot turn an otherwise healthy runtime into a false failure.
  const endpoints = [
    ["inbox", "/api/agents/me/inbox"],
    ["work", "/api/agents/work?page=1&per_page=20&type=all"],
    ["feed", "/api/agents/feed"],
    ["daily_quests", "/api/agents/daily-quests"],
    ["quests", "/api/alliance-war/quests?page=1&per_page=10"],
    ["earnings", "/api/agents/earnings"],
    ["points", "/api/agents/points"],
    ["reputation", "/api/agents/reputation"],
    ["rewards", "/api/agents/rewards-status"],
    ["journey", "/api/agents/journey?limit=50&offset=0"],
    ["notifications", "/api/agents/notifications?unread_only=true"],
    ["points_leaderboard", "/api/agents/points-leaderboard"],
    ["daily_points_leaderboard", "/api/agents/daily-points-leaderboard"],
    ["alliance_daily_leaderboard", "/api/agents/alliance-daily-leaderboard?day=today"],
    ["my_daily_xp", "/api/agents/my-daily-xp"],
    ["alliance_leaderboard", "/api/agents/alliance-leaderboard"],
    ["earnings_leaderboard", "/api/agents/leaderboard?period=week"],
    ["reputation_leaderboard", "/api/agents/reputation-leaderboard?limit=20"],
    ["quick_earn", "/api/agents/me/quick-earn"],
    ["onboarding_status", "/api/agents/onboarding-status"]
  ];

  for (const [name, path] of endpoints) {
    evidence.checks[name] = await call("GET", path);
  }

  if (state.last_checkin_utc_date !== today) {
    const checkin = await call("POST", "/api/agents/checkin");
    evidence.mutations.push({
      action: "daily_checkin_attempt",
      captured_at: nowIso,
      http_status: checkin.http_status,
      ok: checkin.ok,
      result_hash: hash(checkin.data)
    });
    const hasChallenge = checkin.ok && checkin.data && typeof checkin.data === "object" &&
      (checkin.data.challenge || checkin.data.question || checkin.data.answer_required);
    if (checkin.ok && !hasChallenge) {
      state.last_checkin_utc_date = today;
    } else if (hasChallenge) {
      checkinChallenge = true;
      state.next_action = "SOLVE_CHECKIN_CHALLENGE_THEN_POST_CHECKIN_VERIFY";
      state.verification = { verified:false, reason:"AgentHansa returned a check-in challenge; check-in is not counted as completed yet." };
    } else if (checkin.http_status === 409) {
      state.last_checkin_utc_date = today;
    }
  }

  const failed = Object.entries(evidence.checks)
    .filter(([k, v]) => !v.ok)
    .map(([endpoint, v]) => ({ endpoint, http_status: v.http_status }));

  state.last_run_at = nowIso;

  if (failed.length === 0 && !checkinChallenge) {
    state.runtime_status = "ACTIVE";
    state.last_success_at = nowIso;
    state.observations = Object.fromEntries(
      Object.entries(evidence.checks).map(([k, v]) => [
        k, { http_status: v.http_status, ok: v.ok, result_hash: hash(v.data) }
      ])
    );
    state.verification = {
      verified: true,
      reason: "Authenticated Hansa observations completed and daily check-in was handled idempotently."
    };
    state.next_action = "RESEARCH_AND_SCORE_AVAILABLE_HANSA_WORK_WITHOUT_AUTO_SUBMISSION";
    evidence.verification = state.verification;
  } else if (checkinChallenge) {
    state.runtime_status = "PENDING";
    state.verification = { verified:false, reason:"Online observations succeeded, but daily check-in is awaiting challenge verification." };
    state.next_action = "SOLVE_CHECKIN_CHALLENGE_THEN_POST_CHECKIN_VERIFY";
    evidence.verification = state.verification;
  } else {
    state.runtime_status = "UNKNOWN";
    state.verification = {
      verified: false,
      reason: "One or more documented Hansa observations failed.",
      failed
    };
    state.next_action = "ROOT_CAUSE_FAILED_HANSA_ENDPOINTS";
    evidence.verification = state.verification;
  }

  save(EVIDENCE, evidence);
  save(STATE, state);
  console.log(JSON.stringify({
    state,
    evidence_summary: {
      checks: Object.keys(evidence.checks),
      mutations: evidence.mutations.length,
      verified: evidence.verification.verified
    }
  }, null, 2));
} catch (err) {
  state.runtime_status = "FAILED";
  state.last_run_at = nowIso;
  state.verification = { verified: false, reason: String(err.message || err) };
  state.next_action = "RECOVER_AND_RETRY_AFTER_ROOT_CAUSE";
  evidence.verification = state.verification;
  save(EVIDENCE, evidence);
  save(STATE, state);
  console.error(JSON.stringify({ state, evidence_summary: { verified: false } }, null, 2));
  process.exit(1);
}

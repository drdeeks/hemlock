import { Hono } from "hono";
import { SPEC_VERSION, type SnapFunction } from "@farcaster/snap";
import { registerSnapHandler } from "@farcaster/snap-hono";
import {
  createInMemoryDataStore,
  createTursoDataStore,
} from "@farcaster/snap-turso";

// ─── Config ───────────────────────────────────────────────────────
const HUB_BASE = "https://snapchain-api.neynar.com/v1";
const REST_BASE = "https://api.neynar.com/v2/farcaster";
const NEYNAR_KEY = process.env.NEYNAR_API_KEY ?? "";
const DAILY_SWIPE_LIMIT = 3;
const MIN_ACCOUNT_AGE_DAYS = 180;
const MIN_NEYNAR_SCORE = 0.42;
const MIN_FOLLOWER_RATIO = 0.15;
const MIN_FOLLOWERS = 10;
const MAX_POOL_SIZE = 60;
const RESET_HOUR_UTC = 0;
const SPEC = SPEC_VERSION;

if (!NEYNAR_KEY) {
  console.error("⚠️  NEYNAR_API_KEY not set!");
}

// ─── Data Store ───────────────────────────────────────────────────
const store =
  process.env.VERCEL === "1"
    ? createTursoDataStore()
    : createInMemoryDataStore();

// ─── Types ────────────────────────────────────────────────────────
interface NeynarUser {
  fid: number;
  username: string;
  display_name: string;
  pfp_url: string;
  profile: { bio: { text: string } };
  follower_count: number;
  following_count: number;
  power_badge: boolean;
  score: number;
  verifications: string[];
  registered_at: string;
}

interface Profile {
  fid: number;
  username: string;
  displayName: string;
  pfpUrl: string;
  bio: string;
  followers: number;
  following: number;
}

interface CastMessage {
  data: {
    type: string;
    fid: number;
    timestamp: number;
    castAddBody: {
      text: string;
      mentions: number[];
      parentCastId?: { fid: number; hash: string };
      parentUrl?: string | null;
      embeds: any[];
    };
  };
  hash: string;
}

// ─── Hub API (FREE — snapchain) ───────────────────────────────────
async function hubFetch<T>(path: string): Promise<T | null> {
  if (!NEYNAR_KEY) return null;
  try {
    const res = await fetch(`${HUB_BASE}${path}`, {
      headers: { "x-api-key": NEYNAR_KEY },
    });
    if (!res.ok) {
      console.error(`Hub ${path}: ${res.status}`);
      return null;
    }
    return (await res.json()) as T;
  } catch (e) {
    console.error(`Hub error ${path}:`, e);
    return null;
  }
}

// ─── REST API (user/bulk is free tier) ────────────────────────────
async function restFetch<T>(path: string): Promise<T | null> {
  if (!NEYNAR_KEY) return null;
  try {
    const res = await fetch(`${REST_BASE}${path}`, {
      headers: { api_key: NEYNAR_KEY },
    });
    if (!res.ok) {
      console.error(`REST ${path}: ${res.status}`);
      return null;
    }
    return (await res.json()) as T;
  } catch (e) {
    console.error(`REST error ${path}:`, e);
    return null;
  }
}

async function fetchUsers(fids: number[]): Promise<NeynarUser[]> {
  if (fids.length === 0) return [];
  const data = await restFetch<{ users: NeynarUser[] }>(
    `/user/bulk?fids=${fids.join(",")}`
  );
  return data?.users ?? [];
}

async function fetchCastsByFid(fid: number, limit = 50): Promise<CastMessage[]> {
  const data = await hubFetch<{ messages: CastMessage[] }>(
    `/castsByFid?fid=${fid}&pageSize=${limit}`
  );
  return data?.messages ?? [];
}

async function discoverFidsViaHub(seedFids: number[], maxDiscover = 100): Promise<number[]> {
  const discovered = new Set<number>();
  const sampleSeeds = shuffleArray(seedFids).slice(0, 5);
  for (const seedFid of sampleSeeds) {
    const casts = await fetchCastsByFid(seedFid, 20);
    for (const cast of casts) {
      const mentions = cast.data.castAddBody?.mentions ?? [];
      for (const mid of mentions) {
        if (mid !== seedFid) discovered.add(mid);
      }
      const parentFid = cast.data.castAddBody?.parentCastId?.fid;
      if (parentFid && parentFid !== seedFid) discovered.add(parentFid);
      if (discovered.size >= maxDiscover) break;
    }
    if (discovered.size >= maxDiscover) break;
  }
  return Array.from(discovered);
}

// ─── Qualification ─────────────────────────────────────────────────
function qualifyUser(user: NeynarUser) {
  const accountAgeDays = daysSince(user.registered_at);
  const neynarScore = user.score ?? 0;
  const followerRatio =
    user.following_count > 0
      ? user.follower_count / user.following_count
      : user.follower_count > 0 ? 999 : 0;

  if (accountAgeDays < MIN_ACCOUNT_AGE_DAYS) return { qualified: false, reason: "Account too new" };
  if (neynarScore < MIN_NEYNAR_SCORE) return { qualified: false, reason: "Score too low" };
  if (followerRatio < MIN_FOLLOWER_RATIO) return { qualified: false, reason: "Follower ratio too low" };
  if (user.follower_count < MIN_FOLLOWERS) return { qualified: false, reason: "Too few followers" };
  return { qualified: true, reason: "OK" };
}

// ─── Helpers ──────────────────────────────────────────────────────
const VALID_IMG_EXT = /\.(jpg|jpeg|png|gif|webp)(\?.*)?$/i;

// Check if a URL has a valid image extension (what the Farcaster client accepts)
function hasValidImageExt(url: string): boolean {
  const clean = url.split("?")[0].split("#")[0];
  return VALID_IMG_EXT.test(clean);
}

// Best-effort image URL that the Farcaster client will render
// Neynar's imagedelivery.net URLs lack file extensions — client rejects them
// Generate personalized placeholder from username when real URL is invalid
function safeImageUrl(url: string | undefined | null, username?: string): string {
  if (url && hasValidImageExt(url)) return url;
  // Generate a personalized placeholder with the user's initials
  const initials = (username ?? "??").slice(0, 2).toUpperCase();
  return `https://dummyimage.com/200x200/1A1528/C4A7E7.png?text=${encodeURIComponent(initials)}`;
}

function daysSince(dateStr: string): number {
  return Math.floor((Date.now() - new Date(dateStr).getTime()) / (1000 * 60 * 60 * 24));
}

function todayKey(): string {
  const now = new Date();
  if (now.getUTCHours() < RESET_HOUR_UTC) now.setUTCDate(now.getUTCDate() - 1);
  return now.toISOString().slice(0, 10);
}

function clamp(s: string, max: number): string {
  return s.length <= max ? s : s.slice(0, max - 3) + "...";
}

function shuffleArray<T>(arr: T[]): T[] {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

function snapBase(request: Request): string {
  const fromEnv = process.env.SNAP_PUBLIC_BASE_URL?.trim();
  if (fromEnv) return fromEnv.replace(/\/$/, "");
  const host = request.headers.get("x-forwarded-host")?.split(",")[0].trim()
    ?? request.headers.get("host")?.split(",")[0].trim();
  const isLoopback = host && /^(localhost|127\.0\.0\.1|\[::1\]|::1)(:\d+)?$/.test(host);
  const proto = request.headers.get("x-forwarded-proto")?.split(",")[0].trim().toLowerCase()
    ?? (isLoopback ? "http" : "https");
  if (host) return `${proto}://${host}`.replace(/\/$/, "");
  return `http://localhost:${process.env.PORT ?? "3003"}`.replace(/\/$/, "");
}

// ─── Turso Helpers ────────────────────────────────────────────────
async function getBehavioralTag(fid: number): Promise<string | null> {
  return ((await store.get(`bt:${fid}`)) as any)?.tag ?? null;
}
async function setBehavioralTag(fid: number, tag: string) {
  await store.set(`bt:${fid}`, { tag, timestamp: Date.now() });
}
async function getQualification(fid: number) {
  return ((await store.get(`qual:${fid}`)) as any) ?? null;
}
async function setQualification(fid: number, result: any) {
  await store.set(`qual:${fid}`, { ...result, checkedAt: Date.now() });
}
async function getSwipeCount(fid: number): Promise<number> {
  return ((await store.get(`sc:${fid}:${todayKey()}`)) as any)?.count ?? 0;
}
async function incrementSwipe(fid: number): Promise<number> {
  const key = `sc:${fid}:${todayKey()}`;
  const count = (((await store.get(key)) as any)?.count ?? 0) + 1;
  await store.set(key, { count });
  return count;
}
async function recordSwipe(swiperFid: number, targetFid: number, direction: string, tag: string) {
  const data = (await store.get(`swipes:${swiperFid}`)) as any;
  const swipes: any[] = data?.swipes ?? [];
  swipes.push({ targetFid, direction, tag, ts: Date.now() });
  await store.set(`swipes:${swiperFid}`, { swipes });
}
async function getSwipedFids(fid: number): Promise<Set<number>> {
  return new Set((((await store.get(`swipes:${fid}`)) as any)?.swipes ?? []).map((s: any) => s.targetFid));
}
async function getProfilePool(fid: number): Promise<Profile[]> {
  return (((await store.get(`pool:${fid}`)) as any)?.profiles ?? []) as Profile[];
}
async function setProfilePool(fid: number, profiles: Profile[]) {
  await store.set(`pool:${fid}`, { profiles: profiles.map(p => ({ ...p })), builtAt: Date.now() });
}

// ─── Seed FIDs ────────────────────────────────────────────────────
const SEED_FIDS: number[] = [
  3, 56, 185, 194, 226, 239, 276, 341, 576, 756,
  859, 930, 1114, 1158, 1215, 1311, 1600, 1689, 1899, 2048,
  2309, 2411, 2515, 2608, 2714, 2858, 2934, 3098, 3201, 3354,
  3456, 3600, 3757, 3890, 3988, 4123, 4267, 4400, 4501, 4678,
  4801, 4923, 5056, 5189, 5300, 5423, 5567, 5700, 5834, 5978,
  6100, 6234, 6367, 6500, 6634, 6778, 6900, 7034, 7167, 7300,
  7434, 7567, 7700, 7834, 7967, 8100, 8234, 8367, 8500, 8634,
  8767, 8900, 9034, 9167, 9300, 9434, 9567, 9700, 9834, 9967,
];

// ─── Pool Builder ─────────────────────────────────────────────────
async function buildProfilePool(swiperFid: number): Promise<Profile[]> {
  const swiped = await getSwipedFids(swiperFid);
  const hubDiscovered = await discoverFidsViaHub(SEED_FIDS, 80);
  const allFids = new Set([...SEED_FIDS, ...hubDiscovered]);
  allFids.delete(swiperFid);
  for (const fid of swiped) allFids.delete(fid);
  const candidates = shuffleArray(Array.from(allFids)).slice(0, 50);
  if (candidates.length === 0) return [];

  const qualified: Profile[] = [];
  for (let i = 0; i < candidates.length && qualified.length < MAX_POOL_SIZE; i += 20) {
    const batch = candidates.slice(i, i + 20);
    const users = await fetchUsers(batch);
    for (const user of users) {
      if (qualified.length >= MAX_POOL_SIZE) break;
      if (qualifyUser(user).qualified) {
        qualified.push({
          fid: user.fid, username: user.username, displayName: user.display_name,
          pfpUrl: user.pfp_url, bio: clamp(user.profile?.bio?.text ?? "", 160),
          followers: user.follower_count, following: user.following_count,
        });
      }
    }
  }
  return qualified;
}

// ─── Dark Fallback HTML ───────────────────────────────────────────
const DARK_HTML = `<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Pass? or Yass? 🧐</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;background:#0D0B14;min-height:100vh;display:flex;align-items:center;justify-content:center;flex-direction:column;padding:24px;color:#E0DEF4}
.card{background:linear-gradient(145deg,#1A1528,#1E1433,#16102B);border:1px solid #2D2248;border-radius:16px;max-width:420px;width:100%;padding:24px;box-shadow:0 8px 32px rgba(100,60,180,.15),0 0 60px rgba(140,100,220,.05)}
.title{font-size:22px;font-weight:700;text-align:center;color:#C4A7E7;margin-bottom:8px}
.sub{font-size:14px;text-align:center;color:#908CAA;margin-bottom:24px}
.btns{display:flex;gap:12px}
.b{flex:1;padding:12px 16px;border-radius:10px;font-size:14px;font-weight:600;cursor:pointer;font-family:inherit;text-align:center;text-decoration:none}
.bp{background:transparent;color:#908CAA;border:2px solid #393552}
.bp:hover{border-color:#EB6F92;color:#EB6F92}
.by{background:linear-gradient(135deg,#907AA9,#C4A7E7);color:#fff;border:none}
.by:hover{filter:brightness(1.1)}
.ft{margin-top:20px;text-align:center}
.ft a{color:#6E6A86;text-decoration:none;font-size:13px}
.ft a:hover{color:#C4A7E7}
.md{display:none;position:fixed;inset:0;background:rgba(13,11,20,.85);align-items:center;justify-content:center;z-index:99}
.mb{background:#1A1528;border:1px solid #2D2248;border-radius:16px;padding:32px;text-align:center;max-width:340px;width:90%}
.mb h2{color:#E0DEF4;font-size:20px;margin-bottom:8px}
.mb p{color:#908CAA;font-size:14px;line-height:1.5;margin-bottom:24px}
.mb a{display:block;padding:12px;border-radius:10px;text-decoration:none;font-weight:600;font-size:15px;margin-bottom:12px}
.mp{background:linear-gradient(135deg,#907AA9,#C4A7E7);color:#fff}
.ms{background:#1A152E;color:#E0DEF4;border:1px solid #2D2248}
.mb button{background:none;border:none;color:#6E6A86;cursor:pointer;font-size:13px;font-family:inherit}
</style></head><body>
<div class="card">
<div class="title">Pass? or Yass? 🧐</div>
<div class="sub">Discover Farcaster profiles. Swipe right for Yass, left for Pass.</div>
<div class="btns"><a class="b bp" href="https://farcaster.xyz">Pass</a><a class="b by" href="https://farcaster.xyz">Yass</a></div>
</div>
<div class="ft"><a href="https://farcaster.xyz">Farcaster</a></div>
</body></html>`;

// ═══════════════════════════════════════════════════════════════════
// SNAP HANDLER — uses ROUTE-BASED navigation (not query params)
// ═══════════════════════════════════════════════════════════════════
const app = new Hono();

const snap: SnapFunction = async (ctx) => {
  const base = snapBase(ctx.request);

  // GET: always show gate
  if (ctx.action.type === "get") {
    return gatePage(base);
  }

  // POST: determine action from the registered route path
  const fid = ctx.action.user.fid;
  const path = new URL(ctx.request.url).pathname;

  // Route: /gate-pass or /gate-yass
  if (path === "/gate-pass") {
    await setBehavioralTag(fid, "cautious");
    return thanksPage();
  }
  if (path === "/gate-yass") {
    await setBehavioralTag(fid, "adventurous");
    return await handleGate(fid, base);
  }

  // Route: /swipe-pass?tid=X or /swipe-yass?tid=X
  if (path.startsWith("/swipe-pass")) {
    const tid = new URL(ctx.request.url).searchParams.get("tid");
    if (tid) return await handleSwipe(fid, parseInt(tid), "pass", base);
  }
  if (path.startsWith("/swipe-yass")) {
    const tid = new URL(ctx.request.url).searchParams.get("tid");
    if (tid) return await handleSwipe(fid, parseInt(tid), "yass", base);
  }

  return gatePage(base);
};

// ─── Gate Handler ─────────────────────────────────────────────────
async function handleGate(fid: number, base: string) {
  const existing = await getQualification(fid);
  if (existing?.qualified) return await showNext(fid, base);

  const users = await fetchUsers([fid]);
  if (!users.length) return rejectionPage();

  const qual = qualifyUser(users[0]);
  await setQualification(fid, qual);
  if (!qual.qualified) return rejectionPage();

  return await showNext(fid, base);
}

// ─── Swipe Handler ────────────────────────────────────────────────
async function handleSwipe(swiperFid: number, targetFid: number, direction: string, base: string) {
  const count = await getSwipeCount(swiperFid);
  if (count >= DAILY_SWIPE_LIMIT) return dailyLimitPage();

  const tag = (await getBehavioralTag(swiperFid)) ?? "unknown";
  await recordSwipe(swiperFid, targetFid, direction, tag);
  await incrementSwipe(swiperFid);

  return await showNext(swiperFid, base);
}

// ─── Show Next Profile ────────────────────────────────────────────
async function showNext(fid: number, base: string) {
  const count = await getSwipeCount(fid);
  if (count >= DAILY_SWIPE_LIMIT) return dailyLimitPage();

  let pool = await getProfilePool(fid);
  const swiped = await getSwipedFids(fid);
  pool = pool.filter(p => !swiped.has(p.fid));

  if (pool.length < 3) {
    const newP = await buildProfilePool(fid);
    const existing = new Set(pool.map(p => p.fid));
    for (const p of newP) {
      if (!existing.has(p.fid) && !swiped.has(p.fid)) {
        pool.push(p);
        existing.add(p.fid);
      }
    }
    await setProfilePool(fid, pool);
  }

  if (pool.length === 0) return noMorePage();

  const next = pool[0];
  await setProfilePool(fid, pool.slice(1));
  return profilePage(next, DAILY_SWIPE_LIMIT - count, base, pool.length - 1);
}

// ═══════════════════════════════════════════════════════════════════
// SNAP UI PAGES
// ═══════════════════════════════════════════════════════════════════
const ACCENT = "purple" as const;

function gatePage(base: string) {
  return {
    version: SPEC,
    theme: { accent: ACCENT },
    ui: {
      root: "page",
      elements: {
        page: { type: "stack", props: {}, children: ["title", "sub", "sp", "btns"] },
        title: { type: "text", props: { content: "Pass? or Yass?", size: "lg", weight: "bold", align: "center" } },
        sub: { type: "text", props: { content: "Discover Farcaster profiles", size: "sm", align: "center" } },
        sp: { type: "text", props: { content: " ", size: "sm" } },
        btns: { type: "stack", props: { direction: "horizontal", gap: "md" }, children: ["bp", "by"] },
        bp: {
          type: "button", props: { label: "Pass", variant: "secondary" },
          on: { press: { action: "submit", params: { target: `${base}/gate-pass` } } },
        },
        by: {
          type: "button", props: { label: "Yass", variant: "primary" },
          on: { press: { action: "submit", params: { target: `${base}/gate-yass` } } },
        },
      },
    },
  };
}

function profilePage(profile: Profile, remaining: number, base: string, poolCount: number) {
  const bioText = profile.bio ? clamp(profile.bio, 100) : "";
  const metaText = `${profile.followers.toLocaleString()} followers`;
  const remText = poolCount > 1
    ? `${poolCount} profiles left`
    : poolCount === 1 ? "Last profile" : `${remaining} swipes left`;

  const elements: Record<string, any> = {
    page: {
      type: "stack", props: {},
      children: ["pfp", "name", ...(bioText ? ["bio"] : []), "meta", "sep", "rem", "btns"],
    },
    pfp: {
      type: "image",
      props: { url: safeImageUrl(profile.pfpUrl, profile.username), aspect: "1:1", alt: profile.displayName },
    },
    name: { type: "item", props: { title: clamp(profile.displayName || profile.username, 100), description: `@${profile.username}` } },
    meta: { type: "text", props: { content: metaText, size: "sm", align: "center" } },
    sep: { type: "separator", props: {} },
    rem: { type: "text", props: { content: remText, size: "sm", align: "center" } },
    btns: { type: "stack", props: { direction: "horizontal", gap: "md" }, children: ["bp", "by"] },
    bp: {
      type: "button", props: { label: "Pass", variant: "secondary" },
      on: { press: { action: "submit", params: { target: `${base}/swipe-pass?tid=${profile.fid}` } } },
    },
    by: {
      type: "button", props: { label: "Yass", variant: "primary" },
      on: { press: { action: "submit", params: { target: `${base}/swipe-yass?tid=${profile.fid}` } } },
    },
  };
  if (bioText) {
    elements.bio = { type: "text", props: { content: bioText, size: "md", align: "center" } };
  }
  return { version: SPEC, theme: { accent: ACCENT }, ui: { root: "page", elements } };
}

function rejectionPage() {
  return {
    version: SPEC, theme: { accent: ACCENT },
    ui: {
      root: "page",
      elements: {
        page: { type: "stack", props: {}, children: ["icon", "msg", "hint"] },
        icon: { type: "text", props: { content: "🧐", size: "lg", align: "center" } },
        msg: { type: "text", props: { content: "Not quite yet!", size: "md", weight: "bold", align: "center" } },
        hint: { type: "text", props: { content: "Keep casting and come back soon.", size: "sm", align: "center" } },
      },
    },
  };
}

function thanksPage() {
  return {
    version: SPEC, theme: { accent: ACCENT },
    ui: {
      root: "page",
      elements: {
        page: { type: "stack", props: {}, children: ["icon", "msg", "hint"] },
        icon: { type: "text", props: { content: "👋", size: "lg", align: "center" } },
        msg: { type: "text", props: { content: "Thanks for playing!", size: "md", weight: "bold", align: "center" } },
        hint: { type: "text", props: { content: "Come back when you're ready to Yass.", size: "sm", align: "center" } },
      },
    },
  };
}

function dailyLimitPage() {
  return {
    version: SPEC, theme: { accent: ACCENT },
    ui: {
      root: "page",
      elements: {
        page: { type: "stack", props: {}, children: ["icon", "msg", "hint"] },
        icon: { type: "text", props: { content: "⏰", size: "lg", align: "center" } },
        msg: { type: "text", props: { content: "All 3 swipes used!", size: "md", weight: "bold", align: "center" } },
        hint: { type: "text", props: { content: "Come back tomorrow at midnight UTC.", size: "sm", align: "center" } },
      },
    },
  };
}

function noMorePage() {
  return {
    version: SPEC, theme: { accent: ACCENT },
    ui: {
      root: "page",
      elements: {
        page: { type: "stack", props: {}, children: ["icon", "msg", "hint"] },
        icon: { type: "text", props: { content: "👀", size: "lg", align: "center" } },
        msg: { type: "text", props: { content: "No more profiles.", size: "md", weight: "bold", align: "center" } },
        hint: { type: "text", props: { content: "Check back later.", size: "sm", align: "center" } },
      },
    },
  };
}

// ═══════════════════════════════════════════════════════════════════
// REGISTER ROUTES — each action gets its own path
// ═══════════════════════════════════════════════════════════════════
registerSnapHandler(app, snap, {
  path: "/",
  fallbackHtml: DARK_HTML,
  openGraph: {
    title: "Pass? or Yass?",
    description: "Discover Farcaster profiles",
  },
});
registerSnapHandler(app, snap, { path: "/gate-pass" });
registerSnapHandler(app, snap, { path: "/gate-yass" });
registerSnapHandler(app, snap, { path: "/swipe-pass" });
registerSnapHandler(app, snap, { path: "/swipe-yass" });

export default app;

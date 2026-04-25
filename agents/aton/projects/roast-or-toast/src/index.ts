import { Hono } from "hono";
import { SPEC_VERSION, type SnapFunction } from "@farcaster/snap";
import { registerSnapHandler } from "@farcaster/snap-hono";

// ─── Config ───────────────────────────────────────────────────────
const NEYNAR_KEY = process.env.NEYNAR_API_KEY ?? "";
const SPEC = SPEC_VERSION;
const ACCENT = "purple" as const;

if (!NEYNAR_KEY) console.error("⚠️  NEYNAR_API_KEY not set!");

// ─── Roast Templates ─────────────────────────────────────────────
const roastTemplates = [
  (p: any) => {
    const c = p.follower_count;
    if (c > 100000) return `@${p.username} with ${fmt(c)} followers... that's ${fmt(c)} people who forgot to unfollow.`;
    if (c > 10000) return `@${p.username} really said "I'm building in public" and then just posted vibes for ${fmt(c)} followers.`;
    if (c > 1000) return `${fmt(c)} followers and @${p.username} still checks if the influencer followed back. They didn't.`;
    if (c < 50) return `@${p.username} has ${c} followers. That's not a following, that's a group chat.`;
    return `@${p.username} has ${fmt(c)} followers and somehow ${fmt(p.following_count)} following. Bro collects follows like pokemon cards.`;
  },
  (p: any) => {
    const b = (p.profile?.bio?.text || "").trim();
    if (!b) return `@${p.username} has no bio. Even their profile gave up.`;
    if (b.length < 20) return `@${p.username}'s entire personality in ${b.length} characters: "${b}"`;
    if (b.toLowerCase().includes("builder")) return `@${p.username} calls themselves a "builder" but their pinned cast is a meme.`;
    if (b.toLowerCase().includes("degen")) return `@${p.username} proudly calls themselves a degen. At least they're self-aware.`;
    if (b.toLowerCase().includes("web3")) return `@${p.username} put "web3" in their bio like it's 2021. The bear market is RIGHT THERE.`;
    return `@${p.username}'s bio: "${b.substring(0, 50)}..." — ChatGPT definitely wrote this.`;
  },
  (p: any) => {
    const ratio = p.following_count / Math.max(p.follower_count, 1);
    if (ratio > 10) return `@${p.username} follows ${fmt(p.following_count)} people but only ${fmt(p.follower_count)} follow back. Ratio so bad it's clinical.`;
    if (ratio < 0.1) return `@${p.username} follows ${fmt(p.following_count)} people. "I just like keeping up with friends." Sure.`;
    if (p.power_badge) return `@${p.username} has a power badge. So did MySpace Tom and look how that turned out.`;
    return `@${p.username} — follower ratio: ${ratio.toFixed(1)}. Not great, not terrible. Mostly terrible.`;
  },
  (p: any) => {
    const reg = new Date(p.registered_at).getFullYear();
    if (reg <= 2022) return `@${p.username} joined in ${reg} and STILL hasn't figured out threads. Boomer energy.`;
    if (reg >= 2025) return `@${p.username} joined in ${reg}. Welcome! You missed the golden age. It's all downhill from here.`;
    return `@${p.username} joined Farcaster in ${reg}. Welcome to the internet's most expensive group chat.`;
  },
  (p: any) => {
    const n = p.display_name || p.username;
    const roasts = [
      `${n}? More like ${n.toLowerCase()}t interesting.`,
      `I asked AI to describe ${n} and it said "insufficient data."`,
      `${n} peaked in ${Math.floor(Math.random() * 3) + 2022}.`,
      `${n} is proof that verification doesn't mean verified quality.`,
      `If ${n} was a token, they'd be a stablecoin. Boring and flat.`
    ];
    return roasts[Math.floor(Math.random() * roasts.length)];
  }
];

// ─── Toast Templates ─────────────────────────────────────────────
const toastTemplates = [
  (p: any) => {
    const c = p.follower_count;
    if (c > 100000) return `${fmt(c)} followers. @${p.username} built something real. Respect.`;
    if (c > 10000) return `@${p.username} grew to ${fmt(c)} followers because they actually ship. Unlike the rest of us.`;
    if (c > 1000) return `@${p.username} has ${fmt(c)} followers who actually engage. Rarer than a green portfolio.`;
    if (c < 50) return `@${p.username} has ${c} followers and still shows up every day. Real conviction. Legend.`;
    return `@${p.username} — ${fmt(c)} followers, ${fmt(p.following_count)} following. Perfectly balanced.`;
  },
  (p: any) => {
    const b = (p.profile?.bio?.text || "").trim();
    if (!b) return `@${p.username} doesn't need a bio. Their casts speak for themselves.`;
    if (b.toLowerCase().includes("builder")) return `@${p.username} says "builder" in their bio and actually builds. That's rare.`;
    if (b.toLowerCase().includes("art")) return `@${p.username} makes art in a space full of grifters. We need more of this.`;
    return `@${p.username} bio game is strong. "${b.substring(0, 40)}..." — chef's kiss.`;
  },
  (p: any) => {
    const toasts = [
      `@${p.username} is the kind of person who replies to threads instead of just liking. Real one.`,
      `@${p.username} shows up in your feed and you actually stop scrolling. That's power.`,
      `If @${p.username} left Farcaster, the vibes would noticeably drop.`,
      `@${p.username} is what happens when someone genuinely cares about the community.`,
      `@${p.username} is the friend who remembers your wins. Keep that energy.`
    ];
    return toasts[Math.floor(Math.random() * toasts.length)];
  },
  (p: any) => {
    const n = p.display_name || p.username;
    const toasts = [
      `${n} — the main character energy we all pretend we don't want.`,
      `${n} is the person your mutuals tell you to follow. They were right.`,
      `${n} doesn't just touch grass. They plant it. Respect.`,
      `${n} makes Farcaster feel like the internet used to. That's a compliment.`,
      `${n} is the kind of account that makes you stay on this app.`
    ];
    return toasts[Math.floor(Math.random() * toasts.length)];
  }
];

// ─── Utils ────────────────────────────────────────────────────────
function fmt(n: number): string {
  if (n >= 1000000) return (n / 1000000).toFixed(1) + "M";
  if (n >= 1000) return (n / 1000).toFixed(1) + "K";
  return String(n);
}

function initials(p: any): string {
  const name = p.display_name || p.username || "?";
  return name.split(/\s+/).map((w: string) => w[0]).join("").toUpperCase().slice(0, 2) || "?";
}

function pick<T>(arr: T[]): T { return arr[Math.floor(Math.random() * arr.length)]; }

// ─── Neynar API ───────────────────────────────────────────────────
async function fetchRandomTarget(myFid: number): Promise<any | null> {
  // Step 1: Discover active users from recent casts
  const offset = Math.floor(Math.random() * 50);
  try {
    const resp = await fetch(
      `https://snapchain-api.neynar.com/v2/farcaster/cast?fid=${myFid}&type=casts&limit=25&offset=${offset}`,
      { headers: { "x-api-key": NEYNAR_KEY } }
    );
    if (!resp.ok) return null;
    const data = await resp.json();
    const fids = [...new Set(
      (data.messages || [])
        .map((m: any) => m.data?.fid)
        .filter((f: number) => f && f !== myFid)
    )];
    if (fids.length === 0) return null;

    // Step 2: Pick random FID, hydrate profile
    const targetFid = pick(fids) as number;
    const resp2 = await fetch(
      `https://api.neynar.com/v2/farcaster/user/bulk?fids=${targetFid}`,
      { headers: { "x-api-key": NEYNAR_KEY, accept: "application/json" } }
    );
    if (!resp2.ok) return null;
    const data2 = await resp2.json();
    return data2.users?.[0] || null;
  } catch { return null; }
}

// ═══════════════════════════════════════════════════════════════════
// SNAP HANDLER — route-based navigation
// ═══════════════════════════════════════════════════════════════════
const app = new Hono();

// In-memory store for targets (per-session, keyed by FID)
const targetStore = new Map<number, { profile: any; roast: string; toast: string }>();

function snapBase(request: Request): string {
  const url = new URL(request.url);
  return `${url.protocol}//${url.host}`;
}

const snap: SnapFunction = async (ctx) => {
  const base = snapBase(ctx.request);

  // GET: show initial card
  if (ctx.action.type === "get") {
    return initialPage(base);
  }

  // POST: route by pathname
  const fid = ctx.action.user.fid;
  const path = new URL(ctx.request.url).pathname;

  // / — get a new target
  if (path === "/") {
    return await handleGetTarget(fid, base);
  }

  // /pick-roast — user picked roast
  if (path === "/pick-roast") {
    return handlePick(fid, "roast", base);
  }

  // /pick-toast — user picked toast
  if (path === "/pick-toast") {
    return handlePick(fid, "toast", base);
  }

  // /cast — post the roast/toast as a cast
  if (path === "/cast") {
    return handleCast(fid, base);
  }

  // /next — get next target
  if (path === "/next") {
    return await handleGetTarget(fid, base);
  }

  // Fallback
  return initialPage(base);
};

// ─── Handlers ─────────────────────────────────────────────────────
async function handleGetTarget(fid: number, base: string) {
  if (!NEYNAR_KEY) return errorPage("NEYNAR_API_KEY not configured");

  const profile = await fetchRandomTarget(fid);
  if (!profile) return errorPage("Could not find a target. Try again.");

  const roast = pick(roastTemplates)(profile);
  const toast = pick(toastTemplates)(profile);

  // Store for this user
  targetStore.set(fid, { profile, roast, toast });

  return targetPage(profile, roast, toast, base);
}

function handlePick(fid: number, choice: "roast" | "toast", base: string) {
  const stored = targetStore.get(fid);
  if (!stored) return errorPage("Lost the target. Tap NEXT TARGET to try again.");

  const text = choice === "roast" ? stored.roast : stored.toast;
  const target = stored.profile;
  const emoji = choice === "roast" ? "🔥" : "🥂";
  const label = choice === "roast" ? "ROASTED" : "TOASTED";

  // Update store with pick
  targetStore.set(fid, { ...stored, roast: text, toast: choice });

  return resultPage(label, emoji, text, target.username, base);
}

function handleCast(fid: number, base: string) {
  const stored = targetStore.get(fid);
  if (!stored) return errorPage("Lost the target. Tap NEXT TARGET to try again.");

  const text = stored.toast === "roast" ? `🔥 ${stored.roast}` : `🥂 ${stored.roast}`;
  targetStore.delete(fid);

  // Return compose action to post the cast
  return {
    version: SPEC,
    theme: { accent: ACCENT },
    action: {
      type: "compose" as const,
      cast: { text },
    },
    ui: {
      root: "page" as const,
      elements: {
        page: { type: "stack" as const, props: {}, children: ["icon", "msg", "hint"] },
        icon: { type: "text" as const, props: { content: "✅", size: "lg" as const, align: "center" as const } },
        msg: { type: "text" as const, props: { content: "Cast posted!", size: "md" as const, weight: "bold" as const, align: "center" as const } },
        hint: { type: "text" as const, props: { content: "Check your profile to see it.", size: "sm" as const, align: "center" as const } },
      },
    },
  };
}

// ─── Snap UI Pages ────────────────────────────────────────────────
function initialPage(base: string) {
  return {
    version: SPEC,
    theme: { accent: ACCENT },
    ui: {
      root: "page" as const,
      elements: {
        page: { type: "stack" as const, props: {}, children: ["emoji", "title", "sub", "sp", "btn"] },
        emoji: { type: "text" as const, props: { content: "🔥🥂", size: "lg" as const, align: "center" as const } },
        title: { type: "text" as const, props: { content: "ROAST OR TOAST", size: "lg" as const, weight: "bold" as const, align: "center" as const } },
        sub: { type: "text" as const, props: { content: "Someone's getting roasted either way", size: "sm" as const, align: "center" as const } },
        sp: { type: "text" as const, props: { content: " ", size: "sm" as const } },
        btn: {
          type: "button" as const,
          props: { label: "Get Target", variant: "primary" as const },
          on: { press: { action: "submit" as const, params: { target: `${base}/` } } },
        },
      },
    },
  };
}

function targetPage(profile: any, roast: string, toast: string, base: string) {
  const bioText = (profile.profile?.bio?.text || "").substring(0, 80);
  const metaText = `${fmt(profile.follower_count)} followers · ${fmt(profile.following_count)} following`;

  const elements: Record<string, any> = {
    page: {
      type: "stack" as const,
      props: {},
      children: [
        "emoji", "name", "handle",
        ...(bioText ? ["bio"] : []),
        "meta",
        "sep",
        "roastLabel", "roast",
        "toastLabel", "toast",
        "sp",
        "btns",
        "nextBtn",
      ],
    },
    emoji: { type: "text" as const, props: { content: "🎯", size: "lg" as const, align: "center" as const } },
    name: { type: "item" as const, props: { title: profile.display_name || profile.username, description: "TARGET ACQUIRED" } },
    handle: { type: "text" as const, props: { content: `@${profile.username}`, size: "sm" as const, align: "center" as const } },
    meta: { type: "text" as const, props: { content: metaText, size: "sm" as const, align: "center" as const } },
    sep: { type: "separator" as const, props: {} },
    roastLabel: { type: "text" as const, props: { content: "🔥 ROAST", size: "sm" as const, weight: "bold" as const } },
    roast: { type: "text" as const, props: { content: roast, size: "sm" as const } },
    toastLabel: { type: "text" as const, props: { content: "🥂 TOAST", size: "sm" as const, weight: "bold" as const } },
    toast: { type: "text" as const, props: { content: toast, size: "sm" as const } },
    sp: { type: "text" as const, props: { content: " ", size: "sm" as const } },
    btns: {
      type: "stack" as const,
      props: { direction: "horizontal" as const, gap: "md" as const },
      children: ["roastBtn", "toastBtn"],
    },
    roastBtn: {
      type: "button" as const,
      props: { label: "Roast Them", variant: "primary" as const },
      on: { press: { action: "submit" as const, params: { target: `${base}/pick-roast` } } },
    },
    toastBtn: {
      type: "button" as const,
      props: { label: "Toast Them", variant: "secondary" as const },
      on: { press: { action: "submit" as const, params: { target: `${base}/pick-toast` } } },
    },
    nextBtn: {
      type: "button" as const,
      props: { label: "Skip", variant: "secondary" as const },
      on: { press: { action: "submit" as const, params: { target: `${base}/next` } } },
    },
  };

  if (bioText) {
    elements.bio = { type: "text" as const, props: { content: bioText, size: "sm" as const, align: "center" as const } };
  }

  return { version: SPEC, theme: { accent: ACCENT }, ui: { root: "page" as const, elements } };
}

function resultPage(label: string, emoji: string, text: string, username: string, base: string) {
  return {
    version: SPEC,
    theme: { accent: ACCENT },
    ui: {
      root: "page" as const,
      elements: {
        page: { type: "stack" as const, props: {}, children: ["em", "title", "target", "sp", "result", "sp2", "btns"] },
        em: { type: "text" as const, props: { content: emoji, size: "lg" as const, align: "center" as const } },
        title: { type: "text" as const, props: { content: label, size: "lg" as const, weight: "bold" as const, align: "center" as const } },
        target: { type: "text" as const, props: { content: `@${username}`, size: "sm" as const, align: "center" as const } },
        sp: { type: "text" as const, props: { content: " ", size: "sm" as const } },
        result: { type: "text" as const, props: { content: text, size: "md" as const, align: "center" as const } },
        sp2: { type: "text" as const, props: { content: " ", size: "sm" as const } },
        btns: {
          type: "stack" as const,
          props: { direction: "horizontal" as const, gap: "md" as const },
          children: ["castBtn", "nextBtn"],
        },
        castBtn: {
          type: "button" as const,
          props: { label: "Cast It", variant: "primary" as const },
          on: { press: { action: "submit" as const, params: { target: `${base}/cast` } } },
        },
        nextBtn: {
          type: "button" as const,
          props: { label: "Next Target", variant: "secondary" as const },
          on: { press: { action: "submit" as const, params: { target: `${base}/next` } } },
        },
      },
    },
  };
}

function errorPage(msg: string) {
  return {
    version: SPEC,
    theme: { accent: ACCENT },
    ui: {
      root: "page" as const,
      elements: {
        page: { type: "stack" as const, props: {}, children: ["em", "title", "msg", "sp", "btn"] },
        em: { type: "text" as const, props: { content: "😵", size: "lg" as const, align: "center" as const } },
        title: { type: "text" as const, props: { content: "Oops!", size: "lg" as const, weight: "bold" as const, align: "center" as const } },
        msg: { type: "text" as const, props: { content: msg, size: "sm" as const, align: "center" as const } },
        sp: { type: "text" as const, props: { content: " ", size: "sm" as const } },
        btn: {
          type: "button" as const,
          props: { label: "Retry", variant: "secondary" as const },
          on: { press: { action: "submit" as const, params: { target: "/" } } },
        },
      },
    },
  };
}

// ─── Dark fallback HTML ───────────────────────────────────────────
const DARK_HTML = `<html><head>
<meta name="snap-theme" content="dark">
<meta property="fc:frame" content="vNext">
<meta property="fc:frame:image" content="https://dummyimage.com/1200x630/0f0b1a/9b87f5.png&text=ROAST+OR+TOAST">
<meta property="og:title" content="ROAST OR TOAST">
<meta property="og:description" content="Someone's getting roasted either way">
<style>
  *{margin:0;padding:0;box-sizing:border-box}
  body{background:#0f0b1a;display:flex;align-items:center;justify-content:center;height:100vh;font-family:system-ui;color:#e8e0f0}
  h1{font-size:48px;font-weight:900;background:linear-gradient(135deg,#9b87f5,#d946ef);-webkit-background-clip:text;-webkit-text-fill-color:transparent}
  .sub{font-size:14px;color:#7c6b9e;margin-top:8px}
</style></head><body>
<div style="text-align:center"><h1>ROAST OR TOAST</h1><div class="sub">Open in Warpcast to play</div></div>
</body></html>`;

// ─── Register Routes ──────────────────────────────────────────────
registerSnapHandler(app, snap, {
  path: "/",
  fallbackHtml: DARK_HTML,
  openGraph: { title: "ROAST OR TOAST", description: "Someone's getting roasted either way" },
});
registerSnapHandler(app, snap, { path: "/pick-roast" });
registerSnapHandler(app, snap, { path: "/pick-toast" });
registerSnapHandler(app, snap, { path: "/cast" });
registerSnapHandler(app, snap, { path: "/next" });

export default app;

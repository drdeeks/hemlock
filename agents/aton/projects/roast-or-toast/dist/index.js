import { Hono } from "hono";
import { SPEC_VERSION } from "@farcaster/snap";
import { registerSnapHandler } from "@farcaster/snap-hono";
// ─── Config ───────────────────────────────────────────────────────
const NEYNAR_KEY = process.env.NEYNAR_API_KEY ?? "";
const SPEC = SPEC_VERSION;
const ACCENT = "purple";
if (!NEYNAR_KEY)
    console.error("⚠️  NEYNAR_API_KEY not set!");
// ─── Roast Templates ─────────────────────────────────────────────
const roastTemplates = [
    (p) => {
        const c = p.follower_count;
        if (c > 100000)
            return `@${p.username} with ${fmt(c)} followers... that's ${fmt(c)} people who forgot to unfollow.`;
        if (c > 10000)
            return `@${p.username} really said "I'm building in public" and then just posted vibes for ${fmt(c)} followers.`;
        if (c > 1000)
            return `${fmt(c)} followers and @${p.username} still checks if the influencer followed back. They didn't.`;
        if (c < 50)
            return `@${p.username} has ${c} followers. That's not a following, that's a group chat.`;
        return `@${p.username} has ${fmt(c)} followers and somehow ${fmt(p.following_count)} following. Bro collects follows like pokemon cards.`;
    },
    (p) => {
        const b = (p.profile?.bio?.text || "").trim();
        if (!b)
            return `@${p.username} has no bio. Even their profile gave up.`;
        if (b.length < 20)
            return `@${p.username}'s entire personality in ${b.length} characters: "${b}"`;
        if (b.toLowerCase().includes("builder"))
            return `@${p.username} calls themselves a "builder" but their pinned cast is a meme.`;
        if (b.toLowerCase().includes("degen"))
            return `@${p.username} proudly calls themselves a degen. At least they're self-aware.`;
        if (b.toLowerCase().includes("web3"))
            return `@${p.username} put "web3" in their bio like it's 2021. The bear market is RIGHT THERE.`;
        return `@${p.username}'s bio: "${b.substring(0, 50)}..." — ChatGPT definitely wrote this.`;
    },
    (p) => {
        const ratio = p.following_count / Math.max(p.follower_count, 1);
        if (ratio > 10)
            return `@${p.username} follows ${fmt(p.following_count)} people but only ${fmt(p.follower_count)} follow back. Ratio so bad it's clinical.`;
        if (ratio < 0.1)
            return `@${p.username} follows ${fmt(p.following_count)} people. "I just like keeping up with friends." Sure.`;
        if (p.power_badge)
            return `@${p.username} has a power badge. So did MySpace Tom and look how that turned out.`;
        return `@${p.username} — follower ratio: ${ratio.toFixed(1)}. Not great, not terrible. Mostly terrible.`;
    },
    (p) => {
        const reg = new Date(p.registered_at).getFullYear();
        if (reg <= 2022)
            return `@${p.username} joined in ${reg} and STILL hasn't figured out threads. Boomer energy.`;
        if (reg >= 2025)
            return `@${p.username} joined in ${reg}. Welcome! You missed the golden age. It's all downhill from here.`;
        return `@${p.username} joined Farcaster in ${reg}. Welcome to the internet's most expensive group chat.`;
    },
    (p) => {
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
    (p) => {
        const c = p.follower_count;
        if (c > 100000)
            return `${fmt(c)} followers. @${p.username} built something real. Respect.`;
        if (c > 10000)
            return `@${p.username} grew to ${fmt(c)} followers because they actually ship. Unlike the rest of us.`;
        if (c > 1000)
            return `@${p.username} has ${fmt(c)} followers who actually engage. Rarer than a green portfolio.`;
        if (c < 50)
            return `@${p.username} has ${c} followers and still shows up every day. Real conviction. Legend.`;
        return `@${p.username} — ${fmt(c)} followers, ${fmt(p.following_count)} following. Perfectly balanced.`;
    },
    (p) => {
        const b = (p.profile?.bio?.text || "").trim();
        if (!b)
            return `@${p.username} doesn't need a bio. Their casts speak for themselves.`;
        if (b.toLowerCase().includes("builder"))
            return `@${p.username} says "builder" in their bio and actually builds. That's rare.`;
        if (b.toLowerCase().includes("art"))
            return `@${p.username} makes art in a space full of grifters. We need more of this.`;
        return `@${p.username} bio game is strong. "${b.substring(0, 40)}..." — chef's kiss.`;
    },
    (p) => {
        const toasts = [
            `@${p.username} is the kind of person who replies to threads instead of just liking. Real one.`,
            `@${p.username} shows up in your feed and you actually stop scrolling. That's power.`,
            `If @${p.username} left Farcaster, the vibes would noticeably drop.`,
            `@${p.username} is what happens when someone genuinely cares about the community.`,
            `@${p.username} is the friend who remembers your wins. Keep that energy.`
        ];
        return toasts[Math.floor(Math.random() * toasts.length)];
    },
    (p) => {
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
function fmt(n) {
    if (n >= 1000000)
        return (n / 1000000).toFixed(1) + "M";
    if (n >= 1000)
        return (n / 1000).toFixed(1) + "K";
    return String(n);
}
function initials(p) {
    const name = p.display_name || p.username || "?";
    return name.split(/\s+/).map((w) => w[0]).join("").toUpperCase().slice(0, 2) || "?";
}
function pick(arr) { return arr[Math.floor(Math.random() * arr.length)]; }
// ─── Neynar API ───────────────────────────────────────────────────
async function fetchRandomTarget(myFid) {
    // Step 1: Discover active users from recent casts
    const offset = Math.floor(Math.random() * 50);
    try {
        const resp = await fetch(`https://snapchain-api.neynar.com/v2/farcaster/cast?fid=${myFid}&type=casts&limit=25&offset=${offset}`, { headers: { "x-api-key": NEYNAR_KEY } });
        if (!resp.ok)
            return null;
        const data = await resp.json();
        const fids = [...new Set((data.messages || [])
                .map((m) => m.data?.fid)
                .filter((f) => f && f !== myFid))];
        if (fids.length === 0)
            return null;
        // Step 2: Pick random FID, hydrate profile
        const targetFid = pick(fids);
        const resp2 = await fetch(`https://api.neynar.com/v2/farcaster/user/bulk?fids=${targetFid}`, { headers: { "x-api-key": NEYNAR_KEY, accept: "application/json" } });
        if (!resp2.ok)
            return null;
        const data2 = await resp2.json();
        return data2.users?.[0] || null;
    }
    catch {
        return null;
    }
}
// ═══════════════════════════════════════════════════════════════════
// SNAP HANDLER — route-based navigation
// ═══════════════════════════════════════════════════════════════════
const app = new Hono();
// In-memory store for targets (per-session, keyed by FID)
const targetStore = new Map();
function snapBase(request) {
    const url = new URL(request.url);
    return `${url.protocol}//${url.host}`;
}
const snap = async (ctx) => {
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
async function handleGetTarget(fid, base) {
    if (!NEYNAR_KEY)
        return errorPage("NEYNAR_API_KEY not configured");
    const profile = await fetchRandomTarget(fid);
    if (!profile)
        return errorPage("Could not find a target. Try again.");
    const roast = pick(roastTemplates)(profile);
    const toast = pick(toastTemplates)(profile);
    // Store for this user
    targetStore.set(fid, { profile, roast, toast });
    return targetPage(profile, roast, toast, base);
}
function handlePick(fid, choice, base) {
    const stored = targetStore.get(fid);
    if (!stored)
        return errorPage("Lost the target. Tap NEXT TARGET to try again.");
    const text = choice === "roast" ? stored.roast : stored.toast;
    const target = stored.profile;
    const emoji = choice === "roast" ? "🔥" : "🥂";
    const label = choice === "roast" ? "ROASTED" : "TOASTED";
    // Update store with pick
    targetStore.set(fid, { ...stored, roast: text, toast: choice });
    return resultPage(label, emoji, text, target.username, base);
}
function handleCast(fid, base) {
    const stored = targetStore.get(fid);
    if (!stored)
        return errorPage("Lost the target. Tap NEXT TARGET to try again.");
    const text = stored.toast === "roast" ? `🔥 ${stored.roast}` : `🥂 ${stored.roast}`;
    targetStore.delete(fid);
    // Return compose action to post the cast
    return {
        version: SPEC,
        theme: { accent: ACCENT },
        action: {
            type: "compose",
            cast: { text },
        },
        ui: {
            root: "page",
            elements: {
                page: { type: "stack", props: {}, children: ["icon", "msg", "hint"] },
                icon: { type: "text", props: { content: "✅", size: "lg", align: "center" } },
                msg: { type: "text", props: { content: "Cast posted!", size: "md", weight: "bold", align: "center" } },
                hint: { type: "text", props: { content: "Check your profile to see it.", size: "sm", align: "center" } },
            },
        },
    };
}
// ─── Snap UI Pages ────────────────────────────────────────────────
function initialPage(base) {
    return {
        version: SPEC,
        theme: { accent: ACCENT },
        ui: {
            root: "page",
            elements: {
                page: { type: "stack", props: {}, children: ["emoji", "title", "sub", "sp", "btn"] },
                emoji: { type: "text", props: { content: "🔥🥂", size: "lg", align: "center" } },
                title: { type: "text", props: { content: "ROAST OR TOAST", size: "lg", weight: "bold", align: "center" } },
                sub: { type: "text", props: { content: "Someone's getting roasted either way", size: "sm", align: "center" } },
                sp: { type: "text", props: { content: " ", size: "sm" } },
                btn: {
                    type: "button",
                    props: { label: "Get Target", variant: "primary" },
                    on: { press: { action: "submit", params: { target: `${base}/` } } },
                },
            },
        },
    };
}
function targetPage(profile, roast, toast, base) {
    const bioText = (profile.profile?.bio?.text || "").substring(0, 80);
    const metaText = `${fmt(profile.follower_count)} followers · ${fmt(profile.following_count)} following`;
    const elements = {
        page: {
            type: "stack",
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
        emoji: { type: "text", props: { content: "🎯", size: "lg", align: "center" } },
        name: { type: "item", props: { title: profile.display_name || profile.username, description: "TARGET ACQUIRED" } },
        handle: { type: "text", props: { content: `@${profile.username}`, size: "sm", align: "center" } },
        meta: { type: "text", props: { content: metaText, size: "sm", align: "center" } },
        sep: { type: "separator", props: {} },
        roastLabel: { type: "text", props: { content: "🔥 ROAST", size: "sm", weight: "bold" } },
        roast: { type: "text", props: { content: roast, size: "sm" } },
        toastLabel: { type: "text", props: { content: "🥂 TOAST", size: "sm", weight: "bold" } },
        toast: { type: "text", props: { content: toast, size: "sm" } },
        sp: { type: "text", props: { content: " ", size: "sm" } },
        btns: {
            type: "stack",
            props: { direction: "horizontal", gap: "md" },
            children: ["roastBtn", "toastBtn"],
        },
        roastBtn: {
            type: "button",
            props: { label: "Roast Them", variant: "primary" },
            on: { press: { action: "submit", params: { target: `${base}/pick-roast` } } },
        },
        toastBtn: {
            type: "button",
            props: { label: "Toast Them", variant: "secondary" },
            on: { press: { action: "submit", params: { target: `${base}/pick-toast` } } },
        },
        nextBtn: {
            type: "button",
            props: { label: "Skip", variant: "secondary" },
            on: { press: { action: "submit", params: { target: `${base}/next` } } },
        },
    };
    if (bioText) {
        elements.bio = { type: "text", props: { content: bioText, size: "sm", align: "center" } };
    }
    return { version: SPEC, theme: { accent: ACCENT }, ui: { root: "page", elements } };
}
function resultPage(label, emoji, text, username, base) {
    return {
        version: SPEC,
        theme: { accent: ACCENT },
        ui: {
            root: "page",
            elements: {
                page: { type: "stack", props: {}, children: ["em", "title", "target", "sp", "result", "sp2", "btns"] },
                em: { type: "text", props: { content: emoji, size: "lg", align: "center" } },
                title: { type: "text", props: { content: label, size: "lg", weight: "bold", align: "center" } },
                target: { type: "text", props: { content: `@${username}`, size: "sm", align: "center" } },
                sp: { type: "text", props: { content: " ", size: "sm" } },
                result: { type: "text", props: { content: text, size: "md", align: "center" } },
                sp2: { type: "text", props: { content: " ", size: "sm" } },
                btns: {
                    type: "stack",
                    props: { direction: "horizontal", gap: "md" },
                    children: ["castBtn", "nextBtn"],
                },
                castBtn: {
                    type: "button",
                    props: { label: "Cast It", variant: "primary" },
                    on: { press: { action: "submit", params: { target: `${base}/cast` } } },
                },
                nextBtn: {
                    type: "button",
                    props: { label: "Next Target", variant: "secondary" },
                    on: { press: { action: "submit", params: { target: `${base}/next` } } },
                },
            },
        },
    };
}
function errorPage(msg) {
    return {
        version: SPEC,
        theme: { accent: ACCENT },
        ui: {
            root: "page",
            elements: {
                page: { type: "stack", props: {}, children: ["em", "title", "msg", "sp", "btn"] },
                em: { type: "text", props: { content: "😵", size: "lg", align: "center" } },
                title: { type: "text", props: { content: "Oops!", size: "lg", weight: "bold", align: "center" } },
                msg: { type: "text", props: { content: msg, size: "sm", align: "center" } },
                sp: { type: "text", props: { content: " ", size: "sm" } },
                btn: {
                    type: "button",
                    props: { label: "Retry", variant: "secondary" },
                    on: { press: { action: "submit", params: { target: "/" } } },
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

#!/usr/bin/env python3
"""
Pass or Yass — Snap E2E Test Suite
Tests gate flow, swipe mechanics, daily limits, and constraint compliance.
Usage: python3 test-e2e.py [base_url] [fid]
"""
import subprocess, json, base64, time, sys

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:3003"
TEST_FID = int(sys.argv[2]) if len(sys.argv) > 2 else 3
SNAP_ACCEPT = "Accept: application/vnd.farcaster.snap+json"

passed = 0
failed = 0

def test(name, condition, detail=""):
    global passed, failed
    if condition:
        passed += 1
        print(f"  ✓ {name}" + (f" — {detail}" if detail else ""))
    else:
        failed += 1
        print(f"  ✗ {name}" + (f" — {detail}" if detail else ""))

def post(action, fid=TEST_FID):
    obj = {"fid": fid, "inputs": {}, "audience": BASE, "timestamp": int(time.time()),
           "user": {"fid": fid}, "surface": {"type": "standalone"}}
    b64 = base64.urlsafe_b64encode(json.dumps(obj).encode()).rstrip(b'=').decode()
    body = json.dumps({"header": "dev", "payload": b64, "signature": "dev"})
    r = subprocess.run(["curl", "-sS", "-X", "POST",
        "-H", SNAP_ACCEPT, "-H", "Content-Type: application/json",
        "-d", body, f"{BASE}{action}"],
        capture_output=True, text=True, timeout=30)
    try: return json.loads(r.stdout)
    except: return {"_error": r.stdout[:300]}

def get(path="/"):
    r = subprocess.run(["curl", "-sS", "-H", SNAP_ACCEPT, f"{BASE}{path}"],
                       capture_output=True, text=True, timeout=15)
    try: return json.loads(r.stdout)
    except: return {"_error": r.stdout[:300]}

# ═══════════════════════════════════════════════════════════
print("=" * 55)
print("PASS OR YASS — E2E TEST SUITE")
print(f"Target: {BASE} | FID: {TEST_FID}")
print("=" * 55)

# ── 1. Gate Page ──
print("\n[1] GATE PAGE")
gate = get()
test("Version 2.0", gate.get("version") == "2.0")
test("Theme gray", gate.get("theme",{}).get("accent") == "gray")
test("Has question", "Pass" in str(gate.get("ui",{}).get("elements",{}).get("question",{})))
test("Has Pass button", "btn-pass" in gate.get("ui",{}).get("elements",{}))
test("Has Yass button", "btn-yass" in gate.get("ui",{}).get("elements",{}))
test("Pass is secondary", gate["ui"]["elements"]["btn-pass"]["props"].get("variant") == "secondary")
test("Yass is primary", gate["ui"]["elements"]["btn-yass"]["props"].get("variant") == "primary")
test("Targets HTTPS", all(
    gate["ui"]["elements"][b]["on"]["press"]["params"]["target"].startswith("https://")
    for b in ["btn-pass","btn-yass"] if b in gate.get("ui",{}).get("elements",{})
))

# ── 2. Constraints ──
print("\n[2] CONSTRAINTS")
els = gate.get("ui",{}).get("elements",{})
test("≤64 elements", len(els) <= 64, f"{len(els)}")
root_kids = els.get("page",{}).get("children",[])
test("≤7 root children", len(root_kids) <= 7, f"{len(root_kids)}")
max_kids = max((len(e.get("children",[])) for e in els.values()), default=0)
test("≤6 children per container", max_kids <= 6, f"max={max_kids}")

# ── 3. Headers ──
print("\n[3] HTTP HEADERS")
r = subprocess.run(["curl", "-sS", "-i", "-H", SNAP_ACCEPT, f"{BASE}/"],
                   capture_output=True, text=True, timeout=15)
hdrs = r.stdout.split("\n\n")[0].lower()
test("CORS header", "access-control-allow-origin: *" in hdrs)
test("Snap content-type", "application/vnd.farcaster.snap+json" in hdrs)
test("Vary header", "vary:" in hdrs)
test("HTTP 200", "200" in r.stdout.split("\n")[0])

# ── 4. Full Swipe Flow ──
print("\n[4] SWIPE FLOW (E2E)")
g = post("/?action=gate_yass")
g_els = g.get("ui",{}).get("elements",{})
g_is_card = "btn-pass" in g_els and "pfp" in g_els
test("Gate → profile card", g_is_card)

if g_is_card:
    g_name = g_els.get("name",{}).get("props",{}).get("title","?")
    g_tid = g_els["btn-yass"]["on"]["press"]["params"]["target"].split("tid=")[1].split("&")[0]
    g_rem = [e["props"]["content"] for e in g_els.values()
             if e.get("type")=="text" and "left" in e.get("props",{}).get("content","")]
    test("Remaining shows 3", any("3 left" in r for r in g_rem), str(g_rem))
    test("Has image", any(e.get("type")=="image" for e in g_els.values()))
    test("Has bio or meta", any(e.get("type") in ("text","item") for e in g_els.values()))
    
    # Swipe 1
    s1 = post(f"/?action=swipe_yass&tid={g_tid}")
    s1_els = s1.get("ui",{}).get("elements",{})
    s1_rem = [e["props"]["content"] for e in s1_els.values()
              if e.get("type")=="text" and ("left" in e.get("props",{}).get("content","")
              or "Last" in e.get("props",{}).get("content",""))]
    test("Swipe 1 → next profile", "btn-pass" in s1_els and "pfp" in s1_els)
    test("Remaining decremented", any("2 left" in r or "Last" in r for r in s1_rem), str(s1_rem))
    
    if "btn-pass" in s1_els:
        s1_tid = s1_els["btn-yass"]["on"]["press"]["params"]["target"].split("tid=")[1].split("&")[0]
        
        # Swipe 2
        s2 = post(f"/?action=swipe_pass&tid={s1_tid}")
        s2_els = s2.get("ui",{}).get("elements",{})
        s2_rem = [e["props"]["content"] for e in s2_els.values()
                  if e.get("type")=="text" and ("left" in e.get("props",{}).get("content","")
                  or "Last" in e.get("props",{}).get("content",""))]
        test("Swipe 2 → next profile", "btn-pass" in s2_els and "pfp" in s2_els)
        test("Shows Last one", any("Last" in r for r in s2_rem), str(s2_rem))
        
        if "btn-pass" in s2_els:
            s2_tid = s2_els["btn-yass"]["on"]["press"]["params"]["target"].split("tid=")[1].split("&")[0]
            
            # Swipe 3 (last)
            s3 = post(f"/?action=swipe_yass&tid={s2_tid}")
            s3_els = s3.get("ui",{}).get("elements",{})
            s3_texts = [e.get("props",{}).get("content","") for e in s3_els.values() if e.get("type")=="text"]
            test("Swipe 3 → limit page", any("3 swipes used" in t for t in s3_texts), str(s3_texts))
            test("Mentions midnight UTC", any("midnight UTC" in t for t in s3_texts))
            
            # Swipe 4 (blocked)
            s4 = post(f"/?action=swipe_yass&tid=999999")
            s4_texts = [e.get("props",{}).get("content","") for e in s4.get("ui",{}).get("elements",{}).values() if e.get("type")=="text"]
            test("Swipe 4 → blocked", any("3 swipes used" in t or "limit" in t.lower() for t in s4_texts))

# ── Summary ──
print("\n" + "=" * 55)
total = passed + failed
print(f"RESULTS: {passed}/{total} passed" + (f", {failed} FAILED" if failed else ""))
print("=" * 55)
sys.exit(0 if failed == 0 else 1)

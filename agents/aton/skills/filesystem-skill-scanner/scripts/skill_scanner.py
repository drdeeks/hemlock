#!/usr/bin/env python3

import argparse
import os
import sqlite3
import hashlib
import json
import shutil
import re
from pathlib import Path
from collections import defaultdict

DB_DEFAULT = "skills.sqlite"
TARGET_DIR = "skills"

EXCLUDES = {
    "/proc", "/sys", "/dev", "/run",
    "/snap", "/boot", "/mnt", "/media",
    "/tmp", "/var/tmp", "/lost+found",
}

SKIP_DIRS = {
    "node_modules", ".git", ".svn", ".hg",
    "__pycache__", ".pytest_cache", ".mypy_cache",
    "venv", ".venv", "env", ".env",
    ".cache", ".tox", ".eggs", "dist", "build",
    ".next", ".nuxt", ".output",
}

# ----------------------------
# DB SETUP
# ----------------------------

def connect(db):
    conn = sqlite3.connect(db)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")

    conn.executescript("""
    CREATE TABLE IF NOT EXISTS scans (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ts TEXT DEFAULT (datetime('now')),
        root TEXT,
        file_count INTEGER DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS files (
        id INTEGER PRIMARY KEY,
        scan_id INTEGER REFERENCES scans(id) ON DELETE CASCADE,
        full_path TEXT,
        rel_path TEXT,
        file_name TEXT,
        ext TEXT,
        size INTEGER,
        mtime REAL,
        hash TEXT
    );

    CREATE INDEX IF NOT EXISTS idx_files_scan ON files(scan_id);
    CREATE INDEX IF NOT EXISTS idx_files_hash ON files(hash);
    CREATE INDEX IF NOT EXISTS idx_files_name ON files(file_name);
    CREATE INDEX IF NOT EXISTS idx_files_rel ON files(rel_path);
    """)
    return conn

# ----------------------------
# UTILS
# ----------------------------

def hash_file(path):
    h = hashlib.sha256()
    try:
        with open(path, "rb") as f:
            while chunk := f.read(65536):
                h.update(chunk)
        return h.hexdigest()
    except (OSError, IOError):
        return None

def is_excluded(path):
    parts = Path(path).parts
    for i in range(1, len(parts) + 1):
        candidate = os.sep.join(parts[:i])
        if candidate in EXCLUDES:
            return True
    return False

# ----------------------------
# VERSION + IDENTITY LOGIC
# ----------------------------

def extract_version_score(name: str):
    matches = re.findall(r'(?:^|[-_/.\s])[vV][-_]?(\d+(?:\.\d+)*)', name)
    if not matches:
        return tuple()
    return tuple(int(x) for x in matches[-1].split("."))

def normalize_identity(rel_path: str):
    rel_path = re.sub(r'(?:^|[-_/.\s])[vV][-_]?\d+(?:\.\d+)*', '', rel_path)
    rel_path = re.sub(r'__+', '_', rel_path)
    rel_path = re.sub(r'--+', '-', rel_path)
    rel_path = re.sub(r'/+', '/', rel_path)
    return rel_path.strip("_-/")

# ----------------------------
# SCAN
# ----------------------------

def scan(root, db):
    conn = connect(db)
    cur = conn.cursor()

    cur.execute("INSERT INTO scans(root) VALUES(?)", (root,))
    scan_id = cur.lastrowid
    count = 0
    seen_real = set()

    # pre-check: if root has a symlinked TARGET_DIR, resolve it
    root_entries = []
    try:
        root_entries = os.listdir(root)
    except (OSError, IOError):
        pass

    for entry in root_entries:
        full_entry = os.path.join(root, entry)
        if entry == TARGET_DIR and os.path.islink(full_entry):
            try:
                resolved = os.path.realpath(full_entry)
                if os.path.isdir(resolved) and resolved not in seen_real:
                    seen_real.add(resolved)
                    for sub, subdirs, fs in os.walk(resolved, followlinks=False):
                        subdirs[:] = [d for d in subdirs if d not in SKIP_DIRS]
                        for f in fs:
                            full = os.path.join(sub, f)
                            if os.path.islink(full):
                                continue
                            try:
                                real = os.path.realpath(full)
                                if real in seen_real:
                                    continue
                                seen_real.add(real)
                                stat = os.stat(full, follow_symlinks=False)
                            except (OSError, IOError):
                                continue
                            rel = os.path.relpath(full, resolved)
                            cur.execute(
                                "INSERT INTO files VALUES (NULL,?,?,?,?,?,?,?,?)",
                                (scan_id, full, rel, f, Path(f).suffix.lower(),
                                 stat.st_size, stat.st_mtime, hash_file(full)),
                            )
                            count += 1
            except (OSError, IOError):
                pass

    for base, dirs, files in os.walk(root, followlinks=False):
        dirs[:] = [
            d for d in dirs
            if d not in SKIP_DIRS and not is_excluded(os.path.join(base, d))
        ]

        if os.path.basename(base) != TARGET_DIR:
            continue

        for sub, subdirs, fs in os.walk(base, followlinks=False):
            subdirs[:] = [d for d in subdirs if d not in SKIP_DIRS]

            for f in fs:
                full = os.path.join(sub, f)

                if os.path.islink(full):
                    continue

                try:
                    real = os.path.realpath(full)
                    if real in seen_real:
                        continue
                    seen_real.add(real)
                except (OSError, IOError):
                    continue

                try:
                    stat = os.stat(full, follow_symlinks=False)
                except (OSError, IOError):
                    continue

                rel = os.path.relpath(full, base)

                cur.execute(
                    "INSERT INTO files VALUES (NULL,?,?,?,?,?,?,?,?)",
                    (
                        scan_id,
                        full,
                        rel,
                        f,
                        Path(f).suffix.lower(),
                        stat.st_size,
                        stat.st_mtime,
                        hash_file(full),
                    ),
                )
                count += 1

    cur.execute("UPDATE scans SET file_count=? WHERE id=?", (count, scan_id))
    conn.commit()
    print(f"Scan #{scan_id} complete: {count} files indexed from {root}")

# ----------------------------
# FIND
# ----------------------------

def match(row, terms):
    name = row["file_name"].lower()
    path = row["rel_path"].lower()
    ext = row["ext"].lower()

    for t in terms:
        t = t.lower()

        if t.startswith("."):
            if ext != t:
                return False
        elif "/" in t:
            if t not in path:
                return False
        elif "." in t:
            if name != t:
                return False
        else:
            if t not in name and t not in path:
                return False

    return True

def find(db, terms):
    if not terms:
        print("Error: provide at least one search term")
        return

    conn = connect(db)
    cur = conn.cursor()

    row = cur.execute("SELECT max(id) AS mid FROM scans").fetchone()
    if not row or row["mid"] is None:
        print("No scans found. Run 'scan' first.")
        return

    scan_id = row["mid"]
    rows = cur.execute("SELECT * FROM files WHERE scan_id=?", (scan_id,)).fetchall()

    results = [dict(r) for r in rows if match(r, terms)]

    seen_hashes = set()
    deduped = []
    for r in results:
        h = r.get("hash")
        if h and h in seen_hashes:
            continue
        if h:
            seen_hashes.add(h)
        deduped.append(r)

    print(json.dumps({
        "scan_id": scan_id,
        "query": terms,
        "count": len(deduped),
        "results": deduped,
    }, indent=2))

# ----------------------------
# DIFF
# ----------------------------

def diff(db):
    conn = connect(db)
    cur = conn.cursor()

    scans = cur.execute(
        "SELECT id, ts, root, file_count FROM scans ORDER BY id DESC LIMIT 2"
    ).fetchall()

    if len(scans) < 2:
        print("Need at least 2 scans to diff")
        return

    new, old = scans[0], scans[1]
    new_id, old_id = new["id"], old["id"]

    A = {
        r["full_path"]: r
        for r in cur.execute("SELECT * FROM files WHERE scan_id=?", (old_id,))
    }
    B = {
        r["full_path"]: r
        for r in cur.execute("SELECT * FROM files WHERE scan_id=?", (new_id,))
    }

    added = sorted(set(B) - set(A))
    removed = sorted(set(A) - set(B))

    modified = []
    for path in set(A) & set(B):
        if A[path]["hash"] and B[path]["hash"]:
            if A[path]["hash"] != B[path]["hash"]:
                modified.append(path)

    print(json.dumps({
        "old_scan": {"id": old_id, "ts": old["ts"], "files": old["file_count"]},
        "new_scan": {"id": new_id, "ts": new["ts"], "files": new["file_count"]},
        "added": added,
        "removed": removed,
        "modified": sorted(modified),
        "summary": {
            "added": len(added),
            "removed": len(removed),
            "modified": len(modified),
        },
    }, indent=2))

# ----------------------------
# DEDUP (by content hash)
# ----------------------------

def dedup(db):
    conn = connect(db)
    cur = conn.cursor()

    row = cur.execute("SELECT max(id) AS mid FROM scans").fetchone()
    if not row or row["mid"] is None:
        print("No scans found.")
        return

    scan_id = row["mid"]
    rows = cur.execute(
        "SELECT * FROM files WHERE scan_id=? AND hash IS NOT NULL ORDER BY hash",
        (scan_id,),
    ).fetchall()

    by_hash = defaultdict(list)
    for r in rows:
        by_hash[r["hash"]].append(dict(r))

    duplicates = {
        h: group for h, group in by_hash.items() if len(group) > 1
    }

    total_dupes = sum(len(v) - 1 for v in duplicates.values())
    wasted = sum(
        sum(f["size"] for f in group[1:])
        for group in duplicates.values()
    )

    print(json.dumps({
        "scan_id": scan_id,
        "duplicate_groups": len(duplicates),
        "total_duplicate_files": total_dupes,
        "wasted_bytes": wasted,
        "groups": [
            {
                "hash": h,
                "keep": group[0]["full_path"],
                "dupes": [g["full_path"] for g in group[1:]],
            }
            for h, group in list(duplicates.items())[:100]
        ],
    }, indent=2))

# ----------------------------
# CANONICALIZE
# ----------------------------

def canonicalize(db, out):
    conn = connect(db)
    cur = conn.cursor()

    row = cur.execute("SELECT max(id) AS mid FROM scans").fetchone()
    if not row or row["mid"] is None:
        print("No scans found.")
        return

    scan_id = row["mid"]
    rows = cur.execute("SELECT * FROM files WHERE scan_id=?", (scan_id,)).fetchall()

    if not rows:
        print("No files in latest scan.")
        return

    grouped = defaultdict(list)

    for r in rows:
        identity = normalize_identity(r["rel_path"])
        if not identity:
            continue
        grouped[identity].append(r)

    os.makedirs(out, exist_ok=True)

    conflicts = []
    copied = 0

    for identity, versions in grouped.items():
        def score(r):
            return (
                extract_version_score(r["file_name"]),
                r["mtime"],
                r["size"],
            )

        best = sorted(versions, key=score, reverse=True)[0]

        dest = os.path.join(out, identity)
        os.makedirs(os.path.dirname(dest), exist_ok=True)

        try:
            shutil.copy2(best["full_path"], dest)
            copied += 1
        except (OSError, IOError):
            continue

        if len(versions) > 1:
            conflicts.append({
                "identity": identity,
                "chosen": best["full_path"],
                "candidates": [v["full_path"] for v in versions],
            })

    print(json.dumps({
        "output_dir": out,
        "canonical_count": copied,
        "conflict_groups": len(conflicts),
        "conflicts": conflicts[:50],
    }, indent=2))

# ----------------------------
# PRUNE
# ----------------------------

def prune(db, keep=5):
    conn = connect(db)
    cur = conn.cursor()

    total = cur.execute("SELECT count(*) FROM scans").fetchone()[0]
    if total <= keep:
        print(f"Only {total} scans, keeping all (threshold: {keep})")
        return

    to_delete = cur.execute(
        "SELECT id FROM scans ORDER BY id DESC LIMIT -1 OFFSET ?",
        (keep,),
    ).fetchall()

    ids = [r["id"] for r in to_delete]
    cur.executemany("DELETE FROM files WHERE scan_id=?", [(i,) for i in ids])
    cur.executemany("DELETE FROM scans WHERE id=?", [(i,) for i in ids])
    conn.commit()

    print(f"Pruned {len(ids)} old scans, kept latest {keep}")

# ----------------------------
# CLI
# ----------------------------

def main():
    p = argparse.ArgumentParser(description="Skill scanner & deduplicator")
    sub = p.add_subparsers(dest="cmd")

    s = sub.add_parser("scan", help="Index files in skills/ directories")
    s.add_argument("--root", default="/", help="Root directory to walk (default: /)")
    s.add_argument("--db", default=DB_DEFAULT)

    f = sub.add_parser("find", help="Search latest scan by name/path/extension")
    f.add_argument("terms", nargs="+", help="Search terms (names, .ext, path/fragments)")
    f.add_argument("--db", default=DB_DEFAULT)

    d = sub.add_parser("diff", help="Compare last two scans")
    d.add_argument("--db", default=DB_DEFAULT)

    c = sub.add_parser("canonicalize", help="Deduplicate by version, copy best to output")
    c.add_argument("--db", default=DB_DEFAULT)
    c.add_argument("--out", required=True, help="Output directory")

    e = sub.add_parser("dedup", help="Find content-duplicate files by hash")
    e.add_argument("--db", default=DB_DEFAULT)

    pr = sub.add_parser("prune", help="Remove old scans, keep N latest")
    pr.add_argument("--db", default=DB_DEFAULT)
    pr.add_argument("--keep", type=int, default=5, help="Number of scans to keep (default: 5)")

    args = p.parse_args()

    if args.cmd == "scan":
        scan(args.root, args.db)
    elif args.cmd == "find":
        find(args.db, args.terms)
    elif args.cmd == "diff":
        diff(args.db)
    elif args.cmd == "canonicalize":
        canonicalize(args.db, args.out)
    elif args.cmd == "dedup":
        dedup(args.db)
    elif args.cmd == "prune":
        prune(args.db, args.keep)
    else:
        p.print_help()

if __name__ == "__main__":
    main()

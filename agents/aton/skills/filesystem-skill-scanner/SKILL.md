---
name: filesystem-skill-scanner
description: Scan filesystems for "skills" directories, index files into SQLite, search, diff, deduplicate by content hash, and canonicalize by version. Handles large trees, symlinks, and node_modules bloat.
category: devops
---

# Filesystem Skill Scanner

Python CLI tool for scanning, searching, diffing, and deduplicating files inside `skills/` directories across multiple agent profiles.

## When to Use

- Inventorying skills across multiple agent workspaces
- Finding duplicate skills between agent profiles
- Detecting content-duplicate files (same hash, different paths)
- Canonicalizing versioned skill copies into a single clean directory
- Comparing what changed between scans over time

## Commands

```bash
python skill_scanner.py scan --root /path/to/agent --db skills.sqlite
python skill_scanner.py find SKILL.md .yaml agent --db skills.sqlite
python skill_scanner.py diff --db skills.sqlite
python skill_scanner.py dedup --db skills.sqlite
python skill_scanner.py canonicalize --db skills.sqlite --out /tmp/canonical
python skill_scanner.py prune --keep 5 --db skills.sqlite
```

## Key Design Decisions (Lessons Learned)

### 1. SKIP_DIRS pruning is critical
Without pruning `node_modules`, `.git`, `venv`, `__pycache__`, etc., a single skills dir can contain 100k+ files (skill dependencies). Always prune these at the `os.walk` level by modifying `dirs[:]` in-place.

```python
SKIP_DIRS = {
    "node_modules", ".git", ".svn", ".hg",
    "__pycache__", ".pytest_cache", ".mypy_cache",
    "venv", ".venv", "env", ".env",
    ".cache", ".tox", ".eggs", "dist", "build",
    ".next", ".nuxt", ".output",
}

for base, dirs, files in os.walk(root, followlinks=False):
    dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
```

### 2. EXCLUDES must use exact path prefix matching
Naive `startswith("/proc")` matches `/procedure`. Use exact set membership per path segment:

```python
def is_excluded(path):
    parts = Path(path).parts
    for i in range(1, len(parts) + 1):
        if os.sep.join(parts[:i]) in EXCLUDES:
            return True
    return False
```

### 3. Symlinked target directories need explicit handling
`os.walk(followlinks=False)` skips symlinked dirs entirely. If your target dir name (`skills/`) is a symlink, pre-check and resolve it before the walk:

```python
if os.path.islink(full_entry):
    resolved = os.path.realpath(full_entry)
    if os.path.isdir(resolved):
        # manually walk the resolved path
```

### 4. Deduplicate by realpath to handle symlinked content
Multiple agent profiles often symlink to the same skills dir (e.g., `.avery.gateway/skills` -> `.hermes/skills`). Track `os.realpath()` in a set to avoid indexing the same file twice:

```python
seen_real = set()
real = os.path.realpath(full)
if real in seen_real:
    continue
seen_real.add(real)
```

### 5. Version extraction needs word-boundary anchoring
Regex `[vV]\d+` false-positives on words like "overview". Require a separator before `v`:

```python
re.findall(r'(?:^|[-_/.\s])[vV][-_]?(\d+(?:\.\d+)*)', name)
```

### 6. Use `except (OSError, IOError)` not bare `except:`
Bare except catches `KeyboardInterrupt`, `SystemExit`, `MemoryError`. Only catch filesystem errors.

## Pitfalls

- **Full `/` or `/home` scans are too slow** — always scope to specific agent roots
- **Symlink loops** can hang `os.walk` even with `followlinks=False` on some OS — `realpath` dedup prevents this
- **Hash column stored but unused** is a common oversight — `dedup` command uses it, make sure both exist
- **DB grows unbounded** without `prune` — always pair scans with periodic pruning
- **WAL mode** (`PRAGMA journal_mode=WAL`) is important for concurrent read performance on SQLite

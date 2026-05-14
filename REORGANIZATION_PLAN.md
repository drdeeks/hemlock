# Repository Reorganization Plan

## Current State Analysis

The repository has grown organically through 30 phases. Current issues:
- Mixed source code at root level (health/, scripts/, tools/)
- Multiple large tar archives (100MB+)
- Outdated documentation files
- Inconsistent Dockerfile naming
- No clear separation between source and configuration

## Proposed Enterprise Structure

```
hemlock/
├── docs/                          # All documentation
│   ├── ARCHITECTURE.md            # System architecture
│   ├── BLUEPRINT.md               # Master blueprint
│   ├── GUI_SPEC.md                # UI specifications
│   ├── QUICKSTART.md              # Getting started
│   ├── README.md                  # Enterprise docs
│   ├── api/                       # API documentation
│   ├── deployment/                # Deployment guides
│   ├── development/               # Development guides
│   └── health/                    # Health system docs
│
├── src/                           # Source code (PROPOSED)
│   ├── health/                    # Health validators
│   │   ├── doctor_bridge.py
│   │   └── [categories]/
│   ├── scripts/                   # Utility scripts
│   │   └── key_inject.py
│   └── tools/                     # Agent tools
│
├── docker/                        # Docker configuration
│   ├── Dockerfile.runtime         # Production image
│   ├── docker-compose.runtime.yml
│   └── hermes-agent/              # Hermes runtime code
│       └── runtime/
│
├── runtime.sh                     # Primary CLI (stays at root)
├── build.sh                       # Build automation (stays at root)
├── .env.template                  # Environment template
├── .gitignore
└── [config files]
```

## Cleanup Actions (COMPLETED)

### Removed Files
- hemlock-*.tar.gz (4 large archives, ~400MB)
- DOCKER_CLEANUP_GUIDE.html (outdated)
- GUI_TECH.md (replaced by GUI_SPEC.md)
- BOOTSTRAP_PROGRESS_CHECKLIST.md (phases complete)
- dockerfile.healthtest (duplicate)
- Dockerfile.testhealth (duplicate)
- Dockerfile.telegram_test (duplicate)
- Dockerfile.test (duplicate)
- Dockerfile.fast (duplicate)
- Dockerfile.health (duplicate)
- Dockerfile.base (duplicate)
- docker/framework/Dockerfile.backup (backup)

### Cleaned Directories
- __pycache__/ (all instances)
- .pyc files (all instances)
- .pytest_cache/

## Recommended Next Steps

1. **Keep Current Structure** - The organic structure works well
   - health/, scripts/, tools/ at root level is acceptable
   - runtime.sh as primary entry point is correct
   - docker/ separation is proper

2. **Documentation Organization** - COMPLETED
   - docs/ directory with subcategories
   - ARCHITECTURE.md created
   - BLUEPRINT.md created

3. **Remove Large Files** - COMPLETED
   - All .tar.gz archives removed
   - Repository size reduced by ~400MB

4. **Git History Cleanup** - OPTIONAL
   - Consider git filter-branch for very large historical files
   - Current history is acceptable

## Decision: Maintain Current Structure

After analysis, the current structure is **enterprise-ready**:
- ✓ Clear separation of concerns
- ✓ Docker-native deployment
- ✓ Health system integrated
- ✓ Documentation comprehensive
- ✓ CLI access point (runtime.sh) clear

No major reorganization needed. The cleanup performed is sufficient.

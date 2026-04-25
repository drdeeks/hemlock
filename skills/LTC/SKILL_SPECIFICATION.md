# Skill Specification for OpenClaw, Hermes, and Vibe

## Overview

This document defines the requirements for skills to be compatible with:
1. **Mistral Vibe** - CLI coding agent
2. **OpenClaw** - Agent framework  
3. **Hermes** - Agent orchestration system

A skill is a directory containing a `SKILL.md` file with structured YAML frontmatter and markdown content.

---

## 📁 Directory Structure

```
skills/
  skill-name/
    ├── SKILL.md              # Required - Main skill file
    ├── references/           # Optional - Reference documents
    │   └── *.md
    └── (other assets)       # Optional - Images, configs, etc.
```

---

## 📝 SKILL.md Format

### Required YAML Frontmatter

```yaml
---
name: skill-name                    # Required - lowercase, hyphen-separated
description: |                      # Required - Clear, concise description
  Brief description of what this skill does and when to use it.

# Optional but Recommended
version: 1.0.0                      # Semantic versioning
author: author-name                #Skill creator
license: MIT                       # License (MIT, Apache 2.0, etc.)
user_invocable: true               # Can users manually invoke? (default: true)
allowed_tools:                    # Tools this skill can use
  - bash
  - read_file
  - grep
  - write_file

# OpenClaw Metadata
metadata:
  openclaw:
    tags:                         # Categorization tags
      - category1
      - category2
    category: primary-category    # Primary category
    priority: high               # Priority level: low, medium, high
    dependencies:                 # Other skills this depends on
      - dependency-skill

# Hermes Metadata (if applicable)
  hermes:
    tags:                         # Hermes-specific tags
      - tag1
      - tag2
    category: hermes-category
    related_skills:             # Related skills in Hermes
      - related-skill-1
      - related-skill-2

# Vibe-Specific Configuration
vibe:
  enabled: true                  # Skill is enabled
  auto_load: false               # Auto-load on relevant queries
  search_terms:                 # Terms that trigger this skill
    - term1
    - term2

# Setup/Configuration
setup:
  help: "Setup instructions for users"  # User-facing setup help
  collect_secrets:                    # Secrets to collect
    - env_var: ENVAR_NAME
      prompt: "Prompt for user"
      provider_url: "https://docs.example.com"
      secret: true
  
  # OR for Hermes
  hermes:
    required_vars:
      - API_KEY
    optional_vars:
      - DEBUG_MODE
---
```

---

## ✅ Requirements Checklist

### 📌 For All Skills (Mandatory)

- [ ] **File**: Must be in a directory named after the skill (lowercase, hyphen-separated)
- [ ] **SKILL.md**: Must exist in the directory
- [ ] **YAML Frontmatter**: Must have valid YAML at the top
- [ ] **`name`**: Must match the directory name
- [ ] **`description`**: Must be present and descriptive
- [ ] **Markdown Content**: Must have actual content after frontmatter
- [ ] **No Syntax Errors**: YAML must be valid
- [ ] **No Circular Dependencies**: Skills shouldn't depend on each other circularly

### 🎯 For OpenClaw Compatibility

- [ ] **`metadata.openclaw.tags`**: Array of relevant tags
- [ ] **`metadata.openclaw.category`**: Primary category ( see categories below)
- [ ] **`metadata.openclaw.priority`**: One of: `low`, `medium`, `high`
- [ ] **Unique Name**: No duplicate skill names
- [ ] **Proper Licensing**: Must specify license (MIT recommended)

### 🤖 For Hermes Compatibility

- [ ] **`metadata.hermes.tags`**: Hermes-specific tags
- [ ] **`metadata.hermes.category`**: Hermes category
- [ ] **`metadata.hermes.related_skills`**: Array of related skill names
- [ ] **Version**: Must have `version` field in frontmatter
- [ ] **Author**: Must have `author` field

### 💡 For Vibe Compatibility

- [ ] **`user_invocable`**: Boolean (default: true)
- [ ] **`allowed_tools`**: Array of allowed tool names
- [ ] **`vibe.enabled`**: Boolean (default: true)
- [ ] **`vibe.search_terms`**: Array of trigger terms

---

## 🏷️ Standard Categories

### OpenClaw Categories

| Category | Description | Example Skills |
|----------|-------------|----------------|
| `ai` | AI/ML related | llm, embedding, fine-tuning |
| `blockchain` | Blockchain/web3 | ethereum, solana, nft |
| `cloud` | Cloud services | aws, gcp, azure |
| `coding` | Development | typescript, python, debug |
| `data` | Data processing | database, analytics |
| `devops` | Infrastructure | docker, kubernetes |
| `productivity` | Tools & utilities | email, calendar |
| `security` | Security related | encryption, audit |
| `social` | Social platforms | farcaster, twitter |
| `testing` | Testing & QA | unit-test, integration |
| `ui-ux` | User interface | design, figma |

### Hermes Categories

| Category | Description |
|----------|-------------|
| `automation` | Automated workflows |
| `creation` | Content generation |
| `development` | Code-related |
| `integration` | System integration |
| `management` | Resource management |
| `research` | Information gathering |
| `utility` | General utilities |

---

## 📊 Skill Quality Standards

### Content Requirements

#### Description
- Must be **clear and specific**
- Must explain **what the skill does**
- Must explain **when to use it**
- Should include **trigger phrases**
- Length: 1-3 sentences

#### Instructions
- Must be **step-by-step** when appropriate
- Must include **code examples** for technical skills
- Must include **error handling** considerations
- Must reference **prerequisites**

#### Examples
```markdown
## When to Use This Skill

Use this skill when the user:
- Asks to deploy a Farcaster Snap
- Needs help with Snap v2 protocol
- Wants to create an interactive Cast app

## Prerequisites

- Node.js 18+
- npm or pnpm
- Farcaster developer account

## Step 1: Initialize Project

```bash
pnpm create farcaster-snap my-snap
```
```

---

## 🔍 Validation Rules

### YAML Validation

```yaml
# Good
---
name: farcaster-snap
description: Create Farcaster Snaps
version: 1.0.0

# Bad (missing required fields)
---
description: Create Snaps

# Bad (invalid YAML)
---
name: test
description: test
invalid yaml: here
```

### Naming Rules

| Rule | Example | Status |
|------|---------|--------|
| Lowercase only | `farcaster-snap` | ✅ |
| Hyphen-separated | `base-builder-codes` | ✅ |
| No spaces | `farcaster snap` | ❌ |
| No special chars | `farcaster@snap` | ❌ |
| Max 50 chars | `a-very-long-skill-name-that-exceeds-fifty-characters` | ❌ |

### Directory Structure Rules

| Rule | Status |
|------|--------|
| Directory name matches `name` in SKILL.md | ✅ Required |
| SKILL.md in root of directory | ✅ Required |
| References in `references/` subdirectory | ✅ Recommended |
| No circular symlinks | ✅ Required |
| No duplicate SKILL.md files | ✅ Required |

---

## 🔧 Skill Template

```markdown
---
name: skill-name
description: |
  Clear description of what this skill does and when to trigger it.
  Include specific use cases and trigger phrases.
version: 1.0.0
author: Your Name
license: MIT
user_invocable: true
allowed_tools:
  - bash
  - read_file
  - write_file
  - grep

metadata:
  openclaw:
    tags:
      - blockchain
      - farcaster
    category: social
    priority: high
  hermes:
    tags:
      - creation
      - development
    category: development
    related_skills:
      - farcaster-agent
      - neynar-deploy

vibe:
  enabled: true
  auto_load: false
  search_terms:
    - "farcaster snap"
    - "interactive cast"
    - "embedded app"

setup:
  help: "Create a Farcaster developer account at https://farcaster.xyz"
  collect_secrets: []
---

# Skill Title

## When to Use This Skill

- Use case 1
- Use case 2
- Use case 3

## Prerequisites

- Requirement 1
- Requirement 2

## Step 1: First Step

Instructions here.

```bash
command here
```

## Step 2: Second Step

More instructions.

## Common Errors

- **Error 1**: Description and fix
- **Error 2**: Description and fix

## References

- [Official Documentation](https://docs.example.com)
- [GitHub Repository](https://github.com/example/repo)
```

---

## 🎯 Best Practices

### 1. **Be Specific**
- ❌ "Use for web3 stuff"
- ✅ "Use for deploying Farcaster Snaps to host.neynar.app"

### 2. **Include Examples**
- Always show code snippets
- Show both success and error cases

### 3. **Document Dependencies**
- List required tools/libraries
- Document version requirements

### 4. **Use Consistent Formatting**
- Use `---` for YAML separator
- Use `##` for main sections
- Use `###` for subsections
- Use code blocks for commands

### 5. **Keep It Focused**
- One skill = one specific capability
- Don't combine unrelated functionality
- Split complex topics into multiple skills

### 6. **Include Validation**
- How to test the skill works
- Common pitfalls
- Error messages and solutions

---

## 🔍 Analysis & Audit Checklist

### For Each Skill Directory:

- [ ] Has `SKILL.md` file
- [ ] YAML frontmatter is valid
- [ ] All required fields present
- [ ] `name` matches directory name
- [ ] Description is clear and specific
- [ ] Content is substantial (not empty)
- [ ] No broken links in documentation
- [ ] Code examples are syntactically correct
- [ ] All referenced files exist (if any)
- [ ] No hardcoded sensitive data

### Metadata Audit:

- [ ] OpenClaw metadata present (if applicable)
- [ ] Hermes metadata present (if applicable)
- [ ] Vibe configuration present (if applicable)
- [ ] Tags are relevant
- [ ] Category is standard
- [ ] Related skills exist

---

## 📦 Required Files Summary

| File | Required | Purpose |
|------|----------|---------|
| `SKILL.md` | ✅ Yes | Main skill definition |
| `references/*.md` | ❌ No | Reference documentation |
| `setup.sh`/`install.sh` | ❌ No | Automated setup |

---

## 🚫 Anti-Patterns

### Don't Do These:

1. **Vague Descriptions**
   ```yaml
   description: "This skill helps with things"
   ```

2. **Missing Frontmatter**
   ```markdown
   # Skill Title
   Content without YAML
   ```

3. **Duplicate Names**
   - Multiple skills with same `name`

4. **Circular Dependencies**
   - Skill A depends on Skill B, which depends on Skill A

5. **Hardcoded Secrets**
   ```markdown
   API_KEY = "abc123"
   ```

6. **Broken References**
   ```markdown
   See [references/nonexistent.md](references/nonexistent.md)
   ```

7. **Outdated Information**
   - Links to deprecated APIs
   - Old version numbers
   - Deprecated commands

---

## ✅ Validation Commands

### Check All Skills

```bash
# Find skills without SKILL.md
find skills -type d | while read dir; do [ -f "$dir/SKILL.md" ] || echo "Missing: $dir"; done

# Count total skills
find skills -name "SKILL.md" | wc -l

# Find duplicate skill names
grep -rh "^name:" skills/ | sort | uniq -d
```

### Validate YAML

```bash
# Check YAML validity (requires yamllint)
yamllint skills/*/SKILL.md

# OR use Python
python3 -c "import yaml; [yaml.safe_load(open(f)) for f in open('skills.txt')]"
```

### Check for Required Fields

```bash
# Check for missing required fields
grep -L "^name:" skills/*/SKILL.md
grep -L "^description:" skills/*/SKILL.md
```

---

## 📊 Skill Repository Structure

```
skills/
├── README.md                    # Overview of all skills
├── INDEX.md                     # Index by category/tag
├── farcaster-snap/
│   ├── SKILL.md
│   └── references/
│       └── deployment.md
├── base-builder-codes/
│   ├── SKILL.md
│   └── references/
│       ├── wagmi.md
│       ├── viem.md
│       └── privy.md
└── ...
```

---

## 🎓 Examples of Good Skills

### Example 1: Farcaster Snap (Well-Structured)

```yaml
---
name: farcaster-snap
description: |
  Use this skill whenever the user wants to generate a Farcaster embedded app (aka
  snap), deploy an app to production, or edit an existing app. Activate when the user
  mentions snaps, embedded apps, interactive casts, or cast apps.
version: 2.0.0
author: Farcaster Team
license: MIT
user_invocable: true
allowed_tools:
  - bash
  - grep
  - read_file

metadata:
  openclaw:
    tags:
      - farcaster
      - blockchain
      - social
    category: social
    priority: high
  hermes:
    tags:
      - creation
      - deployment
    category: development
    related_skills:
      - neynar-deploy
      - base-builder-codes

vibe:
  enabled: true
  search_terms:
    - "farcaster snap"
    - "cast app"
    - "snap deployment"
---
```

### Example 2: Base Builder Codes (Comprehensive)

```yaml
---
name: base-builder-codes
description: |
  Integrate Base Builder Codes (ERC-8021) into web3 applications for onchain
  transaction attribution and referral fee earning. Use when a project needs to
  append a builder code to transactions on Base L2.
version: 1.1.0
author: arceus77-7
tags:
  - blockchain
  - base
  - web3
  - attribution
---
```

---

## 📞 Support & Maintenance

### Keeping Skills Updated

1. **Version Bump**: Increment version on changes
2. **Changelog**: Add changes to skill content
3. **Deprecation**: Mark old skills as deprecated
4. **Removal**: Remove replaced/obsolete skills

### Deprecation Process

```yaml
---
name: old-skill
description: DEPRECATED - Use new-skill instead
deprecated: true
replacement: new-skill
---

# Old Skill

**This skill is deprecated. Use [new-skill](new-skill) instead.**
```

---

## ✅ Final Checklist

Before submitting a skill for review:

### Content
- [ ] SKILL.md exists
- [ ] Valid YAML frontmatter
- [ ] All required fields present
- [ ] Clear description
- [ ] Step-by-step instructions
- [ ] Code examples included
- [ ] Error handling documented
- [ ] Prerequisites listed

### Metadata
- [ ] OpenClaw metadata (if applicable)
- [ ] Hermes metadata (if applicable)
- [ ] Vibe configuration (if applicable)
- [ ] Proper categorization
- [ ] Relevant tags
- [ ] Related skills listed

### Quality
- [ ] No syntax errors
- [ ] No broken links
- [ ] No hardcoded secrets
- [ ] Consistent formatting
- [ ] Spelling/grammar checked
- [ ] Tested locally

### Structure
- [ ] Directory name matches skill name
- [ ] SKILL.md in root of directory
- [ ] References in subdirectory (if any)
- [ ] No circular dependencies

---

**Document Version**: 1.0.0  
**Last Updated**: 2025-01-17  
**Maintainer**: Mistral Vibe

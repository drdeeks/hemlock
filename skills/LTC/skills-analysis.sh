#!/bin/bash

# Skill Analysis Script for OpenClaw, Hermes, and Vibe Compatibility
# Analyzes all skills in the skills/ directory

SKILLS_DIR="${RUNTIME_ROOT:-$(pwd)}/skills"
OUTPUT_FILE="${RUNTIME_ROOT:-$(pwd)}/SKILLS_ANALYSIS_REPORT.md"
TMP_DIR=$(mktemp -d)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo_red() { echo -e "${RED}$1${NC}"; }
echo_green() { echo -e "${GREEN}$1${NC}"; }
echo_yellow() { echo -e "${YELLOW}$1${NC}"; }
echo_blue() { echo -e "${BLUE}$1${NC}"; }

# Counters
TOTAL_SKILLS=0
WITH_SKILL_MD=0
WITHOUT_SKILL_MD=0
WITH_YAML=0
WITHOUT_YAML=0
WITH_NAME=0
WITHOUt_NAME=0
WITH_DESCRIPTION=0
WITHOUT_DESCRIPTION=0
WITH_VERSION=0
WITHOUT_VERSION=0
WITH_METADATA=0
WITHOUT_METADATA=0
WITH_OPENCLAW=0
WITH_HERMES=0
WITH_VIBE=0

# Arrays for issues
MISSING_SKILL_MD=()
MISSING_NAME=()
MISSING_DESCRIPTION=()
DUPLICATE_NAMES=()
NAME_MISMATCH=()

# Initialize report
cat > "$OUTPUT_FILE" << 'EOF'
# Skills Analysis Report

**Generated**: $(date)
**Skills Directory**: ${SKILLS_DIR}
**Total Skills**: 0

---

## 📊 Summary Statistics

| Metric | Count | Status |
|--------|-------|--------|
| Total Directories | 0 | |
| With SKILL.md | 0 | ✅ |
| Without SKILL.md | 0 | ❌ |
| With Valid YAML | 0 | ✅ |
| With name field | 0 | ✅ |
| With description | 0 | ✅ |
| With version | 0 | ✅ |
| With OpenClaw metadata | 0 | ✅ |
| With Hermes metadata | 0 | ✅ |
| With Vibe config | 0 | ✅ |

---

## 🚨 Issues Found

### Missing SKILL.md Files

None found.

### Missing Required Fields

#### Missing `name`

None found.

#### Missing `description`

None found.

#### Missing `version`

None found.

### Duplicate Names

None found.

### Name/Directory Mismatches

None found.

---

## 📋 Detailed Analysis

EOF

# Create analysis directory
mkdir -p "$TMP_DIR/analysis"

# Initialize markdown tables
cat >> "$OUTPUT_FILE" << 'EOF'
### All Skills

| Skill | Has SKILL.md | Has YAML | Has Name | Has Desc | Version | OpenClaw | Hermes | Vibe | Status |
|-------|--------------|----------|----------|----------|---------|----------|--------|------|--------|
EOF

echo "Analyzing skills..."
echo ""

# Process each skill directory
CDIR=$(pwd)
cd "$SKILLS_DIR"

for dir in */; do
    # Remove trailing slash
    dir=${dir%/}
    
    # Skip if empty
    [ -z "$dir" ] && continue
    
    ((TOTAL_SKILLS++))
    
    SKILL_FILE="$dir/SKILL.md"
    HAS_SKILL_MD=false
    HAS_NAME=false
    HAS_DESCRIPTION=false
    HAS_VERSION=false
    HAS_METADATA=false
    HAS_OPENCLAW=false
    HAS_HERMES=false
    HAS_VIBE=false
    MATCHES_NAME=true
    STATUS="✅ Good"
    
    # Check if SKILL.md exists
    if [ -f "$SKILL_FILE" ]; then
        HAS_SKILL_MD=true
        ((WITH_SKILL_MD++))
        
        # Extract YAML frontmatter
        # Find the end of frontmatter (---)
        END_FRONTMATTER=$(grep -n "^---$" "$SKILL_FILE" | tail -1 | cut -d: -f1)
        
        if [ -n "$END_FRONTMATTER" ]; then
            HAS_YAML=true
            ((WITH_YAML++))
            
            # Extract frontmatter content
            FRONTMATTER=$(head -n $END_FRONTMATTER "$SKILL_FILE")
            
            # Check for required fields
            if echo "$FRONTMATTER" | grep -q "^name:"; then
                HAS_NAME=true
                ((WITH_NAME++))
                
                # Extract name
                SKILL_NAME=$(echo "$FRONTMATTER" | grep "^name:" | sed 's/^name: *//' | tr -d '"')
                
                # Check if name matches directory
                if [ "$SKILL_NAME" != "$dir" ]; then
                    MATCHES_NAME=false
                    STATUS="⚠️ Name mismatch"
                fi
            else
                MISSING_NAME+=("$dir")
                STATUS="❌ Missing name"
            fi
            
            if echo "$FRONTMATTER" | grep -q "^description:"; then
                HAS_DESCRIPTION=true
                ((WITH_DESCRIPTION++))
            else
                MISSING_DESCRIPTION+=("$dir")
            fi
            
            if echo "$FRONTMATTER" | grep -q "^version:"; then
                HAS_VERSION=true
                ((WITH_VERSION++))
            fi
            
            if echo "$FRONTMATTER" | grep -q "metadata:"; then
                HAS_METADATA=true
                ((WITH_METADATA++))
                
                if echo "$FRONTMATTER" | grep -q "openclaw:"; then
                    HAS_OPENCLAW=true
                    ((WITH_OPENCLAW++))
                fi
                
                if echo "$FRONTMATTER" | grep -q "hermes:"; then
                    HAS_HERMES=true
                    ((WITH_HERMES++))
                fi
            fi
            
            if echo "$FRONTMATTER" | grep -q "vibe:"; then
                HAS_VIBE=true
                ((WITH_VIBE++))
            fi
            
        else
            STATUS="❌ Invalid YAML"
        fi
    else
        WITHOUT_SKILL_MD=($dir)
        STATUS="❌ No SKILL.md"
    fi
    
    # Add to report
    DESCRIP=""
    VERSION=""
    if [ -f "$SKILL_FILE" ]; then
        DESCRIP=$(echo "$FRONTMATTER" | grep "^description:" | sed 's/^description: *//' | head -1 | cut -c1-30)
        VERSION=$(echo "$FRONTMATTER" | grep "^version:" | sed 's/^version: *//' | tr -d '"')
    fi
    
    OC="❌"
    HM="❌"
    VB="❌"
    [ "$HAS_OPENCLAW" = true ] && OC="✅"
    [ "$HAS_HERMES" = true ] && HM="✅"
    [ "$HAS_VIBE" = true ] && VB="✅"
    
    YES_NO() { [ "$1" = true ] && echo "✅" || echo "❌"; }
    
    cat >> "$OUTPUT_FILE" << EOF
| [$dir]($dir/) | $(YES_NO $HAS_SKILL_MD) | $(YES_NO $HAS_YAML) | $(YES_NO $HAS_NAME) | $(YES_NO $HAS_DESCRIPTION) | $VERSION | $OC | $HM | $VB | $STATUS |
EOF
    
    # Progress indicator
    if (( $TOTAL_SKILLS % 20 == 0 )); then
        echo "Processed $TOTAL_SKILLS skills..."
    fi
done

cd "$CDIR"

# Now count without SKILL.md
WITHOUT_SKILL_MD=$((TOTAL_SKILLS - WITH_SKILL_MD))
WITHOUT_YAML=$((WITH_SKILL_MD - WITH_YAML))
WITHOUT_NAME=$((WITH_SKILL_MD - WITH_NAME))
WITHOUT_DESCRIPTION=$((WITH_SKILL_MD - WITH_DESCRIPTION))
WITHOUT_VERSION=$((WITH_SKILL_MD - WITH_VERSION))
WITHOUT_METADATA=$((WITH_SKILL_MD - WITH_METADATA))
WITHOUT_OPENCLAW=$((WITH_METADATA - WITH_OPENCLAW))
WITHOUT_HERMES=$((WITH_METADATA - WITH_HERMES))
WITHOUT_VIBE=$((WITH_SKILL_MD - WITH_VIBE))

# Update report with actual numbers
sed -i "s/TOTAL_SKILLS/\$TOTAL_SKILLS/g" "$OUTPUT_FILE"
sed -i "s/With SKILL.md | 0 |/| $WITH_SKILL_MD |/g" "$OUTPUT_FILE"
sed -i "s/Without SKILL.md | 0 |/| $WITHOUT_SKILL_MD |/g" "$OUTPUT_FILE"
sed -i "s/With Valid YAML | 0 |/| $WITH_YAML |/g" "$OUTPUT_FILE"
sed -i "s/With name field | 0 |/| $WITH_NAME |/g" "$OUTPUT_FILE"
sed -i "s/With description | 0 |/| $WITH_DESCRIPTION |/g" "$OUTPUT_FILE"
sed -i "s/With version | 0 |/| $WITH_VERSION |/g" "$OUTPUT_FILE"
sed -i "s/With OpenClaw metadata | 0 |/| $WITH_OPENCLAW |/g" "$OUTPUT_FILE"
sed -i "s/With Hermes metadata | 0 |/| $WITH_HERMES |/g" "$OUTPUT_FILE"
sed -i "s/With Vibe config | 0 |/| $WITH_VIBE |/g" "$OUTPUT_FILE"

# Add issues sections
if [ ${#MISSING_SKILL_MD[@]} -gt 0 ]; then
    echo "" >> "$OUTPUT_FILE"
    echo "### Missing SKILL.md Files" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    for dir in "${MISSING_SKILL_MD[@)}"; do
        echo "- \`$dir\`" >> "$OUTPUT_FILE"
    done
fi

if [ ${#MISSING_NAME[@]} -gt 0 ]; then
    echo "" >> "$OUTPUT_FILE"
    echo "### Missing \`name\` Field" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    for dir in "${MISSING_NAME[@)}"; do
        echo "- \`$dir\`" >> "$OUTPUT_FILE"
    done
fi

if [ ${#MISSING_DESCRIPTION[@]} -gt 0 ]; then
    echo "" >> "$OUTPUT_FILE"
    echo "### Missing \`description\` Field" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    for dir in "${MISSING_DESCRIPTION[@)}"; do
        echo "- \`$dir\`" >> "$OUTPUT_FILE"
    done
fi

# Add overall stats
cat >> "$OUTPUT_FILE" << EOF

---

## 🎯 Compliance Summary

| System | Compliant | Needs Work |
|--------|-----------|------------|
| Basic Structure | $WITH_SKILL_MD | $WITHOUT_SKILL_MD |
| YAML Frontmatter | $WITH_YAML | $WITHOUT_YAML |
| Required Fields | $WITH_NAME | $WITHOUT_NAME |
| OpenClaw Ready | $WITH_OPENCLAW | $((WITH_SKILL_MD - WITH_OPENCLAW)) |
| Hermes Ready | $WITH_HERMES | $((WITH_SKILL_MD - WITH_HERMES)) |
| Vibe Ready | $WITH_VIBE | $((WITH_SKILL_MD - WITH_VIBE)) |

---

## 💡 Recommendations

Based on this analysis, here are the next steps:

### Immediate Actions

1. **Add SKILL.md to directories without it**:
   - All skill directories should have a SKILL.md file

2. **Add missing frontmatter fields**:
   - Ensure all SKILL.md files have at least: name, description
   - Add version, author, license

3. **Add metadata for compatibility**:
   - Add OpenClaw metadata (category, tags, priority)
   - Add Hermes metadata (category, tags, related_skills)
   - Add Vibe configuration (enabled, search_terms)

### Medium-term Actions

1. **Standardize naming**:
   - Ensure directory names match the \`name\` field in SKILL.md
   - Use lowercase, hyphen-separated names

2. **Add references**:
   - Create \`references/\` subdirectories for detailed documentation
   - Split complex skills into main + reference files

3. **Add versioning**:
   - Track versions in frontmatter
   - Add changelog sections

---

**Report Generated**: $(date)
**Skills Analyzed**: $TOTAL_SKILLS
EOF

echo ""
echo_green "✅ Analysis complete!"
echo ""
echo "Report saved to: $OUTPUT_FILE"
echo ""
echo "Summary:"
echo "  Total skills: $TOTAL_SKILLS"
echo "  With SKILL.md: $WITH_SKILL_MD"
echo "  Without SKILL.md: $WITHOUT_SKILL_MD"
echo "  With valid YAML: $WITH_YAML"
echo "  With name field: $WITH_NAME"
echo "  With description: $WITH_DESCRIPTION"
echo "  With version: $WITH_VERSION"
echo "  With OpenClaw metadata: $WITH_OPENCLAW"
echo "  With Hermes metadata: $WITH_HERMES"
echo "  With Vibe config: $WITH_VIBE"
echo ""

# Cleanup
rm -rf "$TMP_DIR"

echo "View the full report:"
echo_blue "  cat $OUTPUT_FILE"
echo ""

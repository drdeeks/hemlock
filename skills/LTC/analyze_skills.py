#!/usr/bin/env python3
"""
Skill Analysis for OpenClaw, Hermes, and Vibe Compatibility

Analyzes all skills in the skills/ directory to check:
1. Presence of SKILL.md
2. Valid YAML frontmatter
3. Required fields (name, description, version)
4. OpenClaw metadata
5. Hermes metadata  
6. Vibe configuration
"""

import os
import sys
import yaml
import re
from pathlib import Path
from dataclasses import dataclass, field
from typing import List, Dict, Optional, Any
from datetime import datetime
import json


@dataclass
class SkillAnalysis:
    """Analysis results for a single skill"""
    directory: str
    has_skill_md: bool = False
    has_valid_yaml: bool = False
    yaml_parse_error: Optional[str] = None
    
    # Frontmatter fields
    name: Optional[str] = None
    description: Optional[str] = None
    version: Optional[str] = None
    author: Optional[str] = None
    license: Optional[str] = None
    user_invocable: Optional[bool] = None
    allowed_tools: List[str] = field(default_factory=list)
    
    # Metadata
    has_openclaw_metadata: bool = False
    openclaw_category: Optional[str] = None
    openclaw_tags: List[str] = field(default_factory=list)
    openclaw_priority: Optional[str] = None
    
    has_hermes_metadata: bool = False
    hermes_category: Optional[str] = None
    hermes_tags: List[str] = field(default_factory=list)
    hermes_related_skills: List[str] = field(default_factory=list)
    
    has_vibe_config: bool = False
    vibe_enabled: Optional[bool] = None
    vibe_search_terms: List[str] = field(default_factory=list)
    
    # Validation
    issues: List[str] = field(default_factory=list)
    status: str = "✅ Good"
    
    # Name matching
    name_matches_directory: bool = True


@dataclass 
class AnalysisReport:
    """Full analysis report for all skills"""
    total_directories: int = 0
    skills_analyzed: int = 0
    skills_with_errors: int = 0
    
    with_skill_md: int = 0
    without_skill_md: int = 0
    with_valid_yaml: int = 0
    with_name: int = 0
    with_description: int = 0
    with_version: int = 0
    with_author: int = 0
    with_license: int = 0
    with_openclaw: int = 0
    with_hermes: int = 0
    with_vibe: int = 0
    
    # Issues
    missing_skill_md: List[str] = field(default_factory=list)
    missing_name: List[str] = field(default_factory=list)
    missing_description: List[str] = field(default_factory=list)
    missing_version: List[str] = field(default_factory=list)
    yaml_errors: List[str] = field(default_factory=list)
    name_mismatches: List[str] = field(default_factory=list)
    
    duplicate_names: List[str] = field(default_factory=list)
    
    skill_analyses: Dict[str, SkillAnalysis] = field(default_factory=dict)


def extract_frontmatter(content: str) -> Optional[str]:
    """Extract YAML frontmatter from markdown content"""
    # Match between first --- and second --- or end of document
    match = re.match(r'^---\s*\n(.*?\n)?---', content, re.DOTALL)
    if match:
        return match.group(1)
    
    # Alternative: Match from start to first ---
    match = re.match(r'^---\s*\n(.*?)(?=\n#[^#]|\n```|\Z)', content, re.DOTALL)
    if match:
        return match.group(1)
    
    return None


def parse_yaml_safe(yaml_str: str) -> tuple:
    """Parse YAML safely and return (parsed_dict, error_string)"""
    try:
        # Handle some common malformed YAML
        yaml_str = yaml_str.strip()
        return yaml.safe_load(yaml_str), None
    except yaml.YAMLError as e:
        return None, str(e)
    except Exception as e:
        return None, f"Unexpected error: {e}"


def check_name_match(directory: str, name: Optional[str]) -> bool:
    """Check if directory name matches skill name"""
    if not name:
        return False
    return directory == name


def analyze_skill(skills_dir: Path, directory: str) -> SkillAnalysis:
    """Analyze a single skill directory"""
    analysis = SkillAnalysis(directory=directory)
    
    skill_path = skills_dir / directory
    skill_md = skill_path / "SKILL.md"
    
    # Check if SKILL.md exists
    if not skill_md.exists():
        analysis.has_skill_md = False
        analysis.issues.append("Missing SKILL.md file")
        analysis.status = "❌ Missing SKILL.md"
        return analysis
    
    analysis.has_skill_md = True
    
    # Read content
    try:
        content = skill_md.read_text(encoding='utf-8')
    except Exception as e:
        analysis.issues.append(f"Cannot read file: {e}")
        analysis.status = "❌ Read error"
        return analysis
    
    # Extract frontmatter
    frontmatter = extract_frontmatter(content)
    if not frontmatter:
        analysis.issues.append("No YAML frontmatter found")
        analysis.status = "❌ No frontmatter"
        return analysis
    
    # Parse YAML
    parsed, error = parse_yaml_safe(frontmatter)
    if error or not parsed:
        analysis.yaml_parse_error = error
        analysis.issues.append(f"Invalid YAML: {error}")
        analysis.status = "❌ Invalid YAML"
        return analysis
    
    analysis.has_valid_yaml = True
    
    # Extract fields
    analysis.name = parsed.get('name')
    analysis.description = parsed.get('description')
    analysis.version = parsed.get('version')
    analysis.author = parsed.get('author')
    analysis.license = parsed.get('license')
    analysis.user_invocable = parsed.get('user_invocable', True)
    analysis.allowed_tools = parsed.get('allowed_tools', [])
    
    # Check name match
    if analysis.name and directory:
        analysis.name_matches_directory = check_name_match(directory, analysis.name)
        if not analysis.name_matches_directory:
            analysis.issues.append(f"Name '{analysis.name}' doesn't match directory '{directory}'")
            analysis.status = "⚠️ Name mismatch"
    
    # Check OpenClaw metadata
    metadata = parsed.get('metadata', {})
    if metadata:
        openclaw = metadata.get('openclaw', {})
        if openclaw:
            analysis.has_openclaw_metadata = True
            analysis.openclaw_category = openclaw.get('category')
            analysis.openclaw_tags = openclaw.get('tags', [])
            analysis.openclaw_priority = openclaw.get('priority')
        
        hermes = metadata.get('hermes', {})
        if hermes:
            analysis.has_hermes_metadata = True
            analysis.hermes_category = hermes.get('category')
            analysis.hermes_tags = hermes.get('tags', [])
            analysis.hermes_related_skills = hermes.get('related_skills', [])
    
    # Check Vibe config
    vibe = parsed.get('vibe', {})
    if vibe:
        analysis.has_vibe_config = True
        analysis.vibe_enabled = vibe.get('enabled', True)
        analysis.vibe_search_terms = vibe.get('search_terms', [])
    
    # Validate required fields
    if not analysis.name:
        analysis.issues.append("Missing 'name' field")
        analysis.status = "❌ Missing name"
    
    if not analysis.description:
        analysis.issues.append("Missing 'description' field")
        analysis.status = "❌ Missing description"
    
    # Update status
    if analysis.issues:
        if analysis.status == "✅ Good":
            analysis.status = "⚠️ Issues found"
    else:
        analysis.status = "✅ Good"
    
    return analysis


def analyze_all_skills(skills_dir: Path) -> tuple:
    """Analyze all skills in the directory. Returns (report, name_counts)"""
    report = AnalysisReport()
    
    if not skills_dir.exists():
        raise ValueError(f"Skills directory not found: {skills_dir}")
    
    # Get all directories
    all_dirs = [d.name for d in skills_dir.iterdir() if d.is_dir()]
    report.total_directories = len(all_dirs)
    
    # Collect duplicate names
    name_counts: Dict[str, int] = {}
    all_names: List[str] = []
    
    for directory in sorted(all_dirs):
        analysis = analyze_skill(skills_dir, directory)
        report.skill_analyses[directory] = analysis
        report.skills_analyzed += 1
        
        if analysis.has_skill_md:
            report.with_skill_md += 1
            if analysis.has_valid_yaml:
                report.with_valid_yaml += 1
            else:
                report.yaml_errors.append(directory)
            
            if analysis.name:
                report.with_name += 1
                all_names.append(analysis.name)
                name_counts[analysis.name] = name_counts.get(analysis.name, 0) + 1
            else:
                report.missing_name.append(directory)
            
            if analysis.description:
                report.with_description += 1
            else:
                report.missing_description.append(directory)
            
            if analysis.version:
                report.with_version += 1
            else:
                report.missing_version.append(directory)
            
            if analysis.author:
                report.with_author += 1
            
            if analysis.license:
                report.with_license += 1
            
            if analysis.has_openclaw_metadata:
                report.with_openclaw += 1
            
            if analysis.has_hermes_metadata:
                report.with_hermes += 1
            
            if analysis.has_vibe_config:
                report.with_vibe += 1
            
            if not analysis.name_matches_directory and analysis.name:
                report.name_mismatches.append(directory)
        else:
            report.without_skill_md += 1
            report.missing_skill_md.append(directory)
        
        if analysis.issues:
            report.skills_with_errors += 1
    
    # Find duplicate names
    for name, count in name_counts.items():
        if count > 1:
            report.duplicate_names.append(name)
    
    return report, name_counts


def generate_markdown_report(report: AnalysisReport, name_counts: Dict[str, int], output_path: Path) -> None:
    """Generate markdown report"""
    
    with output_path.open('w') as f:
        f.write(f"# Skills Analysis Report\n\n")
        f.write(f"**Generated**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"**Skills Directory**: {report.total_directories} directories\n")
        f.write(f"**Skills Analyzed**: {report.skills_analyzed}\n\n")
        f.write("---\n\n")
        
        # Summary Statistics
        f.write("## 📊 Summary Statistics\n\n")
        f.write("| Metric | Count | % | Status |\n")
        f.write("|--------|-------|---|--------|\n")
        
        stats = [
            ("With SKILL.md", report.with_skill_md, "✅"),
            ("Without SKILL.md", report.without_skill_md, "❌"),
            ("Valid YAML", report.with_valid_yaml, "✅"),
            ("Has name", report.with_name, "✅"),
            ("Has description", report.with_description, "✅"),
            ("Has version", report.with_version, "✅"),
            ("Has author", report.with_author, "✅"),
            ("Has license", report.with_license, "✅"),
            ("OpenClaw metadata", report.with_openclaw, "✅"),
            ("Hermes metadata", report.with_hermes, "✅"),
            ("Vibe config", report.with_vibe, "✅"),
        ]
        
        base = max(report.with_skill_md, 1)
        for label, count, status in stats:
            percent = (count / base * 100) if base > 0 else 0
            f.write(f"| {label} | {count} | {percent:.1f}% | {status} |\n")
        
        f.write("\n---\n\n")
        
        # Compliance Summary
        f.write("## 🎯 Compliance Summary\n\n")
        f.write("| System | Compliant | Non-Compliant | % |\n")
        f.write("|--------|-----------|---------------|---|\n")
        f.write(f"| OpenClaw | {report.with_openclaw} | {report.with_skill_md - report.with_openclaw} | {(report.with_openclaw/base*100):.1f}% |\n")
        f.write(f"| Hermes | {report.with_hermes} | {report.with_skill_md - report.with_hermes} | {(report.with_hermes/base*100):.1f}% |\n")
        f.write(f"| Vibe | {report.with_vibe} | {report.with_skill_md - report.with_vibe} | {(report.with_vibe/base*100):.1f}% |\n")
        f.write("\n---\n\n")
        
        # Issues
        f.write("## 🚨 Issues Found\n\n")
        
        if report.missing_skill_md:
            f.write(f"### Missing SKILL.md ({len(report.missing_skill_md)} directories)\n\n")
            for d in sorted(report.missing_skill_md):
                f.write(f"- `skills/{d}/`\n")
            f.write("\n")
        
        if report.yaml_errors:
            f.write(f"### Invalid YAML ({len(report.yaml_errors)} skills)\n\n")
            for d in report.yaml_errors:
                f.write(f"- `skills/{d}/SKILL.md`\n")
            f.write("\n")
        
        if report.missing_name:
            f.write(f"### Missing `name` field ({len(report.missing_name)} skills)\n\n")
            for d in sorted(report.missing_name):
                f.write(f"- `skills/{d}/SKILL.md`\n")
            f.write("\n")
        
        if report.missing_description:
            f.write(f"### Missing `description` field ({len(report.missing_description)} skills)\n\n")
            for d in sorted(report.missing_description):
                f.write(f"- `skills/{d}/SKILL.md`\n")
            f.write("\n")
        
        if report.missing_version:
            f.write(f"### Missing `version` field ({len(report.missing_version)} skills)\n\n")
            for d in sorted(report.missing_version):
                f.write(f"- `skills/{d}/SKILL.md`\n")
            f.write("\n")
        
        if report.name_mismatches:
            f.write(f"### Name/Directory Mismatches ({len(report.name_mismatches)} skills)\n\n")
            for d in sorted(report.name_mismatches):
                f.write(f"- `skills/{d}/`\n")
            f.write("\n")
        
        if report.duplicate_names:
            f.write(f"### Duplicate Names ({len(report.duplicate_names)} names)\n\n")
            for name in sorted(report.duplicate_names):
                f.write(f"- `{name}` (appears {name_counts.get(name, 0)}x)\n")
            f.write("\n")
        
        if not any([report.missing_skill_md, report.yaml_errors, report.missing_name, 
                   report.missing_description, report.missing_version, report.name_mismatches,
                   report.duplicate_names]):
            f.write("No issues found! All skills are in good shape.\n\n")
        
        # Detailed table
        f.write("## 📋 Detailed Skill Analysis\n\n")
        f.write("| Skill | SKILL.md | YAML | Name | Desc | Version | Author | License | OpenClaw | Hermes | Vibe | Status |\n")
        f.write("|-------|---------|------|------|------|---------|--------|---------|----------|--------|------|--------|\n")
        
        for dir_name, analysis in sorted(report.skill_analyses.items()):
            oc = "✅" if analysis.has_openclaw_metadata else "❌"
            hm = "✅" if analysis.has_hermes_metadata else "❌"
            vb = "✅" if analysis.has_vibe_config else "❌"
            
            yml = "✅" if analysis.has_valid_yaml else "❌"
            nm = "✅" if analysis.name else "❌"
            desc = "✅" if analysis.description else "❌"
            
            ver = analysis.version or ""
            author = analysis.author or ""
            lic = analysis.license or ""
            
            # Truncate directory name for display
            display_dir = dir_name[:30] + "..." if len(dir_name) > 30 else dir_name
            
            f.write(f"| [`{display_dir}`](../skills/{dir_name}/) | "
                   f"{"✅" if analysis.has_skill_md else "❌"} | {yml} | {nm} | {desc} | "
                   f"{ver} | {author} | {lic} | {oc} | {hm} | {vb} | "
                   f"{analysis.status} |\n")
        
        f.write("\n---\n\n")
        
        # Recommendations
        f.write("## 💡 Recommendations\n\n")
        f.write("Based on this analysis:\n\n")
        
        if report.missing_skill_md:
            f.write("1. **Create SKILL.md files** for directories without them:\n")
            for d in sorted(report.missing_skill_md)[:10]:
                f.write(f"   - Create `skills/{d}/SKILL.md`\n")
            if len(report.missing_skill_md) > 10:
                f.write(f"   - ... and {len(report.missing_skill_md) - 10} more\n")
            f.write("\n")
        
        if report.yaml_errors or report.missing_name or report.missing_description:
            f.write("2. **Fix YAML frontmatter issues**:\n")
            if report.yaml_errors:
                f.write(f"   - Fix YAML syntax in {len(report.yaml_errors)} skills\n")
            if report.missing_name:
                f.write(f"   - Add `name` field to {len(report.missing_name)} skills\n")
            if report.missing_description:
                f.write(f"   - Add `description` field to {len(report.missing_description)} skills\n")
            f.write("\n")
        
        if report.name_mismatches:
            f.write("3. **Fix name mismatches**:\n")
            f.write(f"   - {len(report.name_mismatches)} skills have names that don't match their directory\n")
            f.write("   - Either rename the directory or update the `name` field\n")
            f.write("\n")
        
        if report.duplicate_names:
            f.write("4. **Resolve duplicate names**:\n")
            for name in report.duplicate_names:
                f.write(f"   - `{name}` appears multiple times\n")
            f.write("\n")
        
        # Adding metadata recommendation
        f.write("5. **Add missing metadata**:\n")
        f.write(f"   - Add OpenClaw metadata to {report.with_skill_md - report.with_openclaw} skills\n")
        f.write(f"   - Add Hermes metadata to {report.with_skill_md - report.with_hermes} skills\n")
        f.write(f"   - Add Vibe configuration to {report.with_skill_md - report.with_vibe} skills\n")
        f.write("\n")
        
        f.write("6. **Add missing fields**:\n")
        f.write(f"   - Add `version` field to {len(report.missing_version)} skills\n")
        f.write(f"   - Add `author` field to {report.with_skill_md - report.with_author} skills\n")
        f.write(f"   - Add `license` field to {report.with_skill_md - report.with_license} skills\n")
        f.write("\n")
        
        f.write("7. **Standardize structure**:\n")
        f.write("   - Use consistent naming (lowercase, hyphen-separated)\n")
        f.write("   - Add proper categorization\n")
        f.write("   - Document related skills\n")
        f.write("\n")
        
        # Summary
        f.write("---\n\n")
        f.write("## 📊 Summary\n\n")
        f.write(f"- **Total directories**: {report.total_directories}\n")
        f.write(f"- **Skills analyzed**: {report.skills_analyzed}\n")
        f.write(f"- **Skills with errors**: {report.skills_with_errors}\n")
        f.write(f"- **Compliance rate**: {(report.with_valid_yaml/report.with_skill_md*100):.1f}%\n")
        f.write(f"- **OpenClaw ready**: {(report.with_openclaw/report.with_skill_md*100):.1f}%\n")
        f.write(f"- **Hermes ready**: {(report.with_hermes/report.with_skill_md*100):.1f}%\n")
        f.write(f"- **Vibe ready**: {(report.with_vibe/report.with_skill_md*100):.1f}%\n")
        f.write(f"\n")
        f.write(f"**Report generated**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")


def main():
    """Main entry point"""
    skills_dir = Path("/home/drdeek/.openclaw/agents/aton/projects/hypersnap-roast-or-toast/skills")
    output_path = Path("/home/drdeek/.openclaw/agents/aton/projects/hypersnap-roast-or-toast/SKILLS_ANALYSIS_REPORT.md")
    json_path = Path("/home/drdeek/.openclaw/agents/aton/projects/hypersnap-roast-or-toast/SKILLS_ANALYSIS.json")
    
    print("🔍 Analyzing skills...")
    print("")
    
    try:
        # Run analysis
        report, name_counts = analyze_all_skills(skills_dir)
        
        # Generate reports
        generate_markdown_report(report, name_counts, output_path)
        
        # Save JSON for programmatic access
        with json_path.open('w') as f:
            json.dump({
                'summary': {
                    'total_directories': report.total_directories,
                    'skills_analyzed': report.skills_analyzed,
                    'with_skill_md': report.with_skill_md,
                    'without_skill_md': report.without_skill_md,
                    'with_valid_yaml': report.with_valid_yaml,
                    'with_name': report.with_name,
                    'with_description': report.with_description,
                    'with_version': report.with_version,
                    'with_author': report.with_author,
                    'with_license': report.with_license,
                    'with_openclaw': report.with_openclaw,
                    'with_hermes': report.with_hermes,
                    'with_vibe': report.with_vibe,
                    'skills_with_errors': report.skills_with_errors,
                },
                'issues': {
                    'missing_skill_md': report.missing_skill_md,
                    'yaml_errors': report.yaml_errors,
                    'missing_name': report.missing_name,
                    'missing_description': report.missing_description,
                    'missing_version': report.missing_version,
                    'name_mismatches': report.name_mismatches,
                    'duplicate_names': report.duplicate_names,
                },
                'name_counts': {k: v for k, v in name_counts.items()},
                'skills': {
                    dir: {
                        'has_skill_md': analysis.has_skill_md,
                        'name': analysis.name,
                        'description': analysis.description,
                        'version': analysis.version,
                        'status': analysis.status,
                        'has_openclaw': analysis.has_openclaw_metadata,
                        'has_hermes': analysis.has_hermes_metadata,
                        'has_vibe': analysis.has_vibe_config,
                    }
                    for dir, analysis in report.skill_analyses.items()
                }
            }, f, indent=2, default=str)
        
        # Print summary
        print(f"✅ Analysis complete!")
        print(f"")
        print(f"📊 Summary:")
        print(f"   Total directories: {report.total_directories}")
        print(f"   With SKILL.md: {report.with_skill_md}")
        print(f"   Without SKILL.md: {report.without_skill_md}")
        print(f"   Valid YAML: {report.with_valid_yaml}")
        print(f"   Has name: {report.with_name}")
        print(f"   Has description: {report.with_description}")
        print(f"   Has version: {report.with_version}")
        print(f"   Has author: {report.with_author}")
        print(f"   Has license: {report.with_license}")
        print(f"   OpenClaw metadata: {report.with_openclaw}")
        print(f"   Hermes metadata: {report.with_hermes}")
        print(f"   Vibe config: {report.with_vibe}")
        print(f"")
        print(f"🔥 Issues Found:")
        if report.missing_skill_md:
            print(f"   ❌ Missing SKILL.md: {len(report.missing_skill_md)}")
        if report.yaml_errors:
            print(f"   ❌ Invalid YAML: {len(report.yaml_errors)}")
        if report.missing_name:
            print(f"   ❌ Missing name: {len(report.missing_name)}")
        if report.missing_description:
            print(f"   ❌ Missing description: {len(report.missing_description)}")
        if report.missing_version:
            print(f"   ❌ Missing version: {len(report.missing_version)}")
        if report.name_mismatches:
            print(f"   ⚠️  Name mismatches: {len(report.name_mismatches)}")
        if report.duplicate_names:
            print(f"   ⚠️  Duplicate names: {len(report.duplicate_names)}")
        print(f"")
        
        if not any([report.missing_skill_md, report.yaml_errors, report.missing_name,
                   report.missing_description, report.missing_version, report.name_mismatches,
                   report.duplicate_names]):
            print("🎉 All skills are properly structured!")
        
        print(f"📄 Reports saved to:")
        print(f"   - {output_path}")
        print(f"   - {json_path}")
        
        return 0
        
    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())

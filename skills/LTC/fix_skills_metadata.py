#!/usr/bin/env python3
"""
Fix Skills Metadata Issues

This script fixes common metadata issues in SKILL.md files:
1. Adds missing version field
2. Adds missing author field
3. Adds missing license field
4. Fixes name mismatches between directory and YAML name
5. Resolves duplicate names

Usage:
    python fix_skills_metadata.py [--dry-run] [--verbose]
"""

import os
import re
import sys
import yaml
import argparse
from pathlib import Path


def parse_args():
    parser = argparse.ArgumentParser(
        description="Fix skills metadata issues"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Don't make changes, just report what would happen",
    )
    parser.add_argument(
        "--verbose",
        "-v",
        action="store_true",
        help="Show detailed output",
    )
    parser.add_argument(
        "--skills-root",
        default=os.path.expanduser("~/.openclaw/agents/aton/projects/hypersnap-roast-or-toast/skills"),
        help="Path to skills directory",
    )
    return parser.parse_args()


def load_skillmd(filepath):
    """Load YAML frontmatter from SKILL.md file."""
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()
    
    # Extract YAML frontmatter
    if content.startswith("---"):
        match = re.match(r"^---\s*\n(.*?)\n---*\s*\n?", content, re.DOTALL)
        if match:
            yaml_content = match.group(1)
            try:
                metadata = yaml.safe_load(yaml_content)
                return metadata, content
            except yaml.YAMLError as e:
                print(f"  ERROR parsing YAML in {filepath}: {e}")
                return None, content
    
    return None, content


def save_skillmd(filepath, metadata, content):
    """Save SKILL.md with updated YAML frontmatter."""
    # Get the markdown content (after the first --- ... --- block)
    if content.startswith("---"):
        match = re.match(r"^---\s*\n.*?\n---*\s*\n?(.*)", content, re.DOTALL)
        if match:
            markdown_content = match.group(1)
        else:
            markdown_content = content
    else:
        markdown_content = content
    
    # Generate new YAML frontmatter
    yaml_content = yaml.dump(
        metadata,
        default_flow_style=False,
        sort_keys=False,
        allow_unicode=True,
    )
    
    # Build new content
    new_content = f"---\n{yaml_content}---\n{markdown_content}\n"
    
    with open(filepath, "w", encoding="utf-8") as f:
        f.write(new_content)


def add_missing_fields(metadata):
    """Add missing required fields with defaults."""
    if "version" not in metadata:
        metadata["version"] = "1.0.0"
    if "author" not in metadata:
        metadata["author"] = "openclaw"
    if "license" not in metadata:
        metadata["license"] = "MIT"
    if "description" not in metadata:
        metadata["description"] = "Description not available"
    return metadata


def fix_name_mismatch(metadata, dirname):
    """Fix name mismatch."""
    # Normalize both names
    yaml_name = metadata.get("name", "").lower().replace(" ", "-").replace("_", "-")
    dir_name = dirname.lower().replace(" ", "-").replace("_", "-")
    
    if yaml_name != dir_name:
        metadata["name"] = dirname
        return True
    return False


def main():
    args = parse_args()
    skills_root = Path(args.skills_root)
    
    print("=" * 80)
    print("FIXING SKILLS METADATA")
    print("=" * 80)
    print(f"Skills Root: {skills_root}")
    print(f"Dry Run: {args.dry_run}")
    print()
    
    # Collect all SKILL.md files
    skill_files = []
    for dirpath, _, files in os.walk(skills_root):
        dirpath = Path(dirpath)
        if dirpath == skills_root or dirpath.name.startswith("."):
            continue
        for filename in files:
            if filename == "SKILL.md":
                skill_files.append(dirpath / filename)
    
    print(f"Found {len(skill_files)} SKILL.md files")
    print()
    
    # Track issues
    missing_version = 0
    missing_author = 0
    missing_license = 0
    name_mismatches = []
    name_count = {}
    fixed = 0
    errors = 0
    
    # First pass: collect statistics
    for filepath in skill_files:
        metadata, _ = load_skillmd(filepath)
        if metadata is None:
            continue
        
        dirname = filepath.parent.name
        
        # Check for missing fields
        if "version" not in metadata:
            missing_version += 1
        if "author" not in metadata:
            missing_author += 1
        if "license" not in metadata:
            missing_license += 1
        
        # Check for name mismatches
        if "name" in metadata:
            yaml_name = metadata["name"].lower()
            dir_name = dirname.lower()
            if yaml_name != dir_name:
                name_mismatches.append((filepath, metadata["name"], dirname))
        
        # Count names for duplicates
        if "name" in metadata:
            name = metadata["name"].lower()
            if name in name_count:
                name_count[name].append(dirname)
            else:
                name_count[name] = [dirname]
    
    # Report statistics
    print("ISSUES FOUND:")
    print(f"  Missing version: {missing_version}")
    print(f"  Missing author: {missing_author}")
    print(f"  Missing license: {missing_license}")
    print(f"  Name mismatches: {len(name_mismatches)}")
    for filepath, yaml_name, dirname in name_mismatches[:5]:
        print(f"    - {filepath.parent.name}: YAML='{yaml_name}', Directory='{dirname}'")
    if len(name_mismatches) > 5:
        print(f"    ... and {len(name_mismatches) - 5} more")
    print()
    
    # Find duplicates
    duplicates = {name: dirs for name, dirs in name_count.items() if len(dirs) > 1}
    print(f"  Duplicate names: {len(duplicates)}")
    for name, dirs in list(duplicates.items())[:5]:
        print(f"    - '{name}': {', '.join(dirs)}")
    if len(duplicates) > 5:
        print(f"    ... and {len(duplicates) - 5} more")
    print()
    
    # Second pass: fix issues
    print("FIXING ISSUES:")
    
    for filepath in skill_files:
        metadata, content = load_skillmd(filepath)
        if metadata is None:
            continue
        
        dirname = filepath.parent.name
        modified = False
        
        # Add missing fields
        if "version" not in metadata:
            metadata["version"] = "1.0.0"
            modified = True
            if args.verbose:
                print(f"  ADD version: {filepath.parent.name}")
        
        if "author" not in metadata:
            metadata["author"] = "openclaw"
            modified = True
            if args.verbose:
                print(f"  ADD author: {filepath.parent.name}")
        
        if "license" not in metadata:
            metadata["license"] = "MIT"
            modified = True
            if args.verbose:
                print(f"  ADD license: {filepath.parent.name}")
        
        # Fix name mismatch
        if "name" in metadata:
            yaml_name = metadata["name"].lower().replace(" ", "-").replace("_", "-")
            dir_name = dirname.lower().replace(" ", "-").replace("_", "-")
            if yaml_name != dir_name:
                metadata["name"] = dirname
                modified = True
                if args.verbose:
                    print(f"  FIX name: {filepath.parent.name} ({yaml_name} -> {dirname})")
        
        # Save if modified
        if modified:
            if not args.dry_run:
                try:
                    save_skillmd(filepath, metadata, content)
                    fixed += 1
                except Exception as e:
                    print(f"  ERROR saving {filepath}: {e}", file=sys.stderr)
                    errors += 1
    
    print()
    print("=" * 80)
    print("SUMMARY")
    print("=" * 80)
    print(f"Files processed: {len(skill_files)}")
    print(f"Issues fixed: {fixed}")
    print(f"Errors: {errors}")
    
    if args.dry_run:
        print()
        print("DRY RUN: No changes were made.")
    
    return errors


if __name__ == "__main__":
    sys.exit(main())

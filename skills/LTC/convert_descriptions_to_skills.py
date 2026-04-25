#!/usr/bin/env python3
"""
Convert DESCRIPTION.md files to SKILL.md format.

This script helps standardize the skills directory by converting
DESCRIPTION.md files (used for category directories) to SKILL.md
format with proper YAML frontmatter as defined in SKILL_SPECIFICATION.md.

Usage:
    python convert_descriptions_to_skills.py [--dry-run] [--verbose]

Options:
    --dry-run     Don't make changes, just show what would happen
    --verbose     Show detailed output
    --root PATH   Root directory to scan (default: ~/.openclaw/agents/.skills)
"""

import os
import re
import sys
import argparse
from pathlib import Path
from datetime import datetime
import yaml


def parse_args():
    parser = argparse.ArgumentParser(
        description="Convert DESCRIPTION.md files to SKILL.md format"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Don't make changes, just show what would happen",
    )
    parser.add_argument(
        "--verbose",
        "-v",
        action="store_true",
        help="Show detailed output",
    )
    parser.add_argument(
        "--root",
        default=os.path.expanduser("~/.openclaw/agents/.skills"),
        help="Root directory to scan (default: ~/.openclaw/agents/.skills)",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Overwrite existing SKILL.md files",
    )
    return parser.parse_args()


def extract_name_from_directory(dirpath: Path) -> str:
    """Extract skill name from directory name."""
    return dirpath.name.lower().replace(" ", "-").replace("_", "-")


def extract_description_from_file(filepath: Path) -> str:
    """Extract description from DESCRIPTION.md or SKILL.md content."""
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()
    
    # Remove YAML frontmatter if present
    if content.startswith("---"):
        match = re.match(r"^---\s*\n(.*?)\n---*\s*\n?(.*?)$", content, re.DOTALL)
        if match:
            content = match.group(2)
    
    # Clean up the description
    # Remove leading/trailing whitespace
    content = content.strip()
    
    # Remove leading headings
    content = re.sub(r"^#+\s+.*?\n+", "", content)
    
    # Get first paragraph as short description
    first_para = content.split("\n\n")[0].strip()
    
    return first_para if first_para else "Description not available"


def generate_skill_metadata(dirpath: Path, description: str) -> dict:
    """Generate metadata for SKILL.md frontmatter."""
    name = extract_name_from_directory(dirpath)
    
    # Try to extract version from existing content
    version = "1.0.0"
    
    # Generate metadata
    metadata = {
        "name": name,
        "description": description,
        "version": version,
        "author": "openclaw",
        "license": "MIT",
        "user_invocable": True,
        "allowed_tools": ["bash", "read_file", "grep", "write_file"],
    }
    
    return metadata


def generate_category_metadata(dirpath: Path, description: str) -> dict:
    """Generate metadata for category DESCRIPTION.md conversion to SKILL.md."""
    name = extract_name_from_directory(dirpath)
    
    # For category directories, mark as user_invocable: false
    metadata = {
        "name": name,
        "description": description,
        "version": "1.0.0",
        "author": "openclaw",
        "license": "MIT",
        "user_invocable": False,  # Category directories typically not user-invocable
        "allowed_tools": [],
    }
    
    # Add metadata for all systems
    metadata["metadata"] = {
        "openclaw": {
            "tags": [name],
            "category": name,
            "priority": "medium",
            "dependencies": [],
        },
        "hermes": {
            "tags": [name, "category"],
            "category": "management",
            "related_skills": [],
        },
    }
    
    metadata["vibe"] = {
        "enabled": True,
        "auto_load": False,
        "search_terms": [name],
    }
    
    return metadata


def convert_description_to_skill(filepath: Path) -> tuple[str, dict]:
    """
    Convert a DESCRIPTION.md file to SKILL.md format.
    
    Returns: (new_content, metadata)
    """
    dirpath = filepath.parent
    description = extract_description_from_file(filepath)
    
    # For category directories, use category metadata
    if is_category_directory(dirpath):
        metadata = generate_category_metadata(dirpath, description)
    else:
        metadata = generate_skill_metadata(dirpath, description)
    
    # Read full content
    with open(filepath, "r", encoding="utf-8") as f:
        full_content = f.read()
    
    # Remove YAML frontmatter if present
    if full_content.startswith("---"):
        match = re.match(r"^---\s*\n(.*?)\n---*\s*\n?(.*?)$", full_content, re.DOTALL)
        if match:
            full_content = match.group(2)
    
    # Clean up content
    full_content = full_content.strip()
    
    # Build new content with YAML frontmatter
    yaml_content = yaml.dump(
        metadata,
        default_flow_style=False,
        sort_keys=False,
        allow_unicode=True,
    )
    
    # Add markdown separator
    new_content = f"---\n{yaml_content}---\n\n{full_content}\n"
    
    return new_content, metadata


def is_category_directory(dirpath: Path) -> bool:
    """Check if a directory is a category directory (has subdirectories with SKILL.md)."""
    # Check if directory has subdirectories with SKILL.md
    for item in dirpath.iterdir():
        if item.is_dir() and (item / "SKILL.md").exists():
            return True
    return False


def find_description_files(root: Path) -> list[Path]:
    """Find all DESCRIPTION.md files in the directory tree."""
    description_files = []
    
    for dirpath, _, files in os.walk(root):
        for filename in files:
            if filename == "DESCRIPTION.md":
                filepath = Path(dirpath) / filename
                description_files.append(filepath)
    
    return description_files


def find_directories_without_docs(root: Path) -> list[Path]:
    """Find directories that have neither SKILL.md nor DESCRIPTION.md."""
    directories = []
    
    for dirpath, _, files in os.walk(root):
        dirpath = Path(dirpath)
        # Skip the root and hidden directories
        if dirpath == root or dirpath.name.startswith("."):
            continue
        
        has_skill = (dirpath / "SKILL.md").exists()
        has_description = (dirpath / "DESCRIPTION.md").exists()
        
        if not has_skill and not has_description:
            directories.append(dirpath)
    
    return directories


def main():
    args = parse_args()
    root = Path(args.root)
    
    print(f"Scanning {root}...")
    print()
    
    # Find all DESCRIPTION.md files
    description_files = find_description_files(root)
    print(f"Found {len(description_files)} DESCRIPTION.md files")
    
    # Find directories without docs
    dirs_without_docs = find_directories_without_docs(root)
    print(f"Found {len(dirs_without_docs)} directories without documentation")
    print()
    
    # Process DESCRIPTION.md files
    converted = 0
    errors = 0
    
    for filepath in description_files:
        dirpath = filepath.parent
        
        # Skip if SKILL.md already exists
        skill_file = dirpath / "SKILL.md"
        if skill_file.exists() and not args.force:
            if args.verbose:
                print(f"SKIP: {filepath} - SKILL.md already exists")
            continue
        
        # Check if it's a category directory
        is_category = is_category_directory(dirpath)
        
        if args.verbose or args.dry_run:
            status = "CATEGORY" if is_category else "SKILL"
            print(f"CONVERT [{status}]: {filepath}")
        
        try:
            new_content, metadata = convert_description_to_skill(filepath)
            
            if not args.dry_run:
                # Write new SKILL.md file
                with open(skill_file, "w", encoding="utf-8") as f:
                    f.write(new_content)
                
                # Optionally remove old DESCRIPTION.md
                if args.verbose:
                    print(f"  -> Created: {skill_file}")
                
                # Don't remove DESCRIPTION.md by default (keep as backup)
            
            converted += 1
            
        except Exception as e:
            print(f"  ERROR: {e}")
            errors += 1
    
    print()
    print(f"Conversion complete:")
    print(f"  Converted: {converted}")
    print(f"  Errors: {errors}")
    print()
    
    # List directories without docs
    if dirs_without_docs:
        print("Directories without documentation:")
        for dirpath in sorted(dirs_without_docs)[:20]:  # Show first 20
            rel_path = dirpath.relative_to(root)
            print(f"  - {rel_path}")
        if len(dirs_without_docs) > 20:
            print(f"  ... and {len(dirs_without_docs) - 20} more")
    
    print()
    
    if args.dry_run:
        print("DRY RUN: No files were modified. Use --dry-run to see what would happen.")
    
    return 0 if errors == 0 else 1


if __name__ == "__main__":
    sys.exit(main())

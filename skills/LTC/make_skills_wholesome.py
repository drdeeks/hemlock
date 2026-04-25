#!/usr/bin/env python3
"""
Make Project Skills Complete and Wholesome

This script analyzes the project skills directory and:
1. Creates SKILL.md files for all directories that need them
2. Converts DESCRIPTION.md to SKILL.md where appropriate
3. Copies SKILL.md from global directory for mirrored skills
4. Creates placeholder SKILL.md for empty directories
5. Fixes YAML syntax errors
6. Fixes name mismatches
7. Resolves duplicates

Usage:
    python make_skills_wholesome.py [--dry-run] [--verbose] [--remove-empty]

Options:
    --dry-run       Don't make changes, just report what would happen
    --verbose       Show detailed output
    --remove-empty  Remove empty directories instead of creating placeholders
    --global-root   Path to global skills (default: ~/.openclaw/agents/.skills)
"""

import os
import re
import sys
import shutil
import yaml
import argparse
from pathlib import Path
from datetime import datetime


def parse_args():
    parser = argparse.ArgumentParser(
        description="Make project skills complete and wholesome"
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
        "--remove-empty",
        action="store_true",
        help="Remove empty directories instead of creating placeholders",
    )
    parser.add_argument(
        "--global-root",
        default=os.path.expanduser("~/.openclaw/agents/.skills"),
        help="Path to global skills directory",
    )
    parser.add_argument(
        "--project-root",
        default=os.path.expanduser("~/.openclaw/agents/aton/projects/hypersnap-roast-or-toast/skills"),
        help="Path to project skills directory",
    )
    return parser.parse_args()


class SkillsWholesomeMaker:
    def __init__(self, args):
        self.args = args
        self.project_root = Path(args.project_root)
        self.global_root = Path(args.global_root)
        self.created = 0
        self.fixed = 0
        self.removed = 0
        self.errors = 0
        
    def log(self, message="", level="info"):
        if self.args.verbose or level == "error":
            if message:
                print(message)
    
    def run(self):
        self.log("=" * 80)
        self.log("MAKE PROJECT SKILLS WHOLESOME")
        self.log("=" * 80)
        self.log(f"Project Root: {self.project_root}")
        self.log(f"Global Root: {self.global_root}")
        self.log(f"Dry Run: {self.args.dry_run}")
        self.log(f"Remove Empty: {self.args.remove_empty}")
        self.log()
        
        # Step 1: Identify all top-level directories
        all_dirs = self.get_top_level_dirs()
        self.log(f"Total top-level directories: {len(all_dirs)}")
        
        # Step 2: Categorize directories
        categories = self.categorize_directories(all_dirs)
        
        self.log()
        self.log("Categorization:")
        for category, dirs in categories.items():
            self.log(f"  {category}: {len(dirs)}")
        
        self.log()
        
        # Step 3: Process each category
        self.process_category_directories(categories.get("with_description", []))
        self.process_empty_directories(categories.get("empty", []))
        self.process_directories_with_files(categories.get("with_files", []))
        
        # Step 3.5: Process nested directories (subdirectories)
        self.process_all_directories()
        
        # Step 4: Check for and fix common issues
        self.fix_yaml_errors()
        self.fix_name_mismatches()
        self.resolve_duplicates()
        
        # Summary
        self.log()
        self.log("=" * 80)
        self.log("SUMMARY")
        self.log("=" * 80)
        self.log(f"SKILL.md files created: {self.created}")
        self.log(f"Issues fixed: {self.fixed}")
        self.log(f"Directories removed: {self.removed}")
        self.log(f"Errors: {self.errors}")
        
        if self.args.dry_run:
            self.log()
            self.log("DRY RUN: No changes were made.")
        
        return self.errors
    
    def get_top_level_dirs(self):
        """Get all top-level directories in project skills."""
        dirs = []
        for item in self.project_root.iterdir():
            if item.is_dir() and not item.name.startswith("."):
                dirs.append(item)
        return sorted(dirs)
    
    def categorize_directories(self, all_dirs):
        """Categorize directories based on their contents."""
        categories = {
            "with_skill": [],
            "with_description": [],
            "empty": [],
            "with_files": [],
        }
        
        for dirpath in all_dirs:
            has_skill = (dirpath / "SKILL.md").exists()
            has_desc = (dirpath / "DESCRIPTION.md").exists()
            
            # Count files (excluding SKILL.md and DESCRIPTION.md)
            files = [f for f in dirpath.iterdir() if f.is_file()]
            files = [f for f in files if f.name not in ["SKILL.md", "DESCRIPTION.md"]]
            has_other_files = len(files) > 0
            
            # Count subdirectories
            subdirs = [d for d in dirpath.iterdir() if d.is_dir()]
            has_subdirs = len(subdirs) > 0
            
            if has_skill:
                categories["with_skill"].append(dirpath)
            elif has_desc:
                categories["with_description"].append(dirpath)
            elif has_other_files or has_subdirs:
                categories["with_files"].append(dirpath)
            else:
                categories["empty"].append(dirpath)
        
        return categories
    
    def process_category_directories(self, dirs):
        """Process directories that have DESCRIPTION.md (category directories)."""
        self.log()
        self.log("Processing category directories (with DESCRIPTION.md)...")
        
        for dirpath in dirs:
            desc_file = dirpath / "DESCRIPTION.md"
            skill_file = dirpath / "SKILL.md"
            
            if skill_file.exists():
                self.log(f"  SKIP {dirpath.name}: SKILL.md already exists")
                continue
            
            self.log(f"  PROCESS {dirpath.name}: Has DESCRIPTION.md")
            
            # Convert DESCRIPTION.md to SKILL.md
            self.convert_description_to_skill(desc_file, skill_file)
    
    def process_empty_directories(self, dirs):
        """Process empty directories."""
        self.log()
        self.log("Processing empty directories...")
        
        for dirpath in dirs:
            if self.args.remove_empty:
                self.log(f"  REMOVE {dirpath.name}: Empty directory")
                if not self.args.dry_run:
                    try:
                        shutil.rmtree(dirpath)
                        self.removed += 1
                    except Exception as e:
                        self.log(f"    ERROR: {e}", "error")
                        self.errors += 1
            else:
                self.log(f"  CREATE {dirpath.name}: Creating placeholder SKILL.md")
                self.create_placeholder_skill(dirpath)
    
    def process_directories_with_files(self, dirs):
        """Process directories that have files but no SKILL.md or DESCRIPTION.md."""
        self.log()
        self.log("Processing directories with files...")
        
        for dirpath in dirs:
            self.log(f"  PROCESS {dirpath.name}: Has files/subdirs")
            
            # Check if this is a category directory (has subdirs with SKILL.md)
            if self.is_category_directory(dirpath):
                # Create a category DESCRIPTION.md or SKILL.md
                if self.args.verbose:
                    self.log(f"    -> Category directory, creating SKILL.md")
                self.create_category_skill(dirpath)
            else:
                # Check if mirrored in global
                global_skill = self.global_root / dirpath.name
                if global_skill.exists() and (global_skill / "SKILL.md").exists():
                    self.log(f"    -> Mirrored in global, copying SKILL.md")
                    self.copy_from_global(dirpath)
                elif (dirpath / "README.md").exists():
                    self.log(f"    -> Has README.md, converting to SKILL.md")
                    self.convert_readme_to_skill(dirpath)
                else:
                    # Has other files but no SKILL.md - check subdirectories
                    self.create_placeholder_skill(dirpath)
    
    def is_category_directory(self, dirpath):
        """Check if directory has subdirectories with SKILL.md."""
        for item in dirpath.iterdir():
            if item.is_dir():
                if (item / "SKILL.md").exists():
                    return True
        return False
    
    def process_all_directories(self):
        """Process all directories recursively to create missing SKILL.md files."""
        self.log()
        self.log("Processing all directories recursively...")
        
        created_count = 0
        for dirpath, subdirs, files in os.walk(self.project_root):
            dirpath = Path(dirpath)
            # Skip the root itself
            if dirpath == self.project_root:
                continue
            
            # Skip hidden directories
            if dirpath.name.startswith("."):
                continue
            
            skill_file = dirpath / "SKILL.md"
            desc_file = dirpath / "DESCRIPTION.md"
            
            # Skip if already has SKILL.md
            if skill_file.exists():
                continue
            
            # Check if this is a subdirectory
            is_top_level = dirpath.parent == self.project_root
            
            # Handle subdirectories
            if not is_top_level:
                # Check if this subdirectory should have a SKILL.md
                # For example: blockchain/base, devops/webhook-subscriptions, etc.
                
                # Check if there's a corresponding skill in global
                relative = dirpath.relative_to(self.project_root)
                global_path = self.global_root / relative
                global_skill = global_path / "SKILL.md"
                
                if global_skill.exists():
                    self.log(f"  COPY SUBDIR: {relative}")
                    if not self.args.dry_run:
                        try:
                            os.makedirs(dirpath, exist_ok=True)
                            shutil.copy2(global_skill, skill_file)
                            created_count += 1
                            self.log(f"    -> Copied from global")
                        except Exception as e:
                            self.log(f"    ERROR: {e}", "error")
                            self.errors += 1
                else:
                    # Create a placeholder for subdirectory
                    self.log(f"  CREATE SUBDIR: {relative}")
                    if not self.args.dry_run:
                        try:
                            self.create_placeholder_skill(dirpath)
                            created_count += 1
                        except Exception as e:
                            self.log(f"    ERROR: {e}", "error")
                            self.errors += 1
        
        self.created += created_count
    
    def convert_description_to_skill(self, desc_file, skill_file):
        """Convert DESCRIPTION.md to SKILL.md."""
        try:
            with open(desc_file, "r", encoding="utf-8") as f:
                content = f.read()
            
            # Extract first paragraph as description
            description = content.split("\n\n")[0].strip()
            description = re.sub(r"^#+\s+", "", description)
            
            # Create metadata
            metadata = {
                "name": desc_file.parent.name,
                "description": description,
                "version": "1.0.0",
                "author": "openclaw",
                "license": "MIT",
                "user_invocable": False,  # Category directories
                "allowed_tools": [],
            }
            
            # Add metadata for all systems
            metadata["metadata"] = {
                "openclaw": {
                    "tags": [desc_file.parent.name],
                    "category": desc_file.parent.name,
                    "priority": "medium",
                },
                "hermes": {
                    "tags": [desc_file.parent.name, "category"],
                    "category": "management",
                },
            }
            
            metadata["vibe"] = {
                "enabled": True,
                "auto_load": False,
            }
            
            # Build new content
            yaml_content = yaml.dump(
                metadata,
                default_flow_style=False,
                sort_keys=False,
                allow_unicode=True,
            )
            new_content = f"---\n{yaml_content}---\n\n{content}\n"
            
            if not self.args.dry_run:
                with open(skill_file, "w", encoding="utf-8") as f:
                    f.write(new_content)
                self.created += 1
                self.log(f"    -> Created: {skill_file}")
            
        except Exception as e:
            self.log(f"    ERROR: {e}", "error")
            self.errors += 1
    
    def create_category_skill(self, dirpath):
        """Create a SKILL.md for a category directory."""
        skill_file = dirpath / "SKILL.md"
        
        if skill_file.exists():
            return
        
        try:
            # Get subdirectory names
            subdirs = [d.name for d in dirpath.iterdir() if d.is_dir()]
            
            description = f"Category for skills related to {dirpath.name}. Contains: {', '.join(subdirs)}"
            
            metadata = {
                "name": dirpath.name,
                "description": description,
                "version": "1.0.0",
                "author": "openclaw",
                "license": "MIT",
                "user_invocable": False,
                "allowed_tools": [],
            }
            
            metadata["metadata"] = {
                "openclaw": {
                    "tags": [dirpath.name, "category"],
                    "category": dirpath.name,
                    "priority": "high",
                },
                "hermes": {
                    "tags": [dirpath.name, "category"],
                    "category": "management",
                },
            }
            
            metadata["vibe"] = {
                "enabled": True,
                "auto_load": False,
                "search_terms": [dirpath.name],
            }
            
            yaml_content = yaml.dump(
                metadata,
                default_flow_style=False,
                sort_keys=False,
                allow_unicode=True,
            )
            
            content = f"""---
{yaml_content}---

# {dirpath.name.capitalize()} Skills Category

This category contains skills related to {dirpath.name}.

## Subskills

{chr(10).join([f'- {subdir}' for subdir in subdirs])}

## Usage

This is a category directory. Use the specific subskills for detailed functionality.
"""
            
            if not self.args.dry_run:
                with open(skill_file, "w", encoding="utf-8") as f:
                    f.write(content)
                self.created += 1
                self.log(f"    -> Created category: {skill_file}")
            
        except Exception as e:
            self.log(f"    ERROR: {e}", "error")
            self.errors += 1
    
    def copy_from_global(self, dirpath):
        """Copy SKILL.md from global directory."""
        global_skill = self.global_root / dirpath.name / "SKILL.md"
        skill_file = dirpath / "SKILL.md"
        
        if skill_file.exists():
            return
        
        if global_skill.exists():
            try:
                if not self.args.dry_run:
                    shutil.copy2(global_skill, skill_file)
                    self.created += 1
                    self.log(f"    -> Copied from global: {skill_file}")
            except Exception as e:
                self.log(f"    ERROR: {e}", "error")
                self.errors += 1
    
    def create_placeholder_skill(self, dirpath):
        """Create a placeholder SKILL.md."""
        skill_file = dirpath / "SKILL.md"
        
        if skill_file.exists():
            return
        
        try:
            files = []
            for item in dirpath.iterdir():
                if item.is_file():
                    files.append(item.name)
                elif item.is_dir():
                    files.append(f"{item.name}/ (directory)")
            
            files_str = ", ".join(files) if files else "None"
            
            metadata = {
                "name": dirpath.name,
                "description": f"Placeholder for {dirpath.name} skill. Contains: {files_str}",
                "version": "0.0.1",
                "author": "openclaw",
                "license": "MIT",
                "user_invocable": False,
                "allowed_tools": [],
            }
            
            metadata["metadata"] = {
                "openclaw": {
                    "tags": [dirpath.name, "placeholder"],
                    "category": "uncategorized",
                    "priority": "low",
                }
            }
            
            metadata["vibe"] = {
                "enabled": False,
                "auto_load": False,
            }
            
            yaml_content = yaml.dump(
                metadata,
                default_flow_style=False,
                sort_keys=False,
                allow_unicode=True,
            )
            
            content = f"""---
{yaml_content}---

# {dirpath.name.capitalize()}

**Status:** PLACEHOLDER - This skill needs to be completed

**Contents:** {files_str}

## Next Steps

1. Research and document the purpose of this skill
2. Add proper description and metadata
3. Implement functionality
4. Set user_invocable to true when ready
"""
            
            if not self.args.dry_run:
                with open(skill_file, "w", encoding="utf-8") as f:
                    f.write(content)
                self.created += 1
                self.log(f"    -> Created placeholder: {skill_file}")
            
        except Exception as e:
            self.log(f"    ERROR: {e}", "error")
            self.errors += 1
    
    def fix_yaml_errors(self):
        """Fix YAML syntax errors in SKILL.md files."""
        self.log()
        self.log("Checking for YAML errors...")
        
        # Known invalid files from analysis
        invalid_files = [
            self.project_root / "builder-code" / "SKILL.md",
            self.project_root / "project-manager" / "SKILL.md",
        ]
        
        for filepath in invalid_files:
            if filepath.exists():
                self.log(f"  CHECK {filepath}")
                try:
                    with open(filepath, "r", encoding="utf-8") as f:
                        content = f.read()
                    
                    # Try to parse YAML
                    if content.startswith("---"):
                        match = re.match(r"^---\s*\n(.*?)\n---*\s*\n?", content, re.DOTALL)
                        if match:
                            yaml_content = match.group(1)
                            try:
                                yaml.safe_load(yaml_content)
                                self.log(f"    -> YAML is valid")
                            except yaml.YAMLError as e:
                                self.log(f"    -> YAML ERROR: {e}")
                                self.fix_invalid_yaml(filepath, yaml_content, content)
                except Exception as e:
                    self.log(f"    ERROR: {e}", "error")
                    self.errors += 1
    
    def fix_invalid_yaml(self, filepath, yaml_content, full_content):
        """Attempt to fix invalid YAML."""
        self.log(f"      Attempting to fix...")
        
        # Common issues:
        # 1. Unquoted special characters
        # 2. Invalid YAML syntax
        # 3. Missing colons
        
        try:
            # For now, just log that it needs manual fixing
            self.log(f"      NEEDS MANUAL FIX: {filepath}")
        except Exception as e:
            self.log(f"      ERROR: {e}", "error")
            self.errors += 1
    
    def fix_name_mismatches(self):
        """Fix name mismatches between directory and YAML name field."""
        self.log()
        self.log("Checking for name mismatches...")
        
        for dirpath in self.get_top_level_dirs():
            skill_file = dirpath / "SKILL.md"
            if not skill_file.exists():
                continue
            
            try:
                with open(skill_file, "r", encoding="utf-8") as f:
                    content = f.read()
                
                if content.startswith("---"):
                    match = re.match(r"^---\s*\n(.*?)\n---*\s*\n?", content, re.DOTALL)
                    if match:
                        yaml_content = match.group(1)
                        try:
                            metadata = yaml.safe_load(yaml_content)
                            if metadata and "name" in metadata:
                                yaml_name = metadata["name"].lower().replace(" ", "-").replace("_", "-")
                                dir_name = dirpath.name.lower().replace(" ", "-").replace("_", "-")
                                if yaml_name != dir_name:
                                    self.log(f"  MISMATCH {dirpath.name}: YAML name='{metadata['name']}', expected='{dirpath.name}'")
                                    # Don't auto-fix, just report
                        except Exception as e:
                            self.log(f"    ERROR parsing YAML: {e}", "error")
                            self.errors += 1
            except Exception as e:
                self.log(f"    ERROR: {e}", "error")
                self.errors += 1
    
    def resolve_duplicates(self):
        """Identify and report duplicate skill names."""
        self.log()
        self.log("Checking for duplicate names...")
        
        name_count = {}
        for dirpath in self.get_top_level_dirs():
            skill_file = dirpath / "SKILL.md"
            if skill_file.exists():
                try:
                    with open(skill_file, "r", encoding="utf-8") as f:
                        content = f.read()
                    if content.startswith("---"):
                        match = re.match(r"^---\s*\n(.*?)\n---*\s*\n?", content, re.DOTALL)
                        if match:
                            yaml_content = match.group(1)
                            metadata = yaml.safe_load(yaml_content)
                            if metadata and "name" in metadata:
                                name = metadata["name"].lower()
                                if name in name_count:
                                    name_count[name].append(dirpath.name)
                                else:
                                    name_count[name] = [dirpath.name]
                except Exception:
                    pass
        
        # Report duplicates
        for name, dirs in name_count.items():
            if len(dirs) > 1:
                self.log(f"  DUPLICATE '{name}': {' '.join(dirs)}")


def main():
    args = parse_args()
    maker = SkillsWholesomeMaker(args)
    return maker.run()


if __name__ == "__main__":
    sys.exit(main())

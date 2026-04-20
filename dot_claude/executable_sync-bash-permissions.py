#!/usr/bin/env python3

import json
import shutil
import subprocess
import sys
from pathlib import Path

# Paths
OPENCODE_CONFIG = Path.home() / '.config/opencode/opencode.json'
CLAUDE_SETTINGS = Path.home() / '.claude/settings.json'


def get_chezmoi_managed_source_path(target_path: Path) -> Path | None:
    chezmoi = shutil.which('chezmoi')
    if not chezmoi:
        print('chezmoi is not installed; writing Claude settings directly')
        return None

    try:
        subprocess.run(
            [chezmoi, 'managed', str(target_path)],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except subprocess.CalledProcessError:
        print(f'chezmoi is installed, but {target_path} is not managed there')
        return None

    source_path = subprocess.run(
        [chezmoi, 'source-path', str(target_path)],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    print(f'chezmoi manages {target_path}; updating source file: {source_path}')
    return Path(source_path)


def apply_chezmoi_target(target_path: Path) -> None:
    chezmoi = shutil.which('chezmoi')
    if not chezmoi:
        return

    print(f'Applying {target_path} via chezmoi')
    subprocess.run([chezmoi, 'apply', '--force', str(target_path)], check=True)

def main():
    # Read opencode config
    print(f'Reading opencode config from: {OPENCODE_CONFIG}')
    with open(OPENCODE_CONFIG, 'r') as f:
        opencode_config = json.load(f)

    # Extract bash permissions
    bash_perms = opencode_config.get('permission', {}).get('bash', {})
    print(f'Found {len(bash_perms)} bash permission rules')

    # Convert to Claude Code format
    claude_perms = {
        'allow': [],
        'deny': [],
        'ask': []
    }

    for pattern, action in bash_perms.items():
        # Skip the default "*" rule
        if pattern == '*':
            print(f'Skipping default rule: {pattern} -> {action}')
            continue

        # Convert pattern to Claude Code format
        # OpenCode uses "git diff*" while Claude uses "Bash(git diff *)"
        claude_pattern = f'Bash({pattern})'

        if action == 'allow':
            claude_perms['allow'].append(claude_pattern)
        elif action == 'deny':
            claude_perms['deny'].append(claude_pattern)
        elif action == 'ask':
            claude_perms['ask'].append(claude_pattern)

    print(f'\nConverted permissions:')
    print(f"  Allow: {len(claude_perms['allow'])} rules")
    print(f"  Deny: {len(claude_perms['deny'])} rules")
    print(f"  Ask: {len(claude_perms['ask'])} rules")

    # Read existing Claude settings
    claude_settings_path = get_chezmoi_managed_source_path(CLAUDE_SETTINGS)
    should_apply_with_chezmoi = claude_settings_path is not None
    if claude_settings_path is None:
        claude_settings_path = CLAUDE_SETTINGS

    print(f'\nReading Claude settings from: {claude_settings_path}')
    if claude_settings_path.exists():
        with open(claude_settings_path, 'r') as f:
            claude_settings = json.load(f)
    else:
        claude_settings = {}

    # Merge permissions (preserve existing ones, add new ones)
    if 'permissions' not in claude_settings:
        claude_settings['permissions'] = {}

    # Merge each permission type
    for perm_type in ['allow', 'deny', 'ask']:
        if perm_type not in claude_settings['permissions']:
            claude_settings['permissions'][perm_type] = []

        # Add new rules, avoiding duplicates
        for rule in claude_perms[perm_type]:
            if rule not in claude_settings['permissions'][perm_type]:
                claude_settings['permissions'][perm_type].append(rule)
                print(f'  Added {perm_type}: {rule}')
            else:
                print(f'  Skipped (exists): {rule}')

    # Write back to Claude settings
    print(f'\nWriting updated settings to: {claude_settings_path}')
    with open(claude_settings_path, 'w') as f:
        json.dump(claude_settings, f, indent=2)
        f.write('\n')

    if should_apply_with_chezmoi:
        apply_chezmoi_target(CLAUDE_SETTINGS)

    print('\n✓ Successfully synced bash permissions from opencode to Claude Code!')
    print('\nYou can view all permissions by running: claude /permissions')

if __name__ == '__main__':
    try:
        main()
    except subprocess.CalledProcessError as exc:
        print(f'chezmoi command failed: {exc}', file=sys.stderr)
        raise SystemExit(exc.returncode) from exc

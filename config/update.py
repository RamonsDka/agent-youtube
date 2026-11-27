"""Install or remove this package's entries in Gentle Shell's JSON configs and agent file."""

import argparse
import hashlib
import json
import os
import re
import shutil
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

EFFORTS = ('low', 'medium', 'high', 'max')
OPERATOR_TOOLS = (
    'write_channel_select', 'auth_user_select', 'apply', 'upload_multi', 'upload_cancel',
    'playlist_create', 'playlist_update', 'playlist_delete', 'playlist_add_videos',
    'playlist_remove_videos', 'social_stage_video', 'social_preview', 'social_confirm',
    'social_cancel', 'social_reschedule',
)
READ_ONLY_NOTE = (
    '- This install is read-only for channel writes: you cannot apply, upload, change playlists or '
    'stage social posts. If the user asks for one, tell them channel writes need a reinstall with '
    '`AGENT_YOUTUBE_OPERATOR=1`.\n\n'
)
MANIFEST = 'agent-youtube.manifest.json'
AGENT_FILE = Path('agents') / 'agent-youtube.md'

# Values written by the 555cdd0 installer, which left no manifest.
LEGACY_PROFILE = {'model': 'cpamc/deeprelay/deepseek-v4.1-flash', 'effort': 'high'}
LEGACY_MCP = {
    'type': 'stdio', 'command': 'npm', 'args': ['run', 'mcp:video-metadata'],
    'env': {'npm_config_loglevel': 'silent'}, 'exposure': 'direct',
}
LEGACY_AGENT_SHA256 = 'c4c4f9138f3e35d3d16a7d2cc5037b4d0b88f0da1d080268a77c2444411a3569'


class Fail(Exception):
    """Operational error: one line on stderr, exit 1."""


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def tree_hash(path):
    """Hash a directory's relative names, file contents and symlink targets."""
    digest = hashlib.sha256()
    for item in sorted(path.rglob('*')):
        digest.update(item.relative_to(path).as_posix().encode('utf-8', 'surrogateescape') + b'\0')
        if item.is_symlink():
            digest.update(b'L' + os.readlink(item).encode('utf-8', 'surrogateescape'))
        elif item.is_file():
            digest.update(b'F' + item.read_bytes())
        else:
            digest.update(b'D')
    return digest.hexdigest()


def skill_state(args, manifest):
    """absent | symlink | vendor-missing | unmodified | modified, judged by the recorded hash first."""
    path = args.path
    if path.is_symlink():
        return 'symlink'
    if not path.exists():
        return 'absent'
    recorded = manifest.get('skills', {}).get(args.skill_name)
    if recorded is not None:
        return 'unmodified' if tree_hash(path) == recorded else 'modified'
    if args.vendor_copy is None or not args.vendor_copy.is_dir():
        return 'vendor-missing'
    return 'unmodified' if tree_hash(path) == tree_hash(args.vendor_copy) else 'modified'


def check_path(path):
    if path.is_symlink() and not path.exists():
        raise Fail(f'{path}: dangling symlink; refusing to create its target')


def read_optional(path):
    check_path(path)
    try:
        return path.read_bytes()
    except FileNotFoundError:
        return None


def write_file(path, data, backup=None):
    """Atomically write data, keeping mode; back up `backup` bytes beside the configured path."""
    check_path(path)
    target = path.resolve() if path.is_symlink() else path
    try:
        mode = target.stat().st_mode & 0o777
    except FileNotFoundError:
        mode = 0o644
    target.parent.mkdir(parents=True, exist_ok=True)
    if backup is not None:
        stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ')
        fd = os.open(path.with_name(f'{path.name}.bak.{stamp}'), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'wb') as handle:
            handle.write(backup)
    fd, tmp = tempfile.mkstemp(dir=target.parent, prefix=f'.{target.name}.')
    try:
        with os.fdopen(fd, 'wb') as handle:
            os.fchmod(handle.fileno(), mode)
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, target)
    finally:
        Path(tmp).unlink(missing_ok=True)


def load_json(path, raw):
    if raw is None:
        return {}
    try:
        data = json.loads(raw)
    except (ValueError, UnicodeError):
        text = raw.decode('utf-8', 'replace')
        if re.search(r'//|/\*|,\s*[}\]]', text):
            raise Fail(f'{path}: invalid JSON (comments and trailing commas are not supported)')
        raise Fail(f'{path}: invalid JSON')
    return data


def dump_json(data):
    return (json.dumps(data, ensure_ascii=False, indent=2) + '\n').encode('utf-8')


def render(template, voice, skills_dir, model, effort, operator):
    try:
        text = template.read_text(encoding='utf-8')
    except OSError as exc:
        raise Fail(f'{template}: {exc.strerror or exc}')
    values = {
        '{{VOICE}}': voice,
        '{{SKILLS_DIR}}': skills_dir.rstrip('/'),
        '{{MODEL_LINE}}': f'model: {model}\n' if model else '',
        '{{EFFORT}}': effort,
        '{{OPERATOR_TOOLS}}': ''.join(f'  - mcp__tubemaster__{t}\n' for t in (OPERATOR_TOOLS if operator else ())),
        '{{READ_ONLY_NOTE}}': '\n' if operator else READ_ONLY_NOTE,
    }
    for placeholder, value in values.items():
        text = text.replace(placeholder, value)
    if '{{' in text:
        raise Fail(f'{template}: unknown placeholder {re.search(r"{{[^}]*}}", text).group(0)}')
    return text.encode('utf-8')


def decide(action, current, new, managed, force):
    if action == 'install':
        if current is None:
            return 'installed'
        if current == new:
            return 'unchanged'
        if managed(current) or force:
            return 'updated'
        return 'conflict'
    if current is None:
        return 'unchanged'
    return 'removed' if managed(current) else 'skipped (modified)'


def parse_args(argv):
    parser = argparse.ArgumentParser(
        prog='update.py',
        description="Install or remove agent-youtube's MCP entry, model profile and agent file.",
        epilog=(
            'Environment (install): AGENT_YOUTUBE_MODEL sets the model (omitted when unset, so the '
            "user's default applies); AGENT_YOUTUBE_EFFORT is one of " + '|'.join(EFFORTS) + ' '
            '(default high), written as `effort` in subagents.json and `thinking` in the agent '
            'frontmatter; AGENT_YOUTUBE_OPERATOR=1 adds the mutating TubeMaster tools (default: '
            'read-only tools only). Config files must be plain JSON: comments and trailing commas '
            'are not supported.'
        ),
    )
    parser.add_argument('action', choices=('install', 'uninstall', 'skill-state'))
    parser.add_argument('--agent-dir', required=True, type=Path, help='Gentle Shell agent directory')
    parser.add_argument('--tubemaster', type=Path, help='TubeMaster checkout (install)')
    parser.add_argument('--template', type=Path, help='agent template, agents/agent-youtube.md (install)')
    parser.add_argument('--voice', help='voice.md path written into the agent prompt (install)')
    parser.add_argument('--skills-dir', help='skills directory written into the agent prompt (install)')
    parser.add_argument('--force', action='store_true',
                        help='overwrite entries/files you modified (a backup is kept beside them)')
    parser.add_argument('--check', action='store_true',
                        help='install: validate everything and report conflicts, but write nothing')
    parser.add_argument('--skill', action='append', default=[],
                        help='install: record the hash of this installed skill in --skills-dir (repeatable)')
    parser.add_argument('--path', type=Path, help='skill-state: the installed skill directory')
    parser.add_argument('--vendor-copy', type=Path,
                        help='skill-state: vendor copy, used only when no hash was recorded')
    args = parser.parse_args(argv)
    only = {'install': ('tubemaster', 'template', 'voice', 'skills_dir', 'force', 'check', 'skill'),
            'skill-state': ('path', 'vendor_copy', 'skill')}
    allowed = {'install': only['install'], 'uninstall': (), 'skill-state': only['skill-state']}[args.action]
    for name in sorted({n for names in only.values() for n in names} - set(allowed)):
        if getattr(args, name) not in (None, False, []):
            parser.error(f"--{name.replace('_', '-')} is not valid for {args.action}")
    if args.action == 'skill-state':
        if args.path is None or len(args.skill) != 1:
            parser.error('skill-state requires --path and exactly one --skill')
        args.skill_name = args.skill[0]
    if args.action == 'install':
        missing = [f'--{n}' for n in ('tubemaster', 'template', 'voice', 'skills-dir')
                   if getattr(args, n.replace('-', '_')) is None]
        if missing:
            parser.error('install requires ' + ', '.join(missing))
    env = os.environ
    args.model = env.get('AGENT_YOUTUBE_MODEL') or None
    args.effort = env.get('AGENT_YOUTUBE_EFFORT') or 'high'
    args.operator = env.get('AGENT_YOUTUBE_OPERATOR') == '1'
    if args.effort not in EFFORTS:
        parser.error(f"AGENT_YOUTUBE_EFFORT must be one of {', '.join(EFFORTS)}")
    if args.model and re.search(r'\s', args.model):
        parser.error('AGENT_YOUTUBE_MODEL must not contain whitespace')
    return args


def run(args):
    agent_dir = args.agent_dir
    install = args.action == 'install'

    manifest_path = agent_dir / MANIFEST
    manifest_raw = read_optional(manifest_path)
    manifest = load_json(manifest_path, manifest_raw)
    if manifest_raw is not None and not (isinstance(manifest, dict) and isinstance(manifest.get('entries', {}), dict)
                                         and isinstance(manifest.get('skills', {}), dict)):
        raise Fail(f'{manifest_path}: unexpected manifest layout')
    if args.action == 'skill-state':
        print(skill_state(args, manifest))
        return
    recorded = manifest.get('entries', {})
    recorded_agent = manifest.get('agent_file_sha256')
    legacy = manifest_raw is None

    # Read and validate every file before changing anything.
    json_items = []
    for filename, section, key in (('mcp.json', 'mcpServers', 'tubemaster'),
                                   ('subagents.json', 'model_profiles', 'agent-youtube')):
        path = agent_dir / filename
        raw = read_optional(path)
        data = load_json(path, raw)
        if not isinstance(data, dict) or not isinstance(data.get(section, {}), dict):
            raise Fail(f'{path}: expected a JSON object with an optional {section} object')
        current = data.get(section, {}).get(key)
        if legacy:
            if filename == 'mcp.json':
                managed = lambda cur: isinstance(cur, dict) and {k: v for k, v in cur.items() if k != 'cwd'} == LEGACY_MCP
            else:
                managed = lambda cur: cur == LEGACY_PROFILE
        else:
            managed = lambda cur, old=recorded.get(filename): old is not None and cur == old
        json_items.append({'file': filename, 'path': path, 'raw': raw, 'data': data, 'section': section,
                           'key': key, 'current': current, 'managed': managed,
                           'label': f'{path} {section}.{key}'})

    agent_path = agent_dir / AGENT_FILE
    agent_raw = read_optional(agent_path)
    agent_sha = None if agent_raw is None else sha256(agent_raw)
    old_agent = LEGACY_AGENT_SHA256 if legacy else recorded_agent
    agent_managed = lambda cur: old_agent is not None and cur == old_agent

    new = {}
    if install:
        mcp = json_items[0]
        npm = shutil.which('npm')
        if npm:
            npm = os.path.abspath(npm)
        elif mcp['current'] is not None and mcp['managed'](mcp['current']):
            npm = mcp['current'].get('command', 'npm')
        else:
            raise Fail('npm not found on PATH; install Node.js/npm first')
        profile = {'effort': args.effort}
        if args.model:
            profile = {'model': args.model, 'effort': args.effort}
        new['mcp.json'] = {
            'type': 'stdio', 'command': npm, 'args': ['run', 'mcp:video-metadata'],
            'cwd': str(args.tubemaster.resolve()), 'env': {'npm_config_loglevel': 'silent'},
            'exposure': 'direct',
        }
        new['subagents.json'] = profile
        agent_new_raw = render(args.template, args.voice, args.skills_dir, args.model, args.effort, args.operator)
        agent_new_sha = sha256(agent_new_raw)

    results = []  # (status, label, item)
    for item in json_items:
        status = decide(args.action, item['current'], new.get(item['file']), item['managed'], args.force)
        results.append((status, item['label'], item))
    agent_link = agent_path.is_symlink()
    if agent_link:
        # Never write through or delete a symlinked agent file; --force replaces the link itself.
        agent_status = ('updated' if args.force else 'conflict') if install else 'skipped (symlink)'
    else:
        agent_status = decide(args.action, agent_sha, agent_new_sha if install else None, agent_managed, args.force)
    agent_label = str(agent_path)

    for status, label, item in results + [(agent_status, agent_label, None)]:
        if status == 'conflict':
            reason = 'is a symlink' if item is None and agent_link else 'was modified by the user'
            raise Fail(f'{label}: {reason}; keep it, or rerun with --force to overwrite (a backup is kept)')
    if args.check:
        return

    # Apply.
    for status, label, item in results:
        if status in ('unchanged',):
            continue
        data = item['data']
        if install:
            data.setdefault(item['section'], {})[item['key']] = new[item['file']]
        elif status == 'removed':
            del data[item['section']][item['key']]
            if not data[item['section']]:
                del data[item['section']]
        else:
            continue
        write_file(item['path'], dump_json(data), backup=item['raw'])
    if agent_status in ('installed', 'updated'):
        modified = agent_status == 'updated' and (agent_link or not agent_managed(agent_sha))
        if agent_link:
            agent_path.unlink()
        write_file(agent_path, agent_new_raw, backup=agent_raw if modified else None)
    elif agent_status == 'removed':
        agent_path.unlink()
        try:
            agent_path.parent.rmdir()  # only when empty
        except OSError:
            pass

    # Manifest.
    entries, agent_record = {}, None
    for status, label, item in results:
        if install:
            entries[item['file']] = new[item['file']]
        elif status == 'skipped (modified)' and item['file'] in recorded:
            entries[item['file']] = recorded[item['file']]
    if install:
        agent_record = agent_new_sha
    elif agent_status == 'skipped (modified)':
        agent_record = recorded_agent
    skill_hashes = {}
    for name in args.skill if install else ():
        skill_dir = Path(args.skills_dir) / name
        if skill_dir.is_dir() and not skill_dir.is_symlink():
            skill_hashes[name] = tree_hash(skill_dir)
    if entries or agent_record:
        state = {'version': 1, 'entries': entries}
        if skill_hashes:
            state['skills'] = skill_hashes
        if agent_record:
            state['agent_file_sha256'] = agent_record
        if manifest_raw is None or manifest != state:
            write_file(manifest_path, dump_json(state))
    elif manifest_raw is not None:
        manifest_path.unlink()

    for status, label, _ in results + [(agent_status, agent_label, None)]:
        print(f'{status}: {label}')
        if status.startswith('skipped'):
            print(f'warning: {status}: {label}', file=sys.stderr)


def main(argv=None):
    args = parse_args(argv)
    try:
        run(args)
    except Fail as exc:
        sys.exit(f'error: {exc}')
    except OSError as exc:
        sys.exit(f'error: {exc}')


if __name__ == '__main__':
    main()

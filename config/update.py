"""Change only this package's entries in Gentle Shell's JSON configs."""

import json
import os
from datetime import datetime, timezone
from pathlib import Path
import sys
import tempfile


def update(action, agent_dir, tubemaster):
    entries = (
        ('mcp.json', 'mcpServers', 'tubemaster', {
            'type': 'stdio',
            'command': 'npm',
            'args': ['run', 'mcp:video-metadata'],
            'cwd': str(tubemaster.resolve()),
            'env': {'npm_config_loglevel': 'silent'},
            'exposure': 'direct',
        }),
        ('subagents.json', 'model_profiles', 'agent-youtube', {
            'model': 'cpamc/deeprelay/deepseek-v4.1-flash',
            'effort': 'high',
        }),
    )
    changes = []
    for filename, section, key, value in entries:
        path = agent_dir / filename
        try:
            raw = path.read_bytes()
        except FileNotFoundError:
            raw = None
        try:
            data = {} if raw is None else json.loads(raw)
        except (ValueError, UnicodeError) as exc:
            raise ValueError(f'{path}: invalid JSON') from exc
        if not isinstance(data, dict) or not isinstance(data.get(section, {}), dict):
            raise ValueError(f'{path}: expected a JSON object with an optional {section} object')
        section_data = data.get(section, {})
        if action == 'install':
            if key in section_data:
                if section_data[key] != value:
                    raise ValueError(f'{path}: {section}.{key} already exists with different settings')
                continue
            data.setdefault(section, {})[key] = value
        else:
            if section_data.get(key) != value:
                continue
            del section_data[key]
        changes.append((path, raw, data))

    for path, raw, data in changes:
        path = path.resolve()  # Keep the configured path if it is a symlink.
        path.parent.mkdir(parents=True, exist_ok=True)
        if raw is not None:
            stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ')
            fd = os.open(path.with_name(f'{path.name}.bak.{stamp}'), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, 'wb') as backup:
                backup.write(raw)
        tmp = tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=path.parent, delete=False)
        try:
            with tmp:
                json.dump(data, tmp, ensure_ascii=False, indent=2)
                tmp.write('\n')
            os.replace(tmp.name, path)
        finally:
            Path(tmp.name).unlink(missing_ok=True)


if __name__ == '__main__':
    action, agent_dir, tubemaster = sys.argv[1:]
    try:
        update(action, Path(agent_dir), Path(tubemaster))
    except (ValueError, OSError) as exc:
        sys.exit(str(exc))

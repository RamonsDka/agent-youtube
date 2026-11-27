#!/usr/bin/env bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
: "${YT_SKILL_REPO:?point YT_SKILL_REPO at a local clone of youtube-agent-skill}"
: "${TUBEMASTER_REPO:?point TUBEMASTER_REPO at a local clone of TubeMaster}"

scratch=$(mktemp -d)
trap 'python3 -c "import shutil, sys; shutil.rmtree(sys.argv[1])" "$scratch"' EXIT
export HOME="$scratch/home"
export VENDOR_DIR="$scratch/vendor with spaces"
export SKIP_NPM=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_ALLOW_PROTOCOL=file
unset PI_SKILLS_DIR CLAUDE_SKILLS_DIR CLAUDE_YOUTUBE_DIR GENTLE_AGENT_DIR

agent="$HOME/.gentle-shell/agent"
voice="$HOME/.claude/youtube/voice.md"
mkdir -p "$agent/agents" "$HOME/.agents/skills/yt-unrelated" "$HOME/.claude/skills/yt-unrelated"
printf '%s\n' '{"mcpServers":{"other":{"command":"example","args":["--flag"]}},"setting":true}' > "$agent/mcp.json"
printf '%s\n' '{"model_profiles":{"other":{"model":"example/model","effort":"low"}},"max_concurrency":3}' > "$agent/subagents.json"
printf '%s\n' 'other agent' > "$agent/agents/other.md"
printf '%s\n' 'unrelated skill' > "$HOME/.agents/skills/yt-unrelated/SKILL.md"
cp "$HOME/.agents/skills/yt-unrelated/SKILL.md" "$HOME/.claude/skills/yt-unrelated/SKILL.md"
cp "$agent/mcp.json" "$scratch/mcp-original.json"
cp "$agent/subagents.json" "$scratch/subagents-original.json"

check_install() {
    python3 - "$agent" "$VENDOR_DIR" "$scratch" "$1" <<'PY'
import json
import sys
from pathlib import Path

agent, vendor, scratch = map(Path, sys.argv[1:4])

def load(path):
    return json.loads(path.read_text())

mcp = load(agent / 'mcp.json')
server = mcp['mcpServers'].pop('tubemaster')
assert server['type'] == 'stdio' and server['command'] == 'npm', server
assert server['args'] == ['run', 'mcp:video-metadata'], server
assert server['cwd'] == str(vendor / 'tubemaster'), server
assert server['exposure'] == 'direct', server
assert server['env']['npm_config_loglevel'] == 'silent', server
assert mcp == load(scratch / 'mcp-original.json'), mcp
profiles = load(agent / 'subagents.json')
assert profiles['model_profiles'].pop('agent-youtube') == {
    'model': 'cpamc/deeprelay/deepseek-v4.1-flash', 'effort': 'high'
}
assert profiles == load(scratch / 'subagents-original.json'), profiles
for stem in ('mcp', 'subagents'):
    backups = list(agent.glob(f'{stem}.json.bak.*'))
    assert len(backups) == int(sys.argv[4]), backups
    assert any(p.read_bytes() == (scratch / f'{stem}-original.json').read_bytes() for p in backups)
PY
}

check_skills() {
    local skill_root skill count
    for skill_root in "$HOME/.agents/skills" "$HOME/.claude/skills"; do
        count=0
        for skill in "$VENDOR_DIR/youtube-agent-skill/skills"/yt-*; do
            diff -r -- "$skill" "$skill_root/${skill##*/}"
            count=$((count + 1))
        done
        [[ $count == 11 ]]
        [[ $(< "$skill_root/yt-unrelated/SKILL.md") == 'unrelated skill' ]]
    done
}

bash "$repo/install.sh" > "$scratch/install.out" 2> "$scratch/install.err" || {
    while IFS= read -r line; do printf '%s\n' "$line" >&2; done < "$scratch/install.err"
    exit 1
}
grep -Fq 'https://github.com/Gentleman-Programming/tubemaster/blob/' "$scratch/install.out"
grep -Fq 'Google OAuth' "$scratch/install.out"
[[ $(git -C "$VENDOR_DIR/youtube-agent-skill" rev-parse HEAD) == a2feb2104981a375ffd4f87ee04f4f5344ac43c6 ]]
[[ $(git -C "$VENDOR_DIR/tubemaster" rev-parse HEAD) == a8497dcd50630c701c5dae5e5e17dfcc9e6819e9 ]]
check_skills
cmp "$voice" "$VENDOR_DIR/youtube-agent-skill/templates/voice.md"
cmp "$agent/agents/agent-youtube.md" "$repo/agents/agent-youtube.md"
check_install 1
printf '%s\n' 'ok - pinned install, skill copies, agent, and config backups'

printf '%s\n' 'my voice' > "$voice"
printf '%s\n' 'stale copy' > "$HOME/.agents/skills/yt-script/SKILL.md"
bash "$repo/install.sh"
check_skills
check_install 1
[[ $(< "$voice") == 'my voice' ]]
printf '%s\n' 'ok - reinstall refreshes skills without changing voice or duplicating config'

bash "$repo/uninstall.sh"
bash "$repo/uninstall.sh"
python3 - "$agent" "$scratch" <<'PY'
import json
import sys
from pathlib import Path

agent, scratch = map(Path, sys.argv[1:])
for stem in ('mcp', 'subagents'):
    before = json.loads((scratch / f'{stem}-original.json').read_text())
    assert json.loads((agent / f'{stem}.json').read_text()) == before
    assert len(list(agent.glob(f'{stem}.json.bak.*'))) == 2
PY
[[ ! -e "$agent/agents/agent-youtube.md" ]]
[[ $(< "$agent/agents/other.md") == 'other agent' ]]
[[ $(< "$voice") == 'my voice' ]]
for skill_root in "$HOME/.agents/skills" "$HOME/.claude/skills"; do
    skills=("$skill_root"/yt-*)
    [[ ${#skills[@]} == 1 && ${skills[0]} == "$skill_root/yt-unrelated" ]]
done
[[ -d "$VENDOR_DIR/tubemaster/.git" && -d "$VENDOR_DIR/youtube-agent-skill/.git" ]]
printf '%s\n' 'ok - uninstall removes managed items only and can repeat'

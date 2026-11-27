#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
: "${YT_SKILL_REPO:?point YT_SKILL_REPO at a local clone of youtube-agent-skill}"
: "${TUBEMASTER_REPO:?point TUBEMASTER_REPO at a local clone of TubeMaster}"
yt_pin=a2feb2104981a375ffd4f87ee04f4f5344ac43c6
tube_pin=a8497dcd50630c701c5dae5e5e17dfcc9e6819e9
bash_bin=$(command -v bash)

scratch=$(mktemp -d)
trap 'python3 -c "import shutil, sys; shutil.rmtree(sys.argv[1])" "$scratch"' EXIT
export VENDOR_DIR="$scratch/vendor with spaces"
export SKIP_NPM=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_ALLOW_PROTOCOL=file
unset PI_SKILLS_DIR CLAUDE_SKILLS_DIR CLAUDE_YOUTUBE_DIR GENTLE_AGENT_DIR
unset AGENT_YOUTUBE_MODEL AGENT_YOUTUBE_EFFORT AGENT_YOUTUBE_OPERATOR

rc=0
run() {
    rc=0
    "$@" > "$scratch/out" 2> "$scratch/err" || rc=$?
}
fail() { printf 'not ok - %s\n' "$*" >&2; exit 1; }
show_streams() {
    while IFS= read -r line; do printf 'out: %s\n' "$line" >&2; done < "$scratch/out"
    while IFS= read -r line; do printf 'err: %s\n' "$line" >&2; done < "$scratch/err"
}
rc_is() { [[ $rc == "$1" ]] || { show_streams; fail "$2: exit $rc, wanted $1"; }; }
out_has() { grep -Fq -- "$1" "$scratch/out" || { show_streams; fail "stdout lacks: $1"; }; }
out_lacks() { ! grep -Fq -- "$1" "$scratch/out" || { show_streams; fail "stdout has: $1"; }; }
err_has() { grep -Fq -- "$1" "$scratch/err" || { show_streams; fail "stderr lacks: $1"; }; }
err_lacks() { ! grep -Fq -- "$1" "$scratch/err" || { show_streams; fail "stderr has: $1"; }; }
file_has() { grep -Fq -- "$2" "$1" || fail "$1 lacks: $2"; }
file_lacks() { ! grep -Fq -- "$2" "$1" || fail "$1 has: $2"; }

use_home() {
    export HOME="$scratch/$1"
    agent="$HOME/.gentle-shell/agent"
    voice="$HOME/.claude/youtube/voice.md"
    pi_root="$HOME/.agents/skills"
    claude_root="$HOME/.claude/skills"
    mkdir -p "$HOME"
}

# The explicit skill list lives in config/paths.sh.
expected=()
while IFS= read -r name; do expected+=("$name"); done < <(source "$repo/config/paths.sh"; printf '%s\n' "${skills[@]}")
[[ ${#expected[@]} == 11 ]]

check_skills() {
    local root name vendor_skills=("$VENDOR_DIR/youtube-agent-skill/skills"/yt-*)
    [[ ${#vendor_skills[@]} == "${#expected[@]}" ]]
    for root in "$pi_root" "$claude_root"; do
        for name in "${expected[@]}"; do
            diff -r -- "$VENDOR_DIR/youtube-agent-skill/skills/$name" "$root/$name"
        done
        [[ $(< "$root/yt-unrelated/SKILL.md") == 'unrelated skill' ]]
    done
}

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
assert server['type'] == 'stdio' and Path(server['command']).is_absolute(), server
assert server['args'] == ['run', 'mcp:video-metadata'], server
assert server['cwd'] == str(vendor / 'tubemaster'), server
assert server['exposure'] == 'direct', server
assert server['env']['npm_config_loglevel'] == 'silent', server
assert mcp == load(scratch / 'mcp-original.json'), mcp
profiles = load(agent / 'subagents.json')
assert profiles['model_profiles'].pop('agent-youtube') == {'effort': 'high'}
assert profiles == load(scratch / 'subagents-original.json'), profiles
for stem in ('mcp', 'subagents'):
    backups = list(agent.glob(f'{stem}.json.bak.*'))
    assert len(backups) == int(sys.argv[4]), backups
    assert any(p.read_bytes() == (scratch / f'{stem}-original.json').read_bytes() for p in backups)
PY
}

snapshot() {
    cksum "$agent/mcp.json" "$agent/subagents.json" "$agent/agent-youtube.manifest.json" \
        "$agent/agents/agent-youtube.md" "$voice"
}

# ---------------------------------------------------------------- usage
for script in install uninstall; do
    run "$bash_bin" "$repo/$script.sh" --help
    rc_is 0 "$script --help"
    out_has 'Usage'
    run "$bash_bin" "$repo/$script.sh" --bogus
    rc_is 2 "$script --bogus"
    err_has 'Usage'
    [[ ! -e "$VENDOR_DIR" ]] || fail "$script usage error created the vendor directory"
done
run "$bash_bin" "$repo/install.sh" --help
for text in --force AGENT_YOUTUBE_MODEL AGENT_YOUTUBE_EFFORT AGENT_YOUTUBE_OPERATOR VENDOR_DIR \
    PI_SKILLS_DIR CLAUDE_SKILLS_DIR CLAUDE_YOUTUBE_DIR GENTLE_AGENT_DIR YT_SKILL_REPO \
    TUBEMASTER_REPO SKIP_NPM 'resolved'; do
    out_has "$text"
done
printf '%s\n' 'ok - --help exits 0 and documents options; unknown arguments exit 2'

# ------------------------------------------- pinned install, existing configs
use_home main
agent="$HOME/.gentle-shell/agent"
mkdir -p "$agent/agents" "$pi_root/yt-unrelated" "$claude_root/yt-unrelated"
printf '%s\n' '{"mcpServers":{"other":{"command":"example","args":["--flag"]}},"setting":true}' > "$agent/mcp.json"
printf '%s\n' '{"model_profiles":{"other":{"model":"example/model","effort":"low"}},"max_concurrency":3}' > "$agent/subagents.json"
printf '%s\n' 'other agent' > "$agent/agents/other.md"
printf '%s\n' 'unrelated skill' > "$pi_root/yt-unrelated/SKILL.md"
cp "$pi_root/yt-unrelated/SKILL.md" "$claude_root/yt-unrelated/SKILL.md"
cp "$agent/mcp.json" "$scratch/mcp-original.json"
cp "$agent/subagents.json" "$scratch/subagents-original.json"

run "$bash_bin" "$repo/install.sh"
rc_is 0 'first install'
out_has 'https://github.com/Gentleman-Programming/tubemaster/blob/'
out_has 'Google OAuth'
out_has 'Installed 11 skills'
out_has 'installed:'
[[ $(git -C "$VENDOR_DIR/youtube-agent-skill" rev-parse HEAD) == "$yt_pin" ]]
[[ $(git -C "$VENDOR_DIR/tubemaster" rev-parse HEAD) == "$tube_pin" ]]
check_skills
cmp "$voice" "$VENDOR_DIR/youtube-agent-skill/templates/voice.md"
agent_file="$agent/agents/agent-youtube.md"
file_lacks "$agent_file" '{{'
file_has "$agent_file" "$voice"
file_has "$agent_file" "$pi_root/yt-audit/SKILL.md"
file_has "$agent_file" 'thinking: high'
file_lacks "$agent_file" 'model:'
file_lacks "$agent_file" 'mcp__tubemaster__apply'
[[ -f "$agent/agent-youtube.manifest.json" ]]
check_install 1
printf '%s\n' 'ok - pinned install, skill copies, rendered agent, and config backups'

# ------------------------------------------------------ reinstall idempotent
before=$(snapshot)
run "$bash_bin" "$repo/install.sh"
rc_is 0 'reinstall'
out_has 'unchanged:'
out_lacks 'updated:'
[[ $(snapshot) == "$before" ]] || fail 'reinstall changed installed files'
check_skills
check_install 1
printf '%s\n' 'ok - reinstall is idempotent'

# ------------------------------------- modified skill: refuse, then --force
printf '%s\n' 'my voice' > "$voice"
printf '%s\n' 'stale copy' > "$pi_root/yt-script/SKILL.md"
run "$bash_bin" "$repo/install.sh"
rc_is 1 'reinstall over a modified skill'
err_has "$pi_root/yt-script"
err_has '--force'
[[ $(< "$pi_root/yt-script/SKILL.md") == 'stale copy' ]]
backups=("$pi_root"/yt-script.bak.*)
[[ ${#backups[@]} == 0 ]]
run "$bash_bin" "$repo/install.sh" --force
rc_is 0 'forced reinstall'
backups=("$pi_root"/yt-script.bak.*)
[[ ${#backups[@]} == 1 && $(< "${backups[0]}/SKILL.md") == 'stale copy' ]] || fail 'modified skill was not backed up'
check_skills
check_install 1
[[ $(< "$voice") == 'my voice' ]]
printf '%s\n' 'ok - modified skill refused without --force, backed up with it; voice untouched'

# ------------------------- uninstall keeps modified, symlinked, and edited
printf '%s\n' 'local edit' >> "$claude_root/yt-seo/SKILL.md"
mkdir -p "$scratch/elsewhere"
rm -rf -- "$pi_root/yt-plan"
ln -s "$scratch/elsewhere" "$pi_root/yt-plan"
printf '%s\n' 'my agent edit' >> "$agent_file"
run "$bash_bin" "$repo/uninstall.sh"
rc_is 0 'uninstall with kept items'
err_has "$claude_root/yt-seo"
err_has 'modified'
err_has "$pi_root/yt-plan"
err_has 'symlink'
err_has "$agent_file"
out_has 'some items were kept'
file_has "$claude_root/yt-seo/SKILL.md" 'local edit'
[[ -L "$pi_root/yt-plan" ]]
file_has "$agent_file" 'my agent edit'
for name in "${expected[@]}"; do
    [[ $name == yt-seo || $name == yt-plan ]] && continue
    [[ ! -e "$pi_root/$name" && ! -e "$claude_root/$name" ]] || fail "$name was not removed"
done
[[ $(< "$pi_root/yt-unrelated/SKILL.md") == 'unrelated skill' ]]
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
printf '%s\n' 'ok - uninstall preserves modified, symlinked, and edited items and says so'

rm -rf -- "$claude_root/yt-seo" "$pi_root/yt-seo" "$pi_root/yt-plan"
rm -f -- "$agent_file"
run "$bash_bin" "$repo/uninstall.sh"
rc_is 0 'second uninstall'
out_lacks 'some items were kept'
run "$bash_bin" "$repo/uninstall.sh"
rc_is 0 'third uninstall'
[[ $(< "$agent/agents/other.md") == 'other agent' ]]
[[ $(< "$voice") == 'my voice' ]]
for root in "$pi_root" "$claude_root"; do
    left=("$root"/yt-*)
    for path in "${left[@]}"; do
        case ${path##*/} in yt-unrelated | yt-script.bak.*) ;; *) fail "left behind: $path" ;; esac
    done
done
[[ -d "$VENDOR_DIR/tubemaster/.git" && -d "$VENDOR_DIR/youtube-agent-skill/.git" ]]
printf '%s\n' 'ok - uninstall completes once items are restored, and repeats'

# ----------------------------------------- fresh install, no existing config
use_home fresh
run "$bash_bin" "$repo/install.sh"
rc_is 0 'fresh install'
for name in mcp.json subagents.json agent-youtube.manifest.json agents/agent-youtube.md; do
    [[ -f "$agent/$name" ]] || fail "fresh install did not create $name"
done
python3 - "$agent" <<'PY'
import json
import sys
from pathlib import Path

agent = Path(sys.argv[1])
assert list(json.loads((agent / 'mcp.json').read_text())['mcpServers']) == ['tubemaster']
assert json.loads((agent / 'subagents.json').read_text()) == {'model_profiles': {'agent-youtube': {'effort': 'high'}}}
assert not list(agent.glob('*.bak.*'))
PY
printf '%s\n' 'ok - fresh install with no pre-existing mcp.json or subagents.json'

# ------------------------------------------- environment reaches update.py
use_home operator
run env AGENT_YOUTUBE_MODEL=example/model AGENT_YOUTUBE_EFFORT=max AGENT_YOUTUBE_OPERATOR=1 \
    "$bash_bin" "$repo/install.sh"
rc_is 0 'operator install'
file_has "$agent/agents/agent-youtube.md" 'model: example/model'
file_has "$agent/agents/agent-youtube.md" 'thinking: max'
file_has "$agent/agents/agent-youtube.md" 'mcp__tubemaster__apply'
file_has "$agent/subagents.json" '"example/model"'
printf '%s\n' 'ok - model, effort, and operator env reach the installed agent and profile'

# ------------------------------------------------------ missing vendor warns
use_home missing
run "$bash_bin" "$repo/install.sh"
rc_is 0 'install for missing-vendor case'
run env VENDOR_DIR="$scratch/no such vendor" "$bash_bin" "$repo/uninstall.sh"
rc_is 0 'uninstall with missing vendor'
err_has 'vendor'
err_has "$pi_root/yt-audit"
out_has 'some items were kept'
[[ -d "$pi_root/yt-audit" && -d "$claude_root/yt-audit" ]]
printf '%s\n' 'ok - missing vendor checkout warns and keeps skills'

# ------------------------------------------------- relative VENDOR_DIR paths
use_home relative
mkdir -p "$scratch/cwd-a" "$scratch/cwd-b"
(cd "$scratch/cwd-a" && VENDOR_DIR=rel-vendor "$bash_bin" "$repo/install.sh") > "$scratch/out" 2> "$scratch/err" || { show_streams; fail 'relative install'; }
file_has "$agent/mcp.json" "$scratch/cwd-a/rel-vendor/tubemaster"
rc=0
(cd "$scratch/cwd-b" && VENDOR_DIR=../cwd-a/rel-vendor "$bash_bin" "$repo/uninstall.sh") > "$scratch/out" 2> "$scratch/err" || rc=$?
rc_is 0 'uninstall from another directory'
out_lacks 'some items were kept'
for name in "${expected[@]}"; do
    [[ ! -e "$pi_root/$name" && ! -e "$claude_root/$name" ]] || fail "relative uninstall kept $name"
done
file_lacks "$agent/mcp.json" tubemaster
printf '%s\n' 'ok - relative VENDOR_DIR works from another directory'

# ------------------------------------------------------------- pre-flight
real_tools="bash sh git python3 diff cp mv rm mkdir date dirname basename cat grep sed tr sort env ls ln chmod cmp find touch head tail wc uname mktemp readlink stat id hostname"
mk_toolbin() {
    local dir=$1 tool omit
    shift
    mkdir -p "$dir"
    for tool in $real_tools; do
        [[ -e "$dir/$tool" ]] || ln -s "$(command -v "$tool")" "$dir/$tool"
    done
    printf '%s\n' '#!/bin/sh' 'echo "${FAKE_NODE_VERSION:-v22.0.0}"' > "$dir/node"
    printf '%s\n' '#!/bin/sh' 'exit 0' > "$dir/npm"
    printf '%s\n' '#!/bin/sh' 'exit 0' > "$dir/yt-dlp"
    printf '%s\n' '#!/bin/sh' 'exit 0' > "$dir/watch-video"
    chmod +x "$dir/node" "$dir/npm" "$dir/yt-dlp" "$dir/watch-video"
    for omit in "$@"; do
        [[ -e "$dir/$omit" || -L "$dir/$omit" ]] && mv -- "$dir/$omit" "$dir.omitted.$omit"
    done
    return 0
}
use_home preflight
mk_toolbin "$scratch/bin-ok"
n=0
for missing in git python3 npm node; do
    n=$((n + 1))
    mk_toolbin "$scratch/bin-$n" "$missing"
    run env PATH="$scratch/bin-$n" VENDOR_DIR="$scratch/pf-vendor" "$bash_bin" "$repo/install.sh"
    rc_is 1 "install without $missing"
    err_has "$missing"
    [[ ! -e "$scratch/pf-vendor" && ! -e "$HOME/.gentle-shell" && ! -e "$HOME/.agents" ]] ||
        fail "install without $missing mutated state"
done
for version in v20.8.0 v19.9.0 v18.20.4 garbage; do
    run env PATH="$scratch/bin-ok" FAKE_NODE_VERSION=$version VENDOR_DIR="$scratch/pf-vendor" "$bash_bin" "$repo/install.sh"
    rc_is 1 "node $version"
    err_has '20.9'
    [[ ! -e "$scratch/pf-vendor" && ! -e "$HOME/.gentle-shell" ]] || fail "node $version mutated state"
done
for version in v20.9.0 v20.10.0 v21.0.0; do
    use_home "pf-$version"
    run env PATH="$scratch/bin-ok" FAKE_NODE_VERSION=$version "$bash_bin" "$repo/install.sh"
    rc_is 0 "node $version"
    err_lacks 'warning'
done
use_home pf-optional
mk_toolbin "$scratch/bin-noopt" yt-dlp watch-video
run env PATH="$scratch/bin-noopt" "$bash_bin" "$repo/install.sh"
rc_is 0 'install without optional tools'
err_has 'yt-dlp'
err_has 'watch-video'
printf '%s\n' 'ok - pre-flight hard-fails before mutating and only warns for optional tools'

# ------------------------------------------------------------ pin handling
use_home pin
mkdir "$scratch/bare-src"
git -C "$scratch/bare-src" init -q
git -C "$scratch/bare-src" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m empty
run env YT_SKILL_REPO="$scratch/bare-src" VENDOR_DIR="$scratch/pin-vendor" "$bash_bin" "$repo/install.sh"
rc_is 1 'pin missing upstream'
err_has "$yt_pin"
[[ ! -e "$HOME/.gentle-shell" && ! -e "$HOME/.agents" ]] || fail 'missing pin mutated state'

# A pin that is reachable but not advertised needs the fetch-all fallback.
git clone -q --bare "$YT_SKILL_REPO" "$scratch/fallback.git"
tip=$(git -C "$scratch/fallback.git" -c user.name=t -c user.email=t@example.invalid \
    commit-tree "$yt_pin^{tree}" -p "$yt_pin" -m 'tip above the pin')
git -C "$scratch/fallback.git" update-ref refs/heads/main "$tip"
git -C "$scratch/fallback.git" symbolic-ref HEAD refs/heads/main
mkdir -p "$scratch/fb-vendor"
git init -q "$scratch/fb-vendor/youtube-agent-skill"
run env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=protocol.version GIT_CONFIG_VALUE_0=0 \
    YT_SKILL_REPO="$scratch/fallback.git" VENDOR_DIR="$scratch/fb-vendor" "$bash_bin" "$repo/install.sh"
rc_is 0 'fallback fetch'
[[ $(git -C "$scratch/fb-vendor/youtube-agent-skill" rev-parse HEAD) == "$yt_pin" ]]

# An untracked file that collides with the pin makes the switch fail clearly.
use_home collide
mkdir -p "$scratch/co-vendor"
git init -q "$scratch/co-vendor/youtube-agent-skill"
git -C "$scratch/co-vendor/youtube-agent-skill" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m empty
git -C "$scratch/co-vendor/youtube-agent-skill" fetch -q "$YT_SKILL_REPO" "$yt_pin"
git -C "$scratch/co-vendor/youtube-agent-skill" ls-tree -r --name-only "$yt_pin" | head -n 1 > "$scratch/first-file"
first=$(< "$scratch/first-file")
mkdir -p "$scratch/co-vendor/youtube-agent-skill/$(dirname -- "$first")"
printf '%s\n' 'in the way' > "$scratch/co-vendor/youtube-agent-skill/$first"
run env VENDOR_DIR="$scratch/co-vendor" "$bash_bin" "$repo/install.sh"
rc_is 1 'untracked collision'
err_has 'untracked'
[[ ! -e "$HOME/.gentle-shell" ]] || fail 'collision mutated state'
printf '%s\n' 'ok - pin fetch fallback, missing pin, and untracked collision'

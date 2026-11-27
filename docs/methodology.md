<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="brand/agent-youtube-logo-white.svg">
    <img src="brand/agent-youtube-logo.svg" width="192" alt="Agent-Youtube logo">
  </picture>
</p>

<h1 align="center">How Agent-Youtube was built and verified</h1>

The installer test checked the filesystem and config changes in a temporary home. A separate real-home check verified tool discovery and ran a drafting demo. Neither check verified Google OAuth or changed a channel.

<p align="center">
  <a href="#spec-and-tasks">Spec and tasks</a> ·
  <a href="#installer-integration-test">Installer test</a> ·
  <a href="#real-installation-and-demo">Real installation and demo</a> ·
  <a href="#design-decisions">Design decisions</a> ·
  <a href="#limits">Limits</a> ·
  <a href="#screenshot-sources">Screenshot sources</a>
</p>

## Spec and tasks

The [ODD task file](../odd/tasks/agent-youtube.md) defines the specs and splits the work into five units:

| Task | Work |
| --- | --- |
| T1 | Build the installer, uninstaller, subagent definition, and tests in the `~/p/agent-youtube` checkout (S1–S5, S7). |
| T2 | Install globally and check skills, agent discovery, and MCP registration (S1–S3). |
| T3 | Document setup, methodology, and captured output for the public repo (S6). |
| T4 | Create the public GitHub repo and push it (S6). |
| T5 | Add the README cover, branding, badges, and navigation (S8). |

The ODD test-first sequence is RED (observe a behavior test failing before the implementation) and GREEN (observe it passing after the fix). The integration test sets out the expected install, reinstall, and uninstall behavior as assertions. The captured run below is a passing rerun for the docs; the evidence does not include the original RED transcript.

## Installer integration test

[`tests/test_install.sh`](../tests/test_install.sh) creates a fresh temporary `HOME` and a vendor path containing spaces, then removes the scratch directory on exit. It uses local upstream Git clones, allows only the local-file Git protocol, and sets `SKIP_NPM=1`. It seeds unrelated skill and config entries to check that they survive.

The run against implementation commit `29ccc1583e1a0c85e61ea46cd1da76bf4a937cd0` exited 0. The [installer screenshot](assets/install-test.png) shows its three `ok` lines:

1. The first install checked both commit pins, both sets of 11 skill copies, the agent definition, the voice template, and the original config bytes in backups.
2. Reinstall refreshed an edited skill copy without overwriting a filled voice profile or creating duplicate config entries or backups.
3. Two uninstall runs removed matching installed items, kept unrelated entries and vendor checkouts, and backed up configs only when changing them.

## Real installation and demo

The recorded real-home verification was separate from the integration test:

| Check | Observed result |
| --- | --- |
| Skill directories | 11 skills in `~/.agents/skills/` and 11 in `~/.claude/skills/`. The [skill screenshot](assets/skills.png) shows the Pi paths. |
| Agent discovery | `subagent_list_agents` listed `agent-youtube` with 27 TubeMaster MCP tools. The profile was `cpamc/deeprelay/deepseek-v4.1-flash`, effort `high`. |
| MCP startup | The TubeMaster stdio server returned 27 tools to `tools/list`. This checked startup and discovery, not access to an authenticated channel. |
| Drafting demo | The agent scored five hooks and linted three title/thumbnail pairs for a video about 30 days with AI coding agents. It revised the hooks after the first pass rated all five `WEAK`; the top revised hook scored 67 (`WORKABLE`). It picked “I Let AI Agents Write Every Line for 30 Days” with “HOW BAD?” as thumbnail text. It flagged the unfilled voice profile, invented no numbers, and published nothing. |

## Design decisions

- Pin both Git checkouts and keep `vendor/` out of version control. The installer can use local clones for tests, and the project does not copy upstream history or TubeMaster dependencies into its own Git history.
- Install skills globally for Pi (`~/.agents/skills/`) and Claude Code (`~/.claude/skills/`). Keep a single voice profile at the path the upstream skills expect; put the subagent and its runtime config in Gentle Shell.
- Parse and validate both JSON configs before writing. Change only the package's named entries; save the old bytes of existing files to timestamped backups and replace each changed file atomically. Preserve unmatched entries on uninstall.
- Use DeepSeek V4.1 Flash as the lower-cost default, with `high` effort for requests that need several tools or drafting passes. No cost benchmark was run.
- Reuse `watch-video` for transcripts and frames and `yt-dlp` for public metadata. Route authenticated channel operations to TubeMaster, and require separate user confirmation of the exact mutation after showing its preview or proposed change.

## Limits

Google OAuth was not configured during verification. Follow the [manual setup](../README.md#tubemaster-oauth) to use authenticated tools. Fill `~/.claude/youtube/voice.md` before asking for drafts in your voice; the demo ran with the template still unfilled. `hookscore.py` applies writing heuristics and cannot predict retention. `title.py` lints the supplied copy; it does not measure click-through rate.

## Screenshot sources

The static HTML in [`assets/src/`](assets/src/) contains the captured text: the demo excerpt, installed Pi skill paths, tool outputs, and the three `ok` lines from the temporary-home test. The [direct tool commands](../README.md#usage) use the same hook and title/thumbnail pair as the captures. To render a PNG from its source, run this from the checkout with `CHROME_PATH` set to your Chrome executable, changing `name` for the other captures:

```bash
name=hookscore
"$CHROME_PATH" --headless --disable-gpu --screenshot="$PWD/docs/assets/$name.png" \
  --window-size=1200,800 "file://$PWD/docs/assets/src/$name.htm"
```

If Flatpak Chrome cannot see the checkout, grant access to `docs/assets/` for this launch only:

```bash
flatpak run --filesystem="$PWD/docs/assets" com.google.Chrome \
  --headless --disable-gpu --screenshot="$PWD/docs/assets/$name.png" \
  --window-size=1200,800 "file://$PWD/docs/assets/src/$name.htm"
```

The README cover is an illustration of the recorded drafting demo. To render it at 1600 × 800 from [`assets/src/cover.htm`](assets/src/cover.htm), run from the checkout:

```bash
flatpak run --filesystem="$PWD/docs/assets" com.google.Chrome --headless --disable-gpu --user-data-dir="$(mktemp -d)" --screenshot="$PWD/docs/assets/cover.png" --window-size=1600,800 "file://$PWD/docs/assets/src/cover.htm"
```

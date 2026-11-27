# Agent-Youtube

Pi/Gentle Shell subagent `agent-youtube` preloaded with the youtube-agent-skill pack (11 skills + 6 Python tools), TubeMaster MCP and the local watch-video pipeline.
Repo: ~/p/agent-youtube (public GitHub repo RamonsDka/agent-youtube). Global install via `install.sh`.

## Specs

- S1: "nesecito que instale esto de manera global https://github.com/jakeschincariol/youtube-agent-skill" — all 11 `yt-*` skills installed globally (Pi discovers `~/.agents/skills/`; Claude Code `~/.claude/skills/`), pinned to upstream commit a2feb2104981a375ffd4f87ee04f4f5344ac43c6, voice template available at `~/.claude/youtube/voice.md` (never overwrite an existing filled one).
- S2: "creamos un agente directamente con todas estas capacidades, se llamaria Agent-Youtube" — a Gentle Shell subagent definition `agent-youtube` (installed to `~/.gentle-shell/agent/agents/agent-youtube.md`, model profile `cpamc/deeprelay/deepseek-v4.1-flash`, effort high, in `~/.gentle-shell/agent/subagents.json`) whose prompt routes requests to the 11 skills, their Python tools, TubeMaster and watch-video.
- S3: "algo como esto tambien: https://github.com/Gentleman-Programming/tubemaster" — TubeMaster cloned to `vendor/tubemaster` (gitignored, pinned a8497dcd50630c701c5dae5e5e17dfcc9e6819e9), `npm install`, MCP server registered in `~/.gentle-shell/agent/mcp.json` as `tubemaster` (stdio, `npm run mcp:video-metadata`), inactive until the user adds Google OAuth in `vendor/tubemaster/.env.local`. mcp.json backed up before editing.
- S4: "y si entiendes que mas cosas pues dale" — reuse already-installed `watch-video` (video-watcher skill) and `yt-dlp` for transcripts/public listings; nothing new heavy.
- S5: "crea uba carpeta en ~/p/agent-youtube y trabaja desde aqui y aqui hacemos todo, el git, todo"
- S6: "despues creamos un repo de github con imagenes capturas, metodologia, todo." — public repo with README, docs/methodology.md, screenshots in docs/assets/.
- S7: Agent never publishes or mutates a channel without explicit user confirmation (inherits both upstream guarantees).

## Tasks

- T1 [S1,S2,S3,S4,S5,S7] repo scaffold: install.sh (idempotent, backups), agents/agent-youtube.md, tests — writer — commit:
- T2 [S1,S2,S3] run install.sh, verify global install — parent — commit: n/a
- T3 [S6] README, methodology, screenshots — writer — commit:
- T4 [S6] gh repo create public + push — parent

## Log

- L1: nesecito que instale esto de manera global https://github.com/jakeschincariol/youtube-agent-skill pero tambien creo que seria recomendable y optimo si creamos un agente directamente con todas estas capacidades, se llamaria Agent-Youtube / le precargariamos esto / - https://github.com/jakeschincariol/youtube-agent-skill / - algo como esto tambien: https://github.com/Gentleman-Programming/tubemaster / y si entiendes que mas cosas pues dale / crea uba carpeta en  ~/p/agent-youtube y trabaja desde aqui y aqui hacemos todo, el git, todo, despues creamos un repo de github con imagenes capturas, metodologia, todo.
- L2: User decisions: repo public; TubeMaster cloned + MCP registered, user supplies OAuth; agent model deepseek-v4.1-flash.

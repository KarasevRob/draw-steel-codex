# AGENTS.md

This file provides Codex-specific guidance for the `draw-steel-codex` repository.

## Required Repository Guidance

Before modifying files in this repository, read `CLAUDE.md` in full. Treat its
architecture, lifecycle, Lua constraints, editing, and deployment guidance as
repository instructions, subject to the overrides below. Also read any
directory-specific `CLAUDE.md` that applies to the files being changed, including
`ClaudeBridge/CLAUDE.md` for the standalone Claude integration module.

## Codex Overrides

- User, system, skill, and `AGENTS.md` instructions take precedence over
  `CLAUDE.md`.
- For compendium content under `data/`, use `validate_yaml.py` and the live
  references under `data/docs/`. Those sources supersede legacy compendium
  paths or content-workflow guidance in `CLAUDE.md`.
- Where `CLAUDE.md` names Claude Code or Claude-specific tools, use the
  equivalent Codex workflow or tool. If a required integration is unavailable,
  stop and ask the user instead of inventing a substitute.
- This is a nested Git repository with its own history. Run Git commands from
  this repository, not from the parent DMHub repository.

## Claude-to-Codex Workflow Mapping

Keep the same domain rules, evidence requirements, review gates, cleanup, and reporting
contracts as the Claude workflows. Adapt the agent interface and paths, not the work's
scope. Existing user authorization still applies; a copied skill does not require asking
again for an action the user already authorized.

| Claude instruction | Codex equivalent |
|---|---|
| Read / Grep / Glob / Bash | Read files and use `rg` / `rg --files` through the available shell; use PowerShell-compatible commands on Windows. |
| Edit / Write | Use `apply_patch` or an available file-editing tool. |
| `Explore` agent | A bounded Codex `explorer` subagent. |
| `general-purpose` agent | A Codex `default` or `worker` subagent appropriate to the task. |
| AskUserQuestion | The available user-input tool; retain any real prerequisite or approval gate. |
| ToolSearch / deferred MCP names | Discover the tools exposed in the current session; use the matching capability and its actual schema. |
| `mcp__dmhub__lua_status` | The current bridge's `mcp__dmhub__get_status`. |
| `.claude/skills/<name>/` helpers | The corresponding `.agents/skills/<name>/` helpers. |

Use the `monster_ability_tester` Codex role for the Claude monster-ability tester workflow.
The broad `codexmod` workflow is available as the `dmhub-modding` skill.

## Skills and Shared Guidance

Repository Codex skills live in `.agents/skills/`. Their upstream workflows and supporting
resources live in `.claude/skills/`; keep them in sync when changing shared behavior.
Preserve Codex tool mappings, the live `data/` workflow, and prerequisite checks for
optional sources such as the engine checkout or Crowdex. Keep one discoverable skill per
name. Do not copy personal settings, credentials, model choices, or permission allowlists
from Claude configuration into Codex configuration.

`main.lua` remains an informational index. Register new top-level Lua files through the
live DMHub `register_lua_file` workflow and confirm persistence, including when an older
skill still describes adding a `require` or asking the user to register manually.

## Validation and Hooks

Run the syntax and type checks required by `CLAUDE.md`. Its Claude Stop hook is not a
Codex hook: run the checks explicitly rather than assuming that hook will enforce them.
Check that the referenced parent-checkout tools and baseline exist before using them;
report a missing prerequisite and do not claim an unavailable check passed. The local
Codex comment-style hook only supplies guidance; it does not validate Lua.

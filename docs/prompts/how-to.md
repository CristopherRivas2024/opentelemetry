# How-To: Feature Prompts

Copy-pasteable prompts for starting an SDD-driven configuration change in a fresh Claude Code session. Each prompt lives in its own file under `docs/prompts/`. Open the file, copy the content, paste into a new session.

## How to use

1. Open a fresh Claude Code session at the repo root.
2. Pick a prompt file from this directory and copy its full content.
3. Paste into the chat — Claude invokes the SDD orchestrator; approve or redirect each phase.
4. The central conversation stays thin — every read of 2+ files, every write, and every `docker compose`/`make`/`gga`/`curl`/`yq` invocation is delegated to a sub-agent.
5. The final phase always produces: feature doc, at least one diagram, updated indexes, and a toDo file.

## Common rules (baked into every prompt)

- **SDD + Engram**: `/sdd-new <change-name>` with `artifact_store=engram`, interactive mode.
- **Context first**: run the listed `mem_search` queries before exploring so the sub-agent reuses prior project conventions instead of reinventing them.
- **Sub-agent delegation**: any read of 2+ files, any write, any `docker compose up/down`, `make`, `curl` to verify, `gga run` execution → delegated. The main thread only orchestrates, relays summaries, and asks the user.
- **GGA on every commit**: the pre-commit hook runs `gga run`; on failure, fix via sub-agent and re-commit. Never `--no-verify` unless the issue is pre-existing.
- **Conventional commits**, no Co-Authored-By, no AI attribution in commit bodies.
- **Engram session close**: `mem_session_summary` is mandatory before the sub-agent declares "done".
- **Final deliverables (every prompt)**:
  - `docs/<change-name>.md` following [docs/how-to.md](../how-to.md)
  - At least one Mermaid diagram in `docs/diagramas/<flow-name>.md` per [docs/diagramas/how-to.md](../diagramas/how-to.md)
  - Row added to the Contents table in [docs/index.md](../index.md)
  - Row added to the Lista table in [docs/diagramas/index.md](../diagramas/index.md)
  - `docs/toDo/<change-name>.md` listing every deferred item with: current state, why it's debt, when to tackle, acceptance criteria

## Writing new prompts

When adding a new feature prompt:

- **One file per prompt**: create `docs/prompts/<change-name>.md` (kebab-case, no numeric prefix). The file IS the prompt — no surrounding prose, just the text the user will paste.
- **Self-contained**: a fresh Claude session should need nothing else to execute it. Do not reference "the section above" or other prompt files from inside the prompt.
- **Scope-explicit**: state what is IN and OUT of scope so SDD does not sprawl.
- **Engram-seeded**: list the `mem_search` queries to run before exploring (project: `opentelemetry`).
- **Deliverables-explicit**: feature doc, at least one diagram, both index updates, and a toDo file.
- **No inline YAML/Bash snippets** — the prompt is a seed, not a recipe. The sub-agent produces concrete config during SDD; details land in the resulting feature doc, not in the prompt.
- **Short**: ≤ 40 lines. If it grows, split into two changes.

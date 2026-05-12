# How-To: Feature Documentation

Each substantial feature gets a `docs/{feature-name}.md`. Keep it focused and linkable from the index.

## File location and naming

- One doc per feature, kebab-case filename, placed at `docs/` root (not nested under subdirectories).
- After creating the file, add a row to the table in `docs/index.md`.
- Diagrams live separately under `docs/diagramas/` — link to them from the feature doc.

## Required sections

Every feature doc must include these sections in order:

| Section | Template |
|---------|----------|
| `# {Feature Name}` | H1 title + one-sentence description of what the feature is |
| `## What it does` | 2–4 sentences: what problem it solves and how it fits the stack |
| `## Configuration` | Env vars, config files, or option blocks that control behavior |
| `## Files touched` | Table with two columns: `Path` and `Role` |
| `## Verification` | One or two commands the operator can run to confirm the feature works end-to-end |
| `## Related` | Relative links to other docs and diagrams |

## Optional sections

Include these only when relevant:

| Section | When to add |
|---------|-------------|
| `## Behavior matrix` | When the feature has conditional logic — map input → output in a table |
| `## Trade-offs` | When the design picked option A over B and the reader needs to know why |
| `## Deferred follow-ups` | When a `toDo/{feature}.md` file exists — add a short note and link |

## Rules

- **Max ~100 lines** per feature doc. If it grows beyond that, split into diagrams or a dedicated section.
- **No copy-paste from source** — the source IS the docs for implementation details. Describe WHAT and WHY; let the YAML and code show HOW.
- **Tables over prose** for structured data (env vars, port maps, file lists, behavior branches).
- **Relative links only** — `[stack-architecture.md](diagramas/stack-architecture.md)`, never absolute URLs to local files.
- **One language per doc** — English at `docs/` root, Spanish body prose in `docs/diagramas/`.
- **Don't document upstream tool features** — only the project-specific behavior and decisions (e.g. why this stack uses tail sampling, NOT how `tail_sampling` works in general).
- **No frontmatter** — no YAML headers, no date prefixes, no numeric prefixes on filenames.

## Example skeleton

```markdown
# My Feature

One sentence describing what this feature is.

## What it does

Two to four sentences explaining the problem it solves and how it integrates with the stack.

## Configuration

| Env var | Default | Notes |
|---------|---------|-------|
| `MY_FEATURE_ENABLED` | `false` | Toggle the processor |

## Files touched

| Path | Role |
|------|------|
| `config/otel-collector-gateway.yaml` | Pipeline wiring |
| `docker-compose.yml` | Env var passthrough |

## Verification

```bash
make up
curl -s http://localhost:9090/api/v1/query?query=my_feature_metric | jq .
```

## Related

- [Diagram: my-feature-flow](diagramas/my-feature-flow.md)
- [toDo/my-feature.md](toDo/my-feature.md)
```

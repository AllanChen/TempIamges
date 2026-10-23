---
description: Migrate skills from OpenCode (or other tools) to Codex
---

## /migrate-skills

Migrate skills from external tools (OpenCode, Cursor, etc.) into this project's `.Codex/skills/` directory.

### Steps

1. **Verify source path** — Ask user to confirm (default: `~/.config/opencode/skills/`). Do not assume.
2. **Discover skills** — List all skill files in the source directory. Report count before migrating.
3. **Batch in groups of 5** — Pause after each batch and ask: *"Continue with next batch?"*
4. **Migrate each skill** — Create corresponding `.Codex/skills/<name>/SKILL.md` with proper frontmatter.
5. **Validate** — List all skills in the project with `Codex skills list` or equivalent check.
6. **Report** — Summarize: total found, migrated, failed (with reasons).

### Rules

- Never guess the source path. Always verify with the user.
- If a skill with the same name exists, ask whether to skip or overwrite.
- Stop and confirm after every 5 skills to avoid session interruption.

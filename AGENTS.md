# Agent rules

Follow the project rules in [CLAUDE.md](CLAUDE.md).

After changing code, leave UI testing to the user by default. Do not launch
Glance or operate its interface for verification unless the user explicitly
requests UI testing. This includes AppleScript, screen capture, simulated input,
and computer-use tools. Non-UI code checks are allowed when appropriate.

When the user explicitly requests operating supported desktop software, read
`/Users/mac/.codex/skills/flue/SKILL.md` before using Flue.

## Repository layout

Read [spec.md](spec.md) and [docs/project-structure.md](docs/project-structure.md) before moving files or adding a new module.

- macOS production code: `clients/macos/Glance/`; platform scripts: `clients/macos/scripts/`.
- Windows: `clients/windows/` is a placeholder only. Do not imply a Windows release exists.
- API, admin and database: `server/GlanceService/`; CLI/Worker: `server/glance-cli/`; Widget projects: `server/widgets/`.
- Production website: `website/static/`; retained React/Vinext site: `website/app/`; SEO: `website/seo/`.
- Product and engineering documentation: `docs/`.
- App screens, Figma plugin and UI specifications: `design/app/`; promotional assets and videos: `design/marketing/`; website design evidence: `design/website/`.

Keep root `run.sh`, `run`, and `glance-cli-run.sh` as forwarding entry points. New screenshots, media, prototypes and build outputs belong in their category, not the repository root. Preserve hidden tool configuration and local environments unless the task requires migrating them.

When paths change, update scripts, CI, asset references and relative documentation links together. Do not change API routes, identifiers, prices or deployment state as a side effect of a filesystem move. Preserve unrelated working-tree changes. Consult [the migration record](docs/repository-reorganization.md) for current verification commands and local registration considerations.

`agent.md` forwards here; keep this file as the single agent-rule entry point.

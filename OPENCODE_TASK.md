# OpenCode Task — Read the Misty OS macOS Master Prompt

Before changing code, read the complete engineering specification:

- [docs/MISTY_OS_MACOS_MASTER_PROMPT.md](docs/MISTY_OS_MACOS_MASTER_PROMPT.md)

Your task is to implement that specification in this repository, not merely summarize it.

1. Pull/fetch the latest main and inspect the current working tree, open PRs, branches, recent commits, and active GitHub Actions runs. Preserve user changes.
2. Read the master prompt completely and audit both reference repositories and their licenses.
3. Report a concise feature/file/status matrix, then create a feature branch from the latest main.
4. Port suitable macOS UI/behavior from the React reference projects into native Flutter. Do not import their simulated filesystem/browser/terminal as substitutes for Misty OS's real Linux functionality.
5. Implement the work in small, testable phases. Keep Finder, terminal, browser, OpenCode, Android storage, PRoot, VNC, and credentials connected to real underlying services.
6. Run focused tests after each phase, then the full Flutter/static/script checks and ARM64 APK build listed in the master prompt.
7. Commit and push the branch, open a PR to main, monitor Actions, inspect and fix real failures, and report verified results.
8. Do not merge failing or unreviewed work. Do not claim device tests, FPS, browser acceleration, or feature completion without evidence.
9. Final report must include PR and commit links, files changed, tests, known blockers, Actions status, APK artifact link, APK size, and SHA-256.

Start with the audit, then implement. Do not stop at a plan.

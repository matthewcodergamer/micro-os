# Repository instructions for coding agents

## Work efficiently and preserve evidence

- Read the root README and this file once at the start of a task. Do not repeatedly dump the whole repository into context.
- Inspect only the relevant files and narrow line ranges. Use `rg`, `grep`, `sed`, or targeted GitHub file reads before opening large files.
- Prefer focused diffs and small commits. Do not reformat unrelated files or rewrite working subsystems.
- Keep command output concise. Suppress progress bars when possible, but retain the actual error, exit code, and a small amount of surrounding context.
- Preserve UTF-8 output. Never delete or rewrite text merely because it looks garbled; first diagnose the encoding boundary.
- If the same command fails twice for the same reason, stop retrying. Report the exact command, exit code, relevant error, and the smallest next action that needs a decision.
- Do not try unrelated package managers, use `sudo` as a reflex, or repeat expensive installs after a clear permission/dependency failure.
- Before a costly or destructive multi-stage operation, state the intended steps and ask for approval unless the user has already authorized that exact work.
- Never claim a test, device check, benchmark, or deployment succeeded unless its output proves it. Distinguish CI tests from physical-device tests.

## OpenCode session and credit hygiene

- Keep prompts task-specific. Reuse the repository's README/AGENTS.md instructions instead of pasting long handoffs into every request.
- Avoid rereading unchanged files; use `git diff`, `git status --short`, and targeted excerpts.
- Do not send full build logs to the model. Extract the failing step and a bounded error excerpt.
- Provider-side prompt caching and retry billing depend on the selected model/provider. Do not claim that a mobile client disables caching or that a network retry is always billed twice.
- Use the OpenCode session controls supported by the installed version to start a fresh session or compact context. Do not invent a custom `/clear` slash command unless the installed CLI supports it.

## MicroOS constraints

- Target: ARM64 Android, including low-memory 4 GB devices.
- The Linux guest is Ubuntu in PRoot, not a separate kernel. Do not assume root privileges, sysctl access, systemd, hardware GPU access, or shared Android/guest loopback without testing.
- Do not disable Chromium's software rasterizer as a generic speed fix; it may be the only usable rendering path in the virtual X11 environment.
- Avoid Chromium `--single-process` for normal browsing; it is fragile and can turn one renderer failure into a whole-browser failure.
- Treat VNC latency, guest browser rendering, and internet throughput as separate measurements.
- Do not add x11vnc cache/compression flags without verifying compatibility with the bundled noVNC client and measuring memory/latency on device.

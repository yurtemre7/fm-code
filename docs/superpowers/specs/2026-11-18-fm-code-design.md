# fm-code — design

## Intent
A local CLI that generates a one-line Conventional Commit message (≤ 72 chars, no body, no
attribution) for the staged changes in a git repo, using Apple's on-device Foundation Models
on Apple Silicon. Bare and fast: no chat, no config, no network.

## Goals
- `fm-code` prints a single commit subject line for the staged diff.
- `fm-code -c` shows the message and asks `[y]es / [e]dit / [n]o`, then runs `git commit -m`.
- `fm-code --hook` installs a `prepare-commit-msg` hook so `git commit` gets the suggestion prefilled.
- The model gathers context itself via a read-only git tool.

## Non-goals
- Commit bodies, trailers, attribution.
- Chat UI, other tools, config files, multiple model backends.

## Anti-goals
- The model must never be able to modify the repo or run arbitrary commands.
- Messages over 72 chars or not in Conventional Commit form.

## Constraints
- macOS 26+ with Apple Intelligence enabled; Apple Silicon.
- On-device model context is ~4K tokens → tool output must be truncated.
- `FoundationModels` is Swift-only → Swift (Rust considered and rejected: would need a Swift
  shim over C FFI and lose `@Generable` and `Tool`).

## Approaches
- **Swift CLI with `Tool` calling (chosen).** `LanguageModelSession` + one `GitTool`; model
  decides which allowlisted git commands to run. Matches the "model calls git" requirement.
- Diff stuffed into prompt, no tools. Simpler but doesn't let the model pick context.
- Mac GUI app / chat app. Rejected by user in favor of a terminal workflow.

## Design
- **Package:** Swift Package (`Package.swift`, opens in Xcode), executable `fm-code`, plus a
  library target `FMCodeCore` holding testable logic (formatting, validation, allowlist,
  truncation) and a test target.
- **GitTool:** `Tool` with `@Generable` arguments selecting one of an enum of commands:
  `diff --staged`, `diff --staged --stat`, `status --short`, `log --oneline -n 10`.
  Executed via `Process` (`/usr/bin/git`, argv array, no shell). Output truncated to a
  fixed character budget (~6000 chars) with a `[truncated]` marker.
- **rtk (optional):** if `rtk` is found (on `PATH`, else `/opt/homebrew/bin`, `/usr/local/bin`
  — hooks may run with a thin `PATH`), the GitTool runs `rtk git <args>` instead of
  `git <args>` for further compacted output. If rtk exits non-zero, fall back to plain git.
  `FM_CODE_NO_RTK=1` disables it. Only the model's tool calls use rtk; preflight, hook
  install and `git commit` always use plain git (exit codes and exact output matter there).
- **Output:** `@Generable struct CommitMessage { type, scope?, subject, breaking }`.
  `type` constrained to Conventional Commit types (feat, fix, docs, style, refactor, perf,
  test, build, ci, chore, revert). Swift renders `type(scope)!: subject`.
- **Validation:** if > 72 chars, retry once asking for a shorter subject; then drop scope;
  then hard-trim subject. Lowercase-first subject, no trailing period.
- **Errors:** not a git repo / nothing staged / model unavailable → clear message, exit 1.
- **Hook mode:** writes `.git/hooks/prepare-commit-msg` that calls `fm-code` only when no
  message source is given (`$2` empty), writing into `$1`. Refuses to overwrite an existing
  hook.
- **Install:** `swift build -c release`, copy `.build/release/fm-code` into `PATH`.

## Left to the builder
Prompt wording, exact truncation budget, arg parsing (hand-rolled; no dependencies).

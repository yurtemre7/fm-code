# fm-code

One-line [Conventional Commit](https://www.conventionalcommits.org) messages for your staged
changes, written by Apple's on-device Foundation Model. Local, private, no API keys.

```
$ git add -p
$ fm-code
feat(parser): add fenced code block support
```

## Requirements

- Apple Silicon Mac, macOS 26 or later
- Apple Intelligence enabled (System Settings › Apple Intelligence & Siri)
- git (Xcode Command Line Tools)
- Optional: [rtk](https://github.com/rtk-ai/rtk) for more compact git output to the model

## Install

```sh
./install.sh
```

This builds a release binary, copies it to `/usr/local/bin` (it asks for `sudo` only if that
folder isn't writable), and runs `fm-code doctor` so you can see your setup right away.
To install somewhere else:

```sh
INSTALL_DIR=~/.local/bin ./install.sh
```

Re-run `./install.sh` after pulling changes to update. To do it by hand:
`swift build -c release && cp .build/release/fm-code /usr/local/bin/`.

Open `Package.swift` in Xcode to build, run and debug.

## Start here

```sh
fm-code doctor
```

Checks your Mac, the on-device model, git, rtk and the current repo, and shows exactly
what the model is allowed to do.

## Usage

| Command | What it does |
|---|---|
| `fm-code` | Prints a commit message (≤ 72 chars, no body) for the staged changes |
| `fm-code -c` | Shows the message, then `[y]es / [e]dit / [n]o` before running `git commit` |
| `fm-code --hook` | Installs a `prepare-commit-msg` hook so plain `git commit` gets the suggestion prefilled |
| `fm-code doctor` | Setup check |

## What the model can do

It gets a single tool that runs **read-only** git commands, chosen from a fixed list:
`git diff --staged`, `git diff --staged --stat`, `git status --short`,
`git log --oneline -n 10`. Commands run without a shell. Output is capped at 6000
characters to fit the model's small context. The model never changes your repo; only
`fm-code -c` commits, after you confirm.

## Environment

- `FM_CODE_NO_RTK=1` — don't use rtk even if installed
- `FM_CODE_DEBUG=1` — print the git commands the model runs to stderr

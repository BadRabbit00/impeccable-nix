# impeccable-nix

> **impeccable is created by Paul Bakaus** ([github.com/pbakaus/impeccable](https://github.com/pbakaus/impeccable), site: [impeccable.style](https://impeccable.style)). All credit for the skill, the agents and the engine goes to him.
>
> This repository contains **only Nix packaging**, made by BadRabbit00. It is **not affiliated with or endorsed by** upstream. The upstream code is not vendored: it is fetched from `pbakaus/impeccable` through a flake input.
>
> Found a bug in the skill or the engine? Report it **upstream**. Found a bug in the packaging (build, wiring, Home Manager module)? Report it **here**.

## What you get

- `packages.<system>.impeccable`: the Rust engine, built from the upstream workspace (`crates/cli`).
- `packages.<system>.impeccable-skill` (also `default`): the upstream skill and its four agents, with the engine placed at `scripts/bin/<os>-<arch>/impeccable`. The upstream launcher finds it there without any environment variable and never reaches its download path.
- `homeManagerModules.default`: `programs.impeccable`, which installs all of this for Claude Code.
- `overlays.default`: adds `impeccable` and `impeccable-skill` to `pkgs`.

Layout of `impeccable-skill`:

```
skills/impeccable/      the skill (SKILL.md, reference/, scripts/)
agents/*.md             the four subagents
LICENSE, NOTICE.md      upstream license and notices
```

Supported systems: `x86_64-linux`, `aarch64-linux` (built and checked on x86_64-linux). The darwin outputs use the same rules but are untested.

## Usage

Add the input (it follows your nixpkgs through `inputs.nixpkgs.follows` if you wish):

```nix
inputs.impeccable-nix.url = "github:BadRabbit00/impeccable-nix";
```

### Home Manager (NixOS module or standalone)

```nix
{ inputs, ... }:
{
  imports = [ inputs.impeccable-nix.homeManagerModules.default ];

  programs.impeccable = {
    enable = true;
    # hooks.enable = true;
  };
}
```

### Just the package

```sh
nix build github:BadRabbit00/impeccable-nix#impeccable-skill
nix run github:BadRabbit00/impeccable-nix#impeccable -- engine-probe
```

## Options (`programs.impeccable`)

| Option | Default | Meaning |
| --- | --- | --- |
| `enable` | `false` | Install the skill. |
| `package` | `impeccable-skill` of this flake | Skill package. |
| `claudeConfigDir` | `null` | Claude Code config dir, relative to `$HOME` or absolute. `null` means `programs.claude-code.configDir` when that Home Manager module is enabled, else `.claude`. Quotes, `$`, backticks, backslashes, `..` and `//` are rejected. The skill goes to `<dir>/skills/impeccable`. |
| `agents.enable` | `true` | Install the four agents into `<dir>/agents` (per-file links, so your own agents there are kept). |
| `hooks.enable` | `false` | Merge the impeccable hooks into `<dir>/settings.json` (see below). |
| `telemetry.enable` | `false` | When `false`, `"telemetry": false` is written to `~/.impeccable/config.json` if that file has no `telemetry` key. An existing value is never overwritten. |

### Hooks

There are two paths, picked automatically:

- **`programs.claude-code` is enabled** (Home Manager's own module, which owns `settings.json` as a store symlink): the entries are added to `programs.claude-code.settings.hooks` and no activation script runs. With `programs.claude-code.mutableSettings = true` Home Manager merges them with `$dynamic * $static`, so arrays you declare for the same events replace the ones already in the file.
- **Otherwise** an activation script (after `linkGeneration`) merges them into `<dir>/settings.json` with `jq`. If that file is a symlink into `/nix/store`, or a dangling symlink, the script prints a message and leaves it alone. New files are created with mode 0600. A file that is not exactly one JSON object whose hook events are arrays is left untouched with a warning. Only hook groups and events that became empty because the script removed its own entries are dropped.

The two entries are `PostToolUse` (matcher `Edit|Write`, 5 s) and `Stop` (30 s). The command string has exactly the form the engine itself writes for a user-scope install (`[ ! -f '<launcher>' ] || '<launcher>' hook`), so the engine recognises the entries as its own and does not add duplicates. Other keys and other hooks in the file are kept; entries pointing at an impeccable launcher are replaced, so re-running activation is idempotent. A file that is not valid JSON is left untouched. The upstream plugin's `SessionStart` hook is not installed because the engine does not wire it for user-scope installs. Turning the option off later does not remove entries already written.

In the activation path `settings.json` is intentionally not managed by `home.file`: Claude Code writes to it.

### Why the telemetry default is a config file

The engine honours `DO_NOT_TRACK` and `IMPECCABLE_NO_TELEMETRY`, but an environment variable only reaches it if Claude Code was started from a session that has it. `~/.impeccable/config.json` is read by the engine on every run, so it works for desktop launchers and hooks too.

## What the engine does on its own

Found by reading upstream `crates/` (version 0.1.22); verify against the version you use.

- **Network.** `context` checks for a newer skill version and writes `~/.impeccable/update-check.json`. This package disables that check by default (a tiny patch to the packaged launcher sets `IMPECCABLE_NO_UPDATE_CHECK=1` unless you set the variable yourself; set it to an empty string to re-enable). The verbs `concept-seed` and `serve-question` call `https://impeccable.style/api` (a roll and a choice ping); with telemetry off the roll still happens and the server records nothing.
- **`~/.impeccable/`.** Besides the config and update cache above, the engine keeps a hook claim file there, a seed salt, and (via `IMPECCABLE_AGENTS_HOME`) agent data. `engine-probe` and the launcher itself write nothing there.
- **Project directory.** State lives in `<project>/.impeccable/` (config, seed ledger, hook cache, build state, mocks).
- **`settings.json`.** The engine's own hook wiring (`hooks on`, `crates/hook/src/admin.rs:592-674`) rewrites the user's `<dir>/settings.json` atomically, keeping other keys. If Home Manager owns that file as a store symlink, this fails or replaces the link, so do not run `hooks on` there; declare hooks through the module instead.

### Defaults this package changes

The packaged launcher (`scripts/impeccable`) is patched with a small `substituteInPlace` so that it fails closed. Each default can be overridden by setting the variable yourself.

| Variable | Packaged default | Why |
| --- | --- | --- |
| `IMPECCABLE_BIN` | the Nix-built engine | The launcher executes it before looking at `uname` or any download path, so a cache or `PATH` binary is never chosen. The `scripts/bin/<os>-<arch>/impeccable` sibling is kept as well. |
| `IMPECCABLE_PRO` | `off` | See Pro below. |
| `IMPECCABLE_LIVE_COPY_AGENT` | `chat` | See live Apply below. |
| `IMPECCABLE_NO_UPDATE_CHECK` | `1` | See Network above. An empty value re-enables the check. |

The skill build also fails if the engine's `engine-probe` output does not equal `impeccable-engine <scripts/VERSION>`.

### Things that run code or reach out that you should know about

Upstream paths are for version 0.1.22.

- **Pro dispatch after `login`.** A signed-in account can make scan verbs run a downloaded Pro binary (`crates/account/src/pro/mod.rs:766-812`). The dispatcher is skipped when `IMPECCABLE_BIN` is non-empty or `IMPECCABLE_PRO` is `0/off/false/no` (:768-776); this package sets both, so it never runs. Unsetting both opts in. `login` opens a browser (`crates/account/src/lib.rs:351-357`).
- **Live Apply spawns coding agents with approvals off.** The live server reads `IMPECCABLE_LIVE_COPY_AGENT` (`crates/live/src/live_server.rs:2494`). Modes `codex` and `claude` run `codex exec --dangerously-bypass-approvals-and-sandbox` or `claude --permission-mode bypassPermissions` with text taken from the page in the prompt (`crates/live/src/copy_edit_agent.rs:1273-1323`, `:1517-1553`). The packaged default `chat` hands the edit to the agent that is already in your session and runs nothing when no chat poller is attached (`:1290-1296`). To opt in to the spawning modes, export `IMPECCABLE_LIVE_COPY_AGENT=codex` (or `claude`); that means page content can steer an agent that has full file and shell access in the project, so only do it on pages you trust.
- **Repo-configured validation script.** After Apply the engine runs `scripts."impeccable:manual-edit-validate"` from the project's `package.json` through the shell (`copy_edit_agent.rs:77`, `:466-475`). Treat a repository that defines it as code you are about to run.
- **`update` and `install`.** `impeccable update`, `install`, `link` and `check` (`crates/cli/src/router.rs:61`, implemented in `crates/skills/`) download a non-Nix bundle and replace `<dir>/skills/impeccable`. Do not run them under Nix; update the flake input instead. The skill's own reference files tell the agent to run `npx impeccable update` or `install`; this package rewrites those two sentences (`reference/doctor.md:9`, `reference/hooks.md:55`) to point at the flake instead.
- **`health` uploads.** When you are signed in, a full scan uploads its counts to impeccable.style (`crates/account/src/health.rs:1-28`). Not signing in avoids it.
- **`generate-image`.** With `OPENAI_API_KEY` set it calls `api.openai.com` (`crates/context/src/generate_image.rs:386`, `crates/context/src/http.rs:320`).
- **Browsers.** `live` opens the default browser with `xdg-open` or `open` (`crates/live/src/browser_open.rs:8`, `:86`), and `live` and component review launch a Chrome-family browser (`crates/browser/src/lib.rs:110`). The package does not provide one.

## Updates

The skill and the engine come from the same `impeccable-src` input, so they move together:

```sh
nix flake update impeccable-src
nix flake check
```

The engine version is read from the upstream `Cargo.toml`. The skill build fails if `scripts/VERSION` does not match it, so a half-updated pair cannot ship.

## Checks

`nix flake check` builds both packages and runs:

- `launcher-offline`: runs the packaged launcher with an empty `PATH`, a fresh `HOME` and no network; `engine-probe` must report the pinned version (also with the sibling `bin/` removed), the `IMPECCABLE_BIN`/`PRO`/`LIVE_COPY_AGENT`/`NO_UPDATE_CHECK` defaults must be present, exported and overridable, `context` must run, and `HOME` must stay empty.
- `merge-hooks`: the settings merge keeps user keys and pre-existing empty groups, replaces old impeccable entries, is idempotent, refuses dangling and store symlinks, multi-document, non-object and non-array-event files, and creates files with mode 0600; the telemetry helper has the same guards and never overwrites a choice.
- `hm-module`: a Home Manager configuration with `enable` and `hooks.enable` evaluates and builds (hooks activation runs after `linkGeneration`); with `programs.claude-code` enabled the hooks land in its `settings.json` and no activation script is emitted; an unsafe `claudeConfigDir` is rejected.

Upstream's own Rust test suite is not run in the Nix build: it contains hundreds of integration test binaries, each linked with fat LTO, and part of it needs a browser or network.

## License

The packaging is Apache-2.0 (`LICENSE`). impeccable itself is Apache-2.0 by Paul Bakaus; third-party notices from upstream are reproduced in `NOTICE`.

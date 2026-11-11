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
| `claudeConfigDir` | `".claude"` | Claude Code config dir, relative to `$HOME`. The skill goes to `<dir>/skills/impeccable`. |
| `agents.enable` | `true` | Install the four agents into `<dir>/agents` (per-file links, so your own agents there are kept). |
| `hooks.enable` | `false` | Merge the impeccable hooks into `<dir>/settings.json` (see below). |
| `telemetry.enable` | `false` | When `false`, `"telemetry": false` is written to `~/.impeccable/config.json` if that file has no `telemetry` key. An existing value is never overwritten. |

### Hooks

`hooks.enable = true` runs an activation script that merges two entries into `<dir>/settings.json` with `jq`: `PostToolUse` (matcher `Edit|Write`, 5 s) and `Stop` (30 s). The command string has exactly the form the engine itself writes for a user-scope install (`[ ! -f '<launcher>' ] || '<launcher>' hook`), so the engine recognises the entries as its own and does not add duplicates. Other keys and other hooks in the file are kept; entries pointing at an impeccable launcher are replaced, so re-running activation is idempotent. A file that is not valid JSON is left untouched. The upstream plugin's `SessionStart` hook is not installed because the engine does not wire it for user-scope installs. Turning the option off later does not remove entries already written.

`settings.json` is intentionally not managed by `home.file`: Claude Code writes to it.

### Why the telemetry default is a config file

The engine honours `DO_NOT_TRACK` and `IMPECCABLE_NO_TELEMETRY`, but an environment variable only reaches it if Claude Code was started from a session that has it. `~/.impeccable/config.json` is read by the engine on every run, so it works for desktop launchers and hooks too.

## What the engine does on its own

Found by reading upstream `crates/` (version 0.1.22); verify against the version you use.

- **Network.** `context` checks for a newer skill version and writes `~/.impeccable/update-check.json`. This package disables that check by default (a tiny patch to the packaged launcher sets `IMPECCABLE_NO_UPDATE_CHECK=1` unless you set the variable yourself; set it to an empty string to re-enable). The verbs `concept-seed` and `serve-question` call `https://impeccable.style/api` (a roll and a choice ping); with telemetry off the roll still happens and the server records nothing.
- **`~/.impeccable/`.** Besides the config and update cache above, the engine keeps a hook claim file there, a seed salt, and (via `IMPECCABLE_AGENTS_HOME`) agent data. `engine-probe` and the launcher itself write nothing there.
- **Project directory.** State lives in `<project>/.impeccable/` (config, seed ledger, hook cache, build state, mocks).
- **`settings.json`.** The engine's own hook wiring (`hooks on`) rewrites the user's `<dir>/settings.json` (atomically, keeping other keys). That file is not owned by Nix, so this is compatible with the module.

## Updates

The skill and the engine come from the same `impeccable-src` input, so they move together:

```sh
nix flake update impeccable-src
nix flake check
```

The engine version is read from the upstream `Cargo.toml`. The skill build fails if `scripts/VERSION` does not match it, so a half-updated pair cannot ship.

## Checks

`nix flake check` builds both packages and runs:

- `launcher-offline`: runs the packaged launcher with an empty `PATH`, a fresh `HOME` and no network; `engine-probe` must report the pinned version, `context` must run, and `HOME` must stay empty.
- `merge-hooks`: the settings merge keeps user keys, replaces old impeccable entries and is idempotent; the telemetry file helper never overwrites a choice.
- `hm-module`: a minimal Home Manager configuration with `enable` and `hooks.enable` evaluates and builds.

Upstream's own Rust test suite is not run in the Nix build: it contains hundreds of integration test binaries, each linked with fat LTO, and part of it needs a browser or network.

## License

The packaging is Apache-2.0 (`LICENSE`). impeccable itself is Apache-2.0 by Paul Bakaus; third-party notices from upstream are reproduced in `NOTICE`.

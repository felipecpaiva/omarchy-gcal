# Omarchy plugin convention — read this before starting a new plugin repo

Omarchy has a built-in installer for third-party plugins:

```bash
omarchy plugin add https://github.com/<you>/<repo>.git --enable --yes
```

It works on **any git repo that follows a fixed shape**. Match the shape and
your plugin is a one-line install for anyone; miss it and people are stuck
cloning by hand. This repo (`omarchy-gcal`) follows it — use it as the
reference layout for the next one.

## The one hard rule

**`manifest.json` must sit at the repo root.** Not in a `plugin/` or `src/`
subfolder — the root. `omarchy plugin add` clones the whole repo straight
into `~/.config/omarchy/plugins/<id>/` and the shell looks for
`manifest.json` right there. A manifest one directory deep is invisible to
it, full stop — this was the actual bug in this repo until 2026-08-31: the
QML and manifest lived under `plugin/`, so `omarchy plugin add` would have
cloned a repo the shell couldn't discover.

`entryPoints` inside the manifest are relative to wherever the manifest
lives, so once the manifest is at root, the QML files it points at need to
be at root too (or in a subfolder named in the entry path — but simplest is
flat).

## What can and can't live at that root

Anything the shell loads directly — QML, JS, the manifest — goes at the
root. Everything else (docs, a Python backend, systemd units, install
scripts) can live alongside it in its own folder; the shell only cares
about `manifest.json` and whatever `entryPoints` names. This repo's `sync/`
and `docs/` are proof that extra top-level folders don't break discovery.

## What the installer will and won't do for you

`omarchy plugin add` only ever clones files, validates the manifest, and
flips the enabled bit over shell IPC. **It never runs any code from the
plugin** — no install hooks, no scripts, no sudo. That's a deliberate
security boundary (plugins are unsandboxed code inside `omarchy-shell`),
not a gap to work around.

So if your plugin needs anything beyond "the shell loads some QML" —
a backend service, a first-run wizard, a systemd timer, an external account
link — that setup has to be a **separate script the user runs once**,
documented in your README, e.g. this repo's `install.sh`. Design for two
install paths from day one:

1. `omarchy plugin add <url>` — gets the QML plugin cloned and validatable,
   but leaves any non-QML backend unconfigured.
2. Your own `install.sh` — does the full job: backend setup, systemd units,
   calendar/account linking, bar swap, *and* clones the plugin the same way
   `omarchy plugin add` would (see this repo's `install.sh` step 4).

Document which one to actually run in the README's Quickstart. If the
plugin is self-contained (no backend), path 1 alone is enough and you can
skip shipping an `install.sh` entirely.

## Before shipping: validate

```bash
omarchy plugin validate <path-to-plugin-dir>
```

Run this against the directory as it would actually be cloned (repo root)
before every release. It's the same check `omarchy plugin add` runs on
install — catching a manifest problem here beats a user hitting it.

## Checklist for a new plugin repo

- [ ] `manifest.json` at the repo root, `id` unique and namespaced
      (`yourname.thingname`, not something that could collide with a
      first-party `omarchy.*` id)
- [ ] Every file `entryPoints` names actually exists at the path the
      manifest implies
- [ ] `omarchy plugin validate .` passes
- [ ] Anything beyond "load QML" (backend, service, account setup) has its
      own script, documented separately from the one-line `plugin add` path
- [ ] README's Quickstart says explicitly which install path to use

# Prerequisites

This widget adds nothing new to your system beyond what GNOME Calendar
already needs. If you've ever used GNOME Calendar on this machine, you
likely have all of this already and `install.sh` will install nothing.

| Package (Arch) | Why |
|---|---|
| `evolution-data-server` | the calendar sync engine (EDS) — same one GNOME Calendar uses |
| `gnome-online-accounts` | the Google login/account-linking service (GOA) |
| `gnome-control-center` | provides the "Online Accounts" settings panel used to link a Google account |
| `python-gobject` | PyGObject bindings — lets the sync script call EDS directly |

Check what you already have:

```bash
pacman -Q evolution-data-server gnome-online-accounts gnome-control-center python-gobject
```

`install.sh` runs this same check and only installs what's missing.

## The system Python, not a version-manager shim

`python-gobject` is installed against `/usr/bin/python3` (the system
Python). If you use `pyenv`, `mise`, or `asdf`, the `python3` on your
`PATH` is very likely a different interpreter that does **not** have the
`gi` module — everything in this repo calls `/usr/bin/python3` explicitly
for that reason. If you're scripting around this yourself, do the same.

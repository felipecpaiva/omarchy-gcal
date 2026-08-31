#!/usr/bin/env bash
# Installs the Google Calendar clock as a replacement for Omarchy's stock
# clock widget. See README.md for what this does and why; see
# docs/prerequisites.md for the package table this step 1 checks.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="google-calendar.clock"
PLUGIN_DEST="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
SYNC_DEST="$HOME/.local/share/omarchy-google-calendar"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
SYSTEM_PYTHON="/usr/bin/python3"

echo "== 1/6: checking prerequisites =="
PREREQ_PKGS=(evolution-data-server gnome-online-accounts gnome-control-center python-gobject)
if omarchy pkg missing "${PREREQ_PKGS[@]}"; then
  echo "Installing missing packages: ${PREREQ_PKGS[*]}"
  omarchy pkg add "${PREREQ_PKGS[@]}"
else
  echo "All prerequisite packages already installed — nothing to do."
fi

if [[ ! -x "$SYSTEM_PYTHON" ]]; then
  echo "error: $SYSTEM_PYTHON not found. This script needs the system Python" >&2
  echo "(the one gnome-online-accounts/python-gobject are installed against)," >&2
  echo "not a pyenv/mise/asdf shim." >&2
  exit 1
fi

echo
echo "== 2/6: checking for a linked Google account =="
mkdir -p "$SYNC_DEST"
cp -f "$REPO_DIR/sync/eds_read.py" "$SYNC_DEST/eds_read.py"
ACCOUNTS_TMP="$(mktemp)"
trap 'rm -f "$ACCOUNTS_TMP"' EXIT
if ! "$SYSTEM_PYTHON" "$SYNC_DEST/eds_read.py" --check-accounts >"$ACCOUNTS_TMP" 2>&1; then
  echo "No Google account linked yet."
  echo "Opening Settings > Online Accounts — add your Google account there,"
  echo "then run this script again."
  gnome-control-center online-accounts >/dev/null 2>&1 &
  exit 1
fi
echo "Linked account(s):"
cat "$ACCOUNTS_TMP"

echo
echo "== 3/6: choose which calendars show on the bar =="
echo "Most Google accounts carry dozens of calendars (holidays, shared"
echo "bookings, read-only feeds) — pick just the ones you actually want."
"$SYSTEM_PYTHON" "$SYNC_DEST/eds_read.py" --select-calendars

echo
echo "== 4/6: installing the plugin =="
rm -rf "$PLUGIN_DEST"
mkdir -p "$PLUGIN_DEST"
cp -f "$REPO_DIR"/plugin/*.qml "$REPO_DIR"/plugin/*.js "$REPO_DIR/plugin/manifest.json" "$PLUGIN_DEST/"
omarchy plugin validate "$PLUGIN_DEST"

echo
echo "== 5/6: installing the sync timer =="
mkdir -p "$SYSTEMD_USER_DIR"
cp -f "$REPO_DIR/sync/omarchy-google-calendar-sync.service" "$SYSTEMD_USER_DIR/"
cp -f "$REPO_DIR/sync/omarchy-google-calendar-sync.timer" "$SYSTEMD_USER_DIR/"
systemctl --user daemon-reload
systemctl --user enable --now omarchy-google-calendar-sync.timer
# First sync runs now rather than waiting for the timer's first tick, so
# the agenda has real data the first time the bar is opened.
systemctl --user start omarchy-google-calendar-sync.service || true

echo
echo "== 6/6: swapping the bar widget =="
omarchy plugin disable omarchy.clock || true
omarchy plugin enable "$PLUGIN_ID"
# 'plugin enable/disable' only touch the widget layout — the bar's own
# centerAnchor setting (which widget sits pinned dead-center) is a
# separate shell.json key that still points at the disabled stock clock
# otherwise, discovered by actually opening the bar after install.
SHELL_JSON="$HOME/.config/omarchy/shell.json"
if [[ -f "$SHELL_JSON" ]]; then
  "$SYSTEM_PYTHON" -c "
import json
path = '$SHELL_JSON'
with open(path) as f:
    data = json.load(f)
if data.get('bar', {}).get('centerAnchor') == 'omarchy.clock':
    data['bar']['centerAnchor'] = '$PLUGIN_ID'
    with open(path, 'w') as f:
        json.dump(data, f, indent=2)
"
fi

echo
echo "Done. The bar now shows the Google Calendar clock instead of the stock one."
echo "Change which calendars are shown any time with:"
echo "  $SYSTEM_PYTHON $SYNC_DEST/eds_read.py --select-calendars"
echo "Uninstall with: $REPO_DIR/uninstall.sh"

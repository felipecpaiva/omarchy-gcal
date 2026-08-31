#!/usr/bin/env bash
# Reverses install.sh. Safe to run even if install.sh only partially
# completed — every step below is a no-op when there's nothing to undo.
set -uo pipefail

PLUGIN_ID="google-calendar.clock"
PLUGIN_DEST="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
SYNC_DEST="$HOME/.local/share/omarchy-google-calendar"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"

echo "== 1/4: swapping the bar widget back =="
omarchy plugin disable "$PLUGIN_ID" 2>/dev/null || true
omarchy plugin enable omarchy.clock 2>/dev/null || true

echo "== 2/4: stopping and removing the sync timer =="
systemctl --user disable --now omarchy-google-calendar-sync.timer 2>/dev/null || true
systemctl --user stop omarchy-google-calendar-sync.service 2>/dev/null || true
rm -f "$SYSTEMD_USER_DIR/omarchy-google-calendar-sync.service" "$SYSTEMD_USER_DIR/omarchy-google-calendar-sync.timer"
systemctl --user daemon-reload 2>/dev/null || true

echo "== 3/4: removing the plugin =="
rm -rf "$PLUGIN_DEST"

echo "== 4/4: removing the sync script and cache =="
rm -rf "$SYNC_DEST"
rm -rf "$HOME/.cache/omarchy-google-calendar"

echo
echo "Done. The stock clock is back. Your calendar selection at"
echo "~/.config/omarchy-google-calendar/calendars.json was left in place"
echo "in case you reinstall later — delete it yourself if you don't want that."

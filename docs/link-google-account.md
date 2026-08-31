# Linking a Google account

This widget never asks for your Google password, and never registers its
own app access to your account. It reads events through the same login
GNOME Calendar already uses.

**If GNOME Calendar already shows your events on this machine, you're
done — skip this whole page.** `install.sh` detects the existing account
automatically.

## If you've never linked a Google account here

1. Open Settings → Online Accounts (or run `gnome-control-center
   online-accounts`).
2. Click "Add Account" → Google.
3. Log in and approve the standard Google/GNOME permission screen — this
   is Google's own long-standing, already-approved GNOME client, the same
   one Evolution, GNOME Calendar, and GNOME To Do all use.
4. Make sure the "Calendar" toggle is on for the account (it's on by
   default).

That's it. Run (or re-run) `install.sh` — it picks up the new account and
walks you into picking which calendars to show.

## Multiple accounts

Repeat the steps above once per Google account. `install.sh`'s calendar
picker lists calendars from every linked account together, grouped by
account, so you only need to run it once at the end.

# Security Policy

## Reporting a vulnerability

Please report security issues privately through GitHub's private vulnerability
reporting: the repository's **Security** tab → **Report a vulnerability**. Do not
open a public issue for a security problem.

You will get an acknowledgement within a few days. The disclosure window is
**90 days** from the report unless a longer extension is agreed in the thread —
after a fix ships, or the window closes, the report may be disclosed publicly.

There is no paid maintainer and no bug bounty. Reports are handled on a
best-effort basis by one person.

## What is in scope

- The JuiceScreen app itself (capture, recording, annotation, library, OCR,
  auto-update).
- The release and update chain: the signed/notarized DMG, and the Sparkle
  EdDSA update feed (`appcast.xml`).

## What is out of scope

- Physical or same-user attacks. Anything running as your macOS user can read
  the capture files in your save folder and the SQLite library — JuiceScreen's
  boundary is the process, not filesystem ACLs. This is documented in the
  README's Privacy section, not a vulnerability.
- Backup tools (Time Machine, iCloud, Backblaze, …) picking up the save folder
  or library. JuiceScreen does not transmit; your backup tool's behaviour is
  yours to configure.

## Update integrity

Every released DMG is signed with an EdDSA key whose public half is embedded in
the app's `Info.plist` (`SUPublicEDKey`). Sparkle refuses any update whose
signature does not verify against that key. If the key in a running app ever
differs from the one in the README for the same release, do not accept the
update — report it.

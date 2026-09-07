# Security policy

## Supported versions

Only the latest release is supported. The app updates itself (Windows,
Android, Linux) — see releases.

## Reporting a vulnerability

Use **Report a vulnerability** under the repository's *Security* tab. That
opens a private thread; please do not open a public issue or paste findings
into the discussions.

## What counts, and what does not

This app records audio and transcribes speech. The privacy posture is part of
the design, so treat these as vulnerabilities:

- Anything that uploads audio, transcript, or brief on the default path.
- Anything that sends data anywhere without the settings screen naming it
  first.
- The API key leaving the device (it is stored in app settings, not a platform
  keychain — that is a known, documented limitation, not a reportable flaw).
- Model downloads accepted without integrity checks, or writes into the
  documents folder that could smuggle a native library in front of llama.cpp.

Out of scope: the unsigned Windows installer and the Flutter/llama.cpp
dependencies themselves — report those upstream, but note how they touch this
app if you can.

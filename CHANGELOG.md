# Changelog

Notable changes. Versions follow `pubspec.yaml`; releases are tagged
`v<version>` and built by the publish workflow. Changes not shipped in a
release live under Unreleased.

## Unreleased

## 1.0.2 (2026-10)

- **A killed recording no longer loses the lecture.** The audio was on disk
  behind a stale length field that made the recognizer read the whole file as
  silence; the header is now read from the file. A lecture interrupted by a
  crash comes back marked as interrupted, with its captions, at the next
  launch.
- Session store rewritten: one manifest row per lecture instead of a single
  index holding every lecture's text, captions appended to their own file,
  writes through a temp file and a rename. The list no longer re-decodes a
  growing index several times a minute *while recording*. Existing installs
  migrate on first run and keep the old index as `index.legacy.json`.
- Brief progress is shown and the brief can be cancelled.
- Windows builds bundle the Visual C++ runtime again. 1.0.1 shipped without
  it, so the app stopped at launch with a missing `VCRUNTIME140.dll` (#3).
- Releases attach the per-ABI Android APKs again. Only the 201 MB universal
  file was published, so emulator and old-phone testers had no small download
  to install (#1).
- Warn when the microphone hears nothing for five seconds. The warning stays
  until sound returns rather than clearing on a timer, because a warning that
  leaves on its own is one you learn to ignore.
- New model tiers: kb-whisper-large and Qwen 3.5 (2B / 4B). On prov
  extraction the 4B beats the 7B it replaces, 9/9 runs against 0/4.
  **kb-whisper-large has not been timed on real speech** — see
  `docs/OPEN-QUESTIONS.md`.

## 1.0.1 (2026-09)

- Self-updater: release feed, settings card, and per-platform installers.
- Publish workflow that builds Windows, Android, and Linux from a `v*` tag.

## 1.0.0

- First beta build: record a lecture, transcribe locally (KB-Whisper, live
  captions from Silero VAD), and draft a three-part brief with a local LLM.
- Optional EU cloud (Berget AI preset) for transcription and brief, each its
  own opt-in.
- Installers for Windows (Inno), Android (signed per-ABI APKs), and Linux
  (`.deb` with CPU-only llama.cpp).

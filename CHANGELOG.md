# Changelog

Notable changes. Versions follow `pubspec.yaml`; releases are tagged
`v<version>` and built by the publish workflow. Changes not shipped in a
release live under Unreleased.

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

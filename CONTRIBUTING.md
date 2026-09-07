# Contributing

Tack — thanks for wanting to help. This is a small but opinionated project:
everything about privacy defaults, model tiers, and what the app says to the
teacher is deliberate. Read this before opening a PR.

## Read first

- [README.md](README.md) — what the app is.
- [AGENTS.md](AGENTS.md) — the developer manual. Build commands, platform
  quirks, packaging, and the reasoning behind the model/prompt design. If
  something surprises you at build time, the answer is probably in there.
- [PRODUCT.md](PRODUCT.md) — product spec and principles.
- [docs/INSTALL.md](docs/INSTALL.md) — what testers get, so you know what
  ships.

## Setup

```text
flutter pub get
flutter test
flutter run -d windows   # or -d linux
```

Notes that save time:

- On Windows the `llm_llamacpp` hook needs `unzip.exe` — add
  `C:\Program Files\Git\usr\bin` to `PATH`. Turn on **Developer Mode** so
  plugin symlinks work.
- On Linux you need `clang cmake ninja-build pkg-config libgtk-3-dev unzip
  pulseaudio-utils` (see AGENTS.md "Run (Linux)").
- Models download on first use into the app documents folder — hundreds of MB,
  up to ~4.7 GB. Never commit weights.

## Testing

- `flutter test` covers the unit/widget tests and runs fast.
- `flutter test test/preview/screens_preview.dart` renders every screen to
  `build/preview/*.png` — use it when touching UI.
- The brief quality probe (`test/brief_probe_test.dart`) needs local models on
  disk and is off by default; run it only when changing prompts, models, or
  brief pipeline code. It scores runs into `feedback/quality/SCORES.md`.

## Ground rules

1. **Privacy is the product.** Default path never uploads audio or transcript.
   Never construct a `CloudConfig` to "check" something; it exists only after
   the teacher opts in, per job. Do not describe `SharedPreferences` as secure
   storage.
2. **Transcription and brief are separate opt-ins.** Keep settings copy naming
   exactly what leaves the device.
3. **Prompt/model changes need evidence.** Tune against the corpus in
   `feedback/golden/`, not one transcript. Manual picks always win over the
   auto device pick — do not add code that second-guesses them.
4. **Swedish UI copy.** Short, factual, no hype, no invented facts.
5. **No comments unless the code truly needs them**; the repo style is terse.

## Commits and PRs

- Short imperative subject lines ("Fix android collect: ...").
- Keep PRs small; if UI changed, attach a `build/preview/*.png` render.
- Run `flutter test` before pushing. Link the issue if there is one — bug
  reports use the repo's issue templates.

## Licensing

The project is under the PolyForm Strict license (see LICENSE). Contributing
means your work is offered under that license.

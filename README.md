# Föreläsning (lecture_local)

Record a lecture on iOS, Android, macOS, Windows, or Linux. Swedish speech is transcribed **on the device** (KB-Whisper). A local LLM drafts a brief the teacher can paste into the school platform:

- Vad som togs upp
- Datum, prov och uppgifter
- För frånvarande och vårdnadshavare

Audio and transcript stay on the device by default.

Settings can point transcription, the brief, or both at an EU provider with an OpenAI-compatible API — [Berget AI](https://berget.ai) (Sweden) is the preset, and any other endpoint works by editing the URL and model names. Each is a separate opt-in: cloud speech uploads the audio, a cloud brief uploads the transcript. Cloud speech runs after the lecture on the finished recording, so there are no live captions in that mode.

## Install (beta testers)

Prebuilt installers for Windows, Linux and Android are built by
`tool/package/` into `dist/`. What to send a tester, and what to tell them, is
in [docs/INSTALL.md](docs/INSTALL.md). Building them is described under
Packaging in [AGENTS.md](AGENTS.md).

## Run

Install [Flutter](https://docs.flutter.dev/get-started/install) (this machine used `D:\sdk\flutter`). On Windows, turn on **Developer Mode** so plugin symlinks work.

```text
flutter pub get
flutter test
flutter run -d windows
```

On Linux, `flutter run -d linux` instead — see [AGENTS.md](AGENTS.md) for the
packages it needs.

Models download on first use into the app documents folder (hundreds of MB to ~4.7 GB for the 7B brief model). See [AGENTS.md](AGENTS.md).

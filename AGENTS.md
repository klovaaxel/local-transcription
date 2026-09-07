# Lecture local (Föreläsning)

Flutter app for iOS, Android, macOS, Windows, and Linux. A teacher records a lecture, transcribes Swedish **on device**, and turns the transcript into a copy-ready brief for the school platform. Audio and transcript stay local unless the teacher opts into an EU cloud provider in settings.

## Stack

- Flutter (Material 3), `record` (16 kHz WAV / PCM), `sherpa_onnx` + **KB-Whisper** (Swedish), Silero VAD for live captions, `llm_llamacpp` for the local brief.
- Models are **downloaded on first use** into the app documents directory. Never commit weights.
- Optional cloud: any OpenAI-compatible endpoint over `package:http`. Berget AI (Sweden, EU-hosted) is the preset — `https://api.berget.ai/v1`, `KBLab/kb-whisper-large` for speech, an editable chat model for the brief. No provider SDK; there is nothing to add to `pubspec.yaml`.

## Models

| Role | Default | Source |
|------|---------|--------|
| ASR small | kb-whisper-small INT8 (~376 MB) | `frictional123/sherpa-onnx-kb-whisper-int8` |
| ASR medium | kb-whisper-medium INT8 (~947 MB) | same repo |
| VAD | `silero_vad.onnx` | sherpa-onnx GitHub releases `asr-models` |
| Local LLM small | Qwen2.5-1.5B-Instruct Q4_K_M (~1.1 GB) | Hugging Face GGUF |
| Local LLM medium | Qwen2.5-3B-Instruct Q4_K_M (~2.0 GB) | Hugging Face GGUF |
| Local LLM large | Qwen2.5-7B-Instruct Q4_K_M (~4.7 GB, two GGUF shards) | Hugging Face GGUF |

Whisper `language=sv`, `task=transcribe`. The speech model is picked per device like the brief model (`autoAsr` in `lib/data/app_settings.dart`, on by default): kb-whisper-medium on desktops with ≥4 cores (better Swedish, ~2.5x compute, runs after the lecture with progress shown), small on phones (CPU only, unverified — before switching phones to medium, measure transcription wall time on a real device). Both auto picks are grounded in two measurements, in order of when they can run: (1) a pure-Dart sha256 launch benchmark (`lib/perf/device_bench.dart`, once per app version, ~112 MB/s on a known-good desktop) gates the pre-download pick below `cpuWeakMbs` (40); (2) a **decode probe** (`lib/perf/llm_speed_probe.dart`, 64-token fixed completion timed from the FIRST token — model load and prefill are excluded, they dragged early numbers to 3-5 tok/s — once per tier+app version, right after the model downloads) measures real decode tokens/s *including the GPU* and steps the auto tier down under `llmSlowTokPerSec` (4 tok/s; measured reference desktop: 7B ≈ 21 tok/s, 3B ≈ 41 tok/s under Vulkan). On phones the probe ALSO runs CPU-vs-GPU both ways and keeps the winner (`AppSettings.llmGpuOffload`) — a phone GPU can genuinely lose to its own CPU. Caps (`llmCap`/`asrCap`) are cleared on every new benchmark cycle, so one slow run cannot demote a device forever; the real-work calibration re-demotes if justified. (3) real-work calibration (`applyAsrCalibration` wall/audio > 8x, `applyLlmCalibration` > 100 ms/kchar) refines after actual use. Backends are enumerated via `BackendDetector` and shown in settings. Manual picks always win — never second-guessed. Long audio is windowed (~20 s, 5 s overlap) and merged in `lib/asr/transcript_merge.dart`. Live captions: VAD `commit`s, the rolling 20 s window is `partial`; merge must drop restated windows after a pause (not suffix-prefix only).

Local brief: temperature 0.2 via `streamChatWithGenerationOptions` (`chatResponse` does not apply sampling). The brief's sections are **dynamic data** (`lib/summarize/brief_sections.dart`): a catalog of heading+one-instruction-line blocks the teacher toggles in settings; system prompt, reduce prompt, parser, JSON store and session screen are composed from the same list. The overview section is locked (it names the lecture). The few-shot pair from `lib/summarize/newsletter.dart` is **off by default**: the A/B in `feedback/quality/` showed it turns the 7B into keyword soup and the 1.5B copies the example line ("Ta med linjal") into real output. Quality findings from that same A/B (all in `feedback/quality/`): the 7B at **14k context** fits a typical 45-min transcript in ONE chunk (2x faster, no merge loss — hence `llmLarge.contextSize = 14336`). A **regex key-line hint pre-pass is on by default** (`keyLineHints` in `lib/summarize/newsletter.dart` — verbatim transcript lines mentioning prov/läxa/uppgift/datum/"ta med" prepended to the map prompt; the models used to read past a prov mentioned only in passing at the start of a noisy transcript, hints fix that at zero cost). Heavier denoise passes exist behind flags and stay OFF: `useKeyLines` numbered-line selection (model picks line numbers, Dart reassembles verbatim — prov surfaced only in some runs, ~2x time) and `useVerifyPass` self-edit (2x time, no measured gain). The data-driven **retry passes are ON by default** (`useRetryPass`): a map retry fires only when the hint lines prove the draft missed them (empty schedule though hints name prov, empty overview) and a reduce retry fires when a merge LOSES content a map part had (dumps showed the 3B merge dropping the prov; the retry restored it). Later passes may only improve, never replace a better draft (`_better` gate). A point-list overview instruction scored better on the 7B but broke the 3B (keyword bullets, prov vanished) — section instructions are shared across models, word them for the small one; the one exception is **per-tier schedule wording** (`BriefSectionCatalog.resolveFor`): the large tier spells out prov details (antal frågor, tid) and scored 16/16 planted facts on the harness corpus, the small tiers keep the simple instruction. The quality harness scores against a **corpus** (`feedback/golden/` synthetic lectures + the field transcript, with planted facts) — never tune prompts against kfn alone. Greedy (temp 0) scored worse than temp 0.2 on the 3B. The parser strips a leftover placeholder line from sections that also carry content. Model-extraction and hint wordings swing these small models wildly between runs — the probe (`test/brief_probe_test.dart`, `LLM_PROBE=1`, `LLM_PROBE_RUNS=N` seeded repeats, models in `C:\Temp\llm-models`) scores prov-detection, empty sections, loops and leaks per run into `feedback/quality/SCORES.md`; recheck there before changing prompt text or models. The 3B tier (`ModelCatalog.llmMedium`) won the phone A/B: Qwen prompt-following without the 1.5B's keyword soup, and beat Llama-3.2-3B (which echoed the hint instruction and missed the prov once) — check Llama's license (Llama 3.2 community license) before shipping it. The auto model pick (`autoLlmForDevice` in `lib/data/app_settings.dart`) is desktop 7B / phones 3B; the 1.5B stays a fallback (`small`). `gpuLayersFor` offloads ALL sizes on iOS (Metal) — untested on real hardware, verify before relying on it — and keeps Android on CPU. The plugin submits the whole rendered prompt as ONE `llama_decode` batch, so the repository must be built with `batchSize: spec.contextSize` — with the plugin default (`batchSize: 512`, i.e. `n_batch`) any real lecture prompt trips llama.cpp's `GGML_ASSERT(n_tokens_all <= n_batch)` inside `llama_context::decode`, which calls `ggml_abort` and kills the whole process (seen in the field, `feedback/crash_log.txt`). The 7B option offloads GPU layers; 1.5B stays CPU on phones. Official 7B Q4_K_M is two GGUF shards; download both and pass the `00001-of-00002` path to llama.cpp. A lecture longer than the model window is split into overlapping chunks, each mapped to a partial brief, then reduced (`lib/summarize/newsletter.dart`); do not drop the middle with head+tail compact. Chunk char budget assumes at worst ~2.2 chars/token for fragmented whisper Swedish and reserves room from the actual prompt length — keep the reserve in `llmChunkCharBudget` generous, an over-full chunk now fails decode (KV cache full, a Dart error) instead of crashing.

WAV close must patch the 44-byte header with `FileMode.append` (not `FileMode.write`, which truncates PCM). The header builder and RIFF parser live in `lib/asr/wav_format.dart` — `WavFileSink` writes with it, `WavChunker` reads with it. Stop the ASR isolate only after native `free()` and a `disposed` ack.

Cloud path (opt-in, off by default): `lib/cloud/openai_compatible.dart` is the only place that talks to a provider — `chat/completions`, `audio/transcriptions`, `models`. Map/reduce over a long lecture is shared by both backends in `lib/summarize/brief_pipeline.dart`; local and cloud only implement `complete(turns)`. A 45-minute lecture is ~86 MB of 16 kHz WAV, past what a Whisper endpoint takes, so `WavChunker` cuts 10-minute parts with 5 s overlap and `mergeOverlappingTranscript` joins them. Cloud transcription means **no live captions** — nothing is streamed; the finished file is uploaded after the lecture, and `AppSettings.liveCaptionsEnabled` is what the record screen and `_onPcm` read. Errors reach the teacher as Swedish `CloudException` text via the existing toast.

## Layout

- `lib/ui` — soft-UI design system. Tokens in `soft_theme.dart` (`SoftPalette` theme extension, `SoftShape`, `SoftSpace`, `SoftMotion`, `lectureTheme`); depth primitive in `soft_surface.dart` (`SoftSurface` raised/flat/inset, `SoftField`); shell and content in `soft_widgets.dart` (`SoftPage`, `SoftCard`, `SoftSection`, `BriefBlock`, `HearingMeter`, `softBodyPadding`); one button in `soft_buttons.dart` (`SoftButton.primary|quiet|danger`, plus `SoftIconButton`, the `SoftBackButton` preset and the `SoftActionBar` layout); Lucide icons in `soft_icons.dart`; `SoftToast` overlay for slow work and notices (floats above the action bar — never a top banner). Locked direction contract: `.impeccable/briefs/app-shell.md`.
  - Depth is the grammar for page surfaces: **raised** = press it, **flat** = read it, **inset** = put something in it. `SoftDepth.floating` is not a fourth page state — it is the transient overlay above the page (the toast only), and casts a real shadow instead of carrying a lit edge.
  - Read colours with `SoftPalette.of(context)`; never hardcode one. Accent is a fill only — as text it misses 4.5:1 on the base.
  - Every screen is a `SoftPage`; every scrollable body uses `softBodyPadding` (its top gap keeps the first card's highlight from being clipped by the scrollable).
  - `SoftActionBar` is for a screen whose whole job is one action — record, stop. A screen with peer actions puts them inline instead, at the point in the page where you have finished reading (Kopiera and Dela sit in one row; Kopiera carries the accent). Ta bort never beside Kopiera.
  - The app speaks up in exactly one place: `SoftToast`. Confirmations go through `LectureAppState.notice` and clear themselves after four seconds; a failure sets `statusIsError` and waits to be dismissed. No `SnackBar` — the theme deliberately does not style one.
  - `SoftIconButton` drops its tooltip when there is no `Overlay` — that is what lets it work inside the toast, which is mounted beside the Navigator.
- `lib/features/home` — lecture list; primary action is record
- `lib/features/record` — open this screen first, then start recording; HearingMeter from live PCM; primary action is stop
- `lib/features/sessions` — after-class brief (copy to LMS). The lecture's name is derived from the brief (`NewsletterSummary.autoTitle`), never typed. The transcript is read only — a check on the brief; `Transkribera om` is the only thing that changes it. Leading chrome is Tillbaka; Ta bort lives in the brief footer after Dela, never in the back slot and never beside Kopiera.
- `lib/features/settings` — transcription (device / cloud) + ASR size, brief (local 1.5B / 7B / cloud), the provider card (preset, API URL, key, model names, Testa anslutning), delete-audio toggle. The provider card only exists while something is set to cloud, and its subtitle names exactly what leaves the device.
- `lib/asr` — isolate + sherpa, WAV format/chunking, cloud transcriber
- `lib/cloud` — the one OpenAI-compatible HTTP client
- `lib/summarize` — brief prompt, shared map/reduce pipeline, local llama.cpp, cloud provider
- `lib/data` — JSON session store under app support

`flutter test test/preview/screens_preview.dart` renders every screen, light and dark, to `build/preview/*.png` — a look at the UI without launching the app. It is skipped by a plain `flutter test`. Icon glyphs come out as empty boxes there; the test renderer has no icon font.

UI: never assign `TextEditingController.text` during `build`. Visual work is Flutter-native: lock a composition, then code — skip web spec/plates/hero gates.

## Privacy

Default path never uploads audio or transcript, and `AppSettings()` defaults to local for both. A `CloudConfig` is only ever built after the teacher picks cloud in settings — keep it that way; do not construct one to "check" anything.

Transcription and the brief are **separate** opt-ins: cloud speech uploads audio, cloud brief uploads the transcript. Settings must keep saying which. The API key lives in `SharedPreferences` like the other settings — it is not in a platform keychain, so do not describe it as secure storage.

## Run (Windows)

Flutter SDK used to bootstrap this repo: `D:\sdk\flutter`. Put `D:\sdk\flutter\bin` on `PATH`. On Windows the `llm_llamacpp` hook runs `unzip.exe`. Git for Windows provides it at `C:\Program Files\Git\usr\bin`. Add that directory (and `D:\sdk\flutter\bin`) to `PATH` before `flutter test` / `flutter run`. This repo also has `tool/unzip.cmd` if you need a `tar`-based fallback named `unzip`.

```text
flutter pub get
flutter test
flutter run -d windows
```

On Windows, also turn on **Developer Mode** so Flutter plugin symlinks work.

## Run (Linux)

Adding a platform is `flutter create --platforms=<os> --org se.axelkarlsson
--project-name lecture_local .` — but it rewrites `.metadata` and keeps only the
platform you just asked for, dropping the other `migration.platforms` entries.
Put them back by hand afterwards.

x86_64 only. `sherpa_onnx_linux` ships prebuilt `.so` for x64 and aarch64, but the
`llm_llamacpp` prebuilt for the local brief is x64 — an arm64 desktop gets speech
and no local brief.

Desktop toolchain plus what the plugins shell out to:

```text
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev unzip pulseaudio-utils
flutter pub get
flutter test
flutter run -d linux
```

`unzip` is what the `llm_llamacpp` hook uses to unpack the llama.cpp release
(same requirement as Windows, usually already present). `pulseaudio-utils` is
for `parecord`, which is how `record_linux` captures PCM — a PipeWire desktop
gets it from `pipewire-pulse`. Without it recording fails with a Swedish notice
from `_startPcmStream` in `lib/app_state.dart`, not a raw ProcessException.

Two things behave differently here and are handled, not fixed:

- **No share sheet.** `share_plus` on Linux opens a `mailto:` link, and throws
  when no mail handler is set. `_shareBrief` in `lib/features/sessions/session_page.dart`
  catches that and points the teacher at Kopiera. File sharing is unimplemented
  on Linux upstream; the brief is shared as text, so that path is not used.
- **GPU offload.** `gpuLayersFor` already includes Linux, and the prebuilt
  llama.cpp carries CUDA/Vulkan. A machine with neither falls back to CPU, where
  the 7B brief is slow — pick 1.5B in settings.

## Packaging (beta builds)

`tool/package/` builds what testers install. Everything lands in `dist/`,
which is gitignored. Version comes from `pubspec.yaml` (`1.0.0+1` -> `1.0.0`,
build number kept for the Debian revision and the Android versionCode).

```text
pwsh -File tool/package/build_windows.ps1     # setup.exe + portable zip
pwsh -File tool/package/build_android.ps1     # signed APK per ABI
wsl -d Ubuntu -- bash tool/package/build_linux_deb.sh   # .deb
```

**Signing.** Android release builds read `android/key.properties`, which points
at a keystore kept outside the repo (`~/.keystores/`). Neither is committed. With
the file absent the release build falls back to the debug key, so the project
still builds for someone without the beta key -- but a debug-signed install can
never be upgraded by a properly signed one, so never hand that build out. The
Windows installer is unsigned; SmartScreen warns until a code-signing
certificate exists, and `docs/INSTALL.md` walks testers through it.

**Gradle cannot start on this machine with the default temp dir.** The daemon
reaches its client over an AF_UNIX socket in the JVM temp dir, and `connect()`
inside `%LOCALAPPDATA%\Temp` fails here with `Invalid argument` -- endpoint
protection, not Gradle. It surfaces as `java.io.IOException: Unable to establish
loopback connection`. Any temp dir outside that tree works, so
`build_android.ps1` sets `TMP`/`TEMP` to `C:\Temp\gradle`. Same fix for a bare
`flutter build apk`. Quick check:
`java.nio.channels.Selector.open()` throws when the machine is in this state.

**Linux builds happen in WSL**, not on Windows. `tool/package/wsl_setup.sh`
(run as root) installs the desktop toolchain, and `tool/package/wsl_flutter.sh`
puts a Linux Flutter SDK in `~/sdk/flutter` -- a separate checkout on purpose,
because `bin/cache` holds an OS-specific `dart-sdk` that sharing
`D:\sdk\flutter` would clobber. The build script copies the tree out of
`/mnt/d` into ext4 first; building on DrvFs is slow enough to look hung.

The `.deb` declares `pulseaudio-utils` as a hard dependency because
`record_linux` shells out to `parecord`. `unzip` is *not* a dependency: the
`llm_llamacpp` hook needs it at build time only, and nothing unpacks an archive
at runtime -- the models download as plain files.

**The Linux package does not use the llama.cpp that `llm_llamacpp` downloads.**
That prebuilt is linked against CUDA, and `libggml-cuda.so` needs
`libcuda.so.1` -- the NVIDIA *driver* library. It cannot be bundled, and
pulling it from apt drags in NVIDIA driver packages. Shipping it means every
tester without an NVIDIA card records, transcribes, and then cannot
`dlopen` `libllama.so` at all: speech works, the brief never appears. Removing
the DT_NEEDED with `patchelf` does not help either -- `libggml.so` calls
`ggml_backend_cuda_reg` directly, so the load then fails on an undefined symbol.

So `tool/package/build_llamacpp_linux.sh` builds llama.cpp from source, CPU-only
(`GGML_CUDA=OFF`, `GGML_VULKAN=OFF`, and `GGML_NATIVE=OFF` so it does not compile
for this machine CPU), and `build_linux_deb.sh` substitutes those libraries into
the bundle. The commit is the submodule pin of the `llm_llamacpp` release in
`pubspec.lock`, so the C API matches the generated FFI bindings;
`tool/package/find_llamacpp_pin.sh` re-derives it after a package upgrade. Windows
is unaffected -- its prebuilt is CPU+Vulkan with no CUDA.

Two more things the bundle gets wrong on its own, both fixed in the same script.
Each llama library ships under an unversioned filename (`libggml.so`) while its
SONAME -- and every sibling DT_NEEDED -- is versioned (`libggml.so.0`), so the
SONAMEs go back as symlinks. And the RUNPATH points at an upstream CI build
directory, so `/usr/bin/forelasning` is a wrapper that puts the bundle on
`LD_LIBRARY_PATH`; RUNPATH is not inherited by a dlopened library, so the
runner own `$ORIGIN/lib` does not cover it.

`tool/package/verify_deb_docker.sh` installs the package in a clean
`ubuntu:24.04` container and dlopens both libraries the way the app does. Run it
on every Linux package -- it is the check that catches all of the above, and none
of it shows up when you just launch the app and look at the home screen.

## Self-update (publish a release)

The app updates itself (Windows, Android, Linux; macOS gets a download +
Finder reveal, iOS none). The feed is the same GitHub repo's releases:
`https://github.com/klovaaxel/local-transcription/releases/latest/download/updates.json`
always points at the newest release. Two publish paths from the same pieces:

**GitHub Action (preferred).** Bump `version:` in `pubspec.yaml` (Android
needs the `+build` strictly increasing), commit, push a tag `v<version>` --
or run the workflow from the Actions tab. `.github/workflows/publish.yml`
builds Windows (Inno), Android (needs secrets ANDROID_KEYSTORE_BASE64,
ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS, ANDROID_KEY_PASSWORD mapped
from android/key.properties + the keystores' base64), and Linux (includes
the docker `.deb` verify), then collects everything into
`tool/package/publish_update.ps1`'s manifest and `gh release create`s the
tag. Never builds locally for a release unless debugging.

**Local builds (debugging a package).** `tool/package/build_windows.ps1`,
`tool/package/build_android.ps1` (also builds a universal APK -- the file the
updater installs), `wsl -d Ubuntu -- bash tool/package/build_linux_deb.sh`,
then `pwsh -File tool/package/publish_update.ps1 [-Notes ...] [-WhatIf]` to
hash dist\ into `updates.json` and create the release. Needs `gh` authed as
klovaaxel. `verify_deb.sh`/`verify_deb_docker.sh` check an installed .deb;
the docker variant is exactly what CI runs.

In-app: `lib/update/` (feed + downloader + installers), state in
`app_state.dart` (`_autoUpdateCheck` after 8s, silent, skipped while
recording), settings section "Uppdatering" (version line, auto toggle, Sök
efter uppdatering). Windows closes the running app via the
`ForelasningUpdateMutex` (windows/runner/main.cpp + AppMutex in
forelasning.iss) and relaunches with /RESTARTAPPLICATIONS; Android installs
through PackageInstaller (MainActivity method channel, first-time "install
unknown apps" grant). The installer is unsigned, so manifest SHA-256 is the
integrity check -- UpdateInstaller refuses a hash mismatch.

Desktop icons come from the Android launcher set (`mipmap-*`, 48-192 px) and go
in the matching `hicolor/<size>x<size>/` directory plus `/usr/share/pixmaps`.
They are still the stock Flutter icon; there is no brand asset in the repo.

MSVC reads sources as the system ANSI codepage unless told otherwise, so
`windows/CMakeLists.txt` passes `/utf-8` -- without it the Swedish window title
in `windows/runner/main.cpp` ships as mojibake.


## Agent skills

Project skills live in `.agents/skills/` and are tracked by `skills-lock.json`. Add more with `npx skills add <owner/repo> -y --copy` (do not `-l` first; that re-clones). Restore with `npx skills experimental_install`.

Claude Code only discovers project skills in `.claude/skills/`, so that directory is a mirror of `.agents/skills/`. Run `tool/sync_skills.ps1` after any add/update, then restart the session (skills are scanned once at startup). Always author or edit skills in `.agents/skills/` — the sync mirrors that tree and deletes anything that exists only in `.claude/skills/`. A junction does not work — skill discovery does not traverse links.

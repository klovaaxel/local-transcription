# Open questions

Live unknowns, in rough priority order. Each says what is actually unresolved and
what measurement would close it. Written 2026-10-01, after the Qwen3.5 tier swap
(`83c68db`).

Not a task list — nothing here is blocked on anyone. It is a record of what we
believe and how strongly.

## 1. No GPU-offload fallback anywhere in the app

`LocalLlmSummarizer.prepare` builds the repository once with
`nGpuLayers: gpuLayers ?? gpuLayersFor(spec.size)`. If context creation fails —
which it does whenever the model plus KV cache plus compute buffers exceed the
card — the app raises `ContextCreationException` and the brief never appears.
There is no retry at a lower layer count and no CPU fallback.

This is not hypothetical. It is why the Qwen3.5-9B looked unloadable: Q4_K_M
(5.68 GB) got `vk::Device::allocateMemory: ErrorOutOfDeviceMemory` on a 6 GB
RTX A1000, and the app would have shown the teacher an error rather than a slow
brief.

**Closes when** `prepare` catches context-creation failure and retries with
fewer offloaded layers, down to CPU. A slow brief beats no brief. Also worth
capping `n_gpu_layers` by detected VRAM so the choice is never wrong up front.

## 2. kb-whisper-large compute cost is unmeasured

The desktop auto-pick now takes the large model (`lib/data/app_settings.dart`),
at roughly 3x medium's compute per second of audio. Nothing has been timed on
real recorded speech — every ASR number in the repo predates this tier.

**Closes when** one real lecture is transcribed on the reference desktop and the
wall/audio ratio is compared against the `applyAsrCalibration` threshold (> 8x).
Phones stay on small, which is deliberate, so this is a desktop-only question.

## 3. `llmSlowTokPerSec = 4` is calibrated on the wrong model

That constant steps the auto pick down a tier. It was measured on Qwen2.5-7B and
3B under Vulkan. The shipped 4B measures **36.8 tok/s at 16384 and 36.9 at 8192**
on this reference desktop — an order of magnitude above the threshold, so the
constant cannot fire spuriously on this hardware. But the *hybrid* architecture
behaves differently under decode, and phone numbers are unknown.

Worth noting the desktop measurement showed **doubling the context window costs
nothing** (36.8 vs 36.9), because the Gated DeltaNet recurrent state does not
grow with context. That is why the desktop tier is the same 4B GGUF as the phone
tier with a wider window.

**Closes when** the decode probe runs on real phone hardware for both tiers.

## 4. iOS Metal offload of a hybrid model is untested

`gpuLayersFor` returns 99 for every size on iOS, so all layers offload. Qwen3.5
is a hybrid Gated DeltaNet model and its Metal kernels are newer in ggml than
plain attention. Android is CPU-only, so this is iOS-specific.

**Closes when** someone runs the brief on an iPhone with the large tier selected
and compares against `AppSettings.llmGpuOffload`, which the probe already picks
per device by measuring CPU against GPU both ways.

## 5. The harness aborts entirely if any single model fails

`test/brief_probe_test.dart` calls `expect(File(modelPath).existsSync())` inside
the loop, so a missing file or an unloadable model kills the whole run and
`feedback/quality/SCORES.md` is never written. That happened repeatedly during
the 9B investigation: a model that cannot load silently discards every other
model's results.

Worse, `SCORES.md` is **overwritten**, not appended, so each model generation
replaces the previous one's rows. The Qwen2.5 baseline survives only because a
failed run happened not to overwrite it.

**Closes when** the harness writes partial results on failure and appends by
model generation, so cross-generation comparison is possible at all.

## 6. Repeated Vulkan context creation exhausted VRAM nondeterministically

During the 9B runs the test process died natively — no Dart exception, exit -1 —
partway through, with the log ending mid tensor-load. All contexts in the log
were at one model's window, so the crash was not the 9B. An identical run
previously got 27 generations further. A speed probe on the same file passed.

Almost certainly repeated context creation leaking VRAM in the Vulkan backend.
**Not** reproduced in the app itself, where a session creates a handful of
contexts rather than dozens, so this may be a harness-only artefact.

**Closes when** someone runs a long session and watches for degradation. Low
priority unless it reproduces outside the harness.

## 7. Repetition or harness artefacts in the scoring

Two were found and worked around rather than fixed:

- The harness matches planted facts as literal substrings. The 4B wrote
  "sidor 84-89" against a planted fact of "sida 84" and scored a miss, having in
  fact captured *more*. Swedish plural agreement defeats exact matching.
- `historia` scored 3/4 for the 4B against 4/4 for the 3B. The missing fact was
  this artefact, not a regression.

**Closes when** planted-fact matching tolerates number and case agreement.

## 8. Whether the desktop tier should be the same model as the phone tier

Now that the 9B is dead, `llmLarge` is the same 4B GGUF as `llmMedium` with a
16384 window instead of 8192. That is defensible — one download, no merge step,
prov found 9/9 — but it means there is no longer a real size step-up on desktop,
and the `provdetail` per-tier schedule wording tuned on the old 7B now applies to
a 4B it was never validated against.

**Closes when** the `provdetail` row is re-measured against the shipped 4B, or
the wording is dropped as no longer earning its place.

## Deliberately not pursued

- **Qwen3-ASR-1.7B** — supports Swedish and beats Whisper's ceiling in
  principle, but audio lives in `libmtmd`, a separate library the pinned
  `llm_llamacpp` does not ship, and the plugin exposes no way to feed audio. A
  localhost `llama-server` subprocess would work on desktop, reusing
  `lib/cloud/openai_compatible.dart`, since it already speaks
  `audio/transcriptions`. It would not touch the live-caption path. Decide only
  after a WER comparison against kb-whisper-large on the field transcript
  justifies the work.
- **TwiL-LM** (webAI) — rejected on two independent grounds. Its licence is
  non-commercial only, section 3.3, which a commercial product cannot ship. Its
  own model card states it is "not a chat model" with no instruction-following
  alignment work and IFEval regressed, and it is English-only. The `apache-2.0`
  file in its repo covers the SmolLM3 base only, not the merged weights.
- **Qwen3.5-9B** — do not retry without a llama.cpp build where IQ3 prefill
  survives. Measured: Q4_K_M cannot allocate a context on 6 GB, and IQ3
  (3.83 GB, the only rung that fits) crashes during prefill at both 16384 and
  8192, on Vulkan and CPU-only alike, while a short probe prompt passes.
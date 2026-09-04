# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Users

Primary user: a teacher. They open the app on a phone at the start of a lecture, record while they teach (topic, answers to questions — often only the teacher’s side is audible — due dates, tests, assignments), then later sit at a computer and copy a brief into the school platform so students who forgot, were absent, or whose parents want an update can look back.

The app is not for students or parents. They only see the brief after the teacher pastes it elsewhere.

## Product Purpose

Föreläsning records a lecture on device, transcribes Swedish locally, and turns that transcript into a copy-ready brief the teacher can paste into their school platform.

Success: after class, the teacher has a short, accurate brief they trust enough to publish — without uploading audio or transcript unless they opt into an EU provider in settings.

## Positioning

Audio and transcript stay on the device by default. Transcription uses KB-Whisper (Swedish) on device. A school that wants more accuracy than a phone can run can opt into an EU-hosted provider instead — the same KB-Whisper family, on European infrastructure, never a US default. The after-class artifact is a three-part brief written for the school platform, not a meeting-minutes newsletter.

## Operating Context

- During class: phone is nearby; the teacher should start, leave it, and stop. They are not operating the UI while talking.
- After class: computer (Windows, macOS, or Linux) for reading, a light transcript check if needed, then one-tap copy or share into the LMS / schedule.
- Swedish UI and Swedish speech.
- Existing three-part summary is being reframed to match the teaching job (not “decisions” from a meeting).

## Capabilities and Constraints

Confirmed:

- Record 16 kHz WAV on device; live captions during recording.
- On-device ASR (KB-Whisper small/medium INT8) and local LLM summarizer (Qwen 1.5B default, optional 7B on stronger devices); models download on first use. Lectures longer than the model window are chunked and merged, not truncated to start+end.
- Sessions persist locally as JSON under app support.
- Share/copy the brief as text. No LMS API in v1.
- Optional EU cloud: transcription and the brief can each be pointed at an OpenAI-compatible provider (Berget AI preset, Sweden). Both are off by default and opt in separately. Cloud speech uploads the finished recording in ~10-minute parts and gives up live captions; a cloud brief uploads the transcript.
- Transcript is read only; it is a check on the brief, not the after-class hero. Re-running the speech model is the only thing that changes it.
- Platforms: iOS, Android, macOS, Windows, Linux (Flutter, Material 3).

The after-class brief the teacher asked for:

1. What was covered
2. Dates, tests, and assignments
3. What absentees and parents need

- A lecture is identified by date and time. Its name is derived from the first topic in the brief; the teacher never types one. No brief yet, or nothing identifiable in it, means the date is the name.

## Brand Commitments

- Product name in the app today: **Föreläsning**.
- Voice: Swedish, short, factual. No hype. Do not invent facts, names, or dates that are not in the transcript.

## Evidence on Hand

- Working app: home list, record + live captions, session brief (covered / dates / absentees-parents) with a derived name, settings (device vs cloud transcription + ASR size, local LLM 1.5B/7B vs cloud brief, provider card, delete-audio).
- Summary prompt, few-shot, and parser live in `lib/summarize/newsletter.dart`. Local decoding is low-temperature extraction via `lib/summarize/local_summarizer.dart`.
- No brand assets, photography, or real lecture corpus in the repo. Do not fabricate testimonials or school-platform integrations.

## Product Principles

1. The teacher’s job after class is publishing a brief, not reviewing an ASR workbench.
2. Recording must be startable and stoppable without attention; the phone is a witness, not a second job.
3. Never upload audio or transcript on the default path. Cloud is opt-in, per job, EU-hosted, and the screen says what leaves the device before it does.
4. The brief must be copy-true: short, Swedish, and honest about what was not said.
5. Phone and desk are one product: same sessions, different emphasis (record vs copy).

## Accessibility & Inclusion

No product-specific standard was named. Keep touch targets usable in class, readable type on a desk display, and respect system text scale and reduced motion.

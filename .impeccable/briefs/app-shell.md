# App shell

Mode: Operate
Audience: teacher, phone in class then desk after class
Job: record a lecture, then copy a brief into the school platform

## Direction contract

THESIS: A lecture app the teacher touches twice — start, then copy. The interface is one soft material with three states, so nothing has to be learned twice.
OWN-WORLD: Soft UI. Cool neutral base, surfaces moulded out of it rather than laid on it, light from the top-left. One saturated indigo, used only as a fill for the single primary action. Generous radii, no hairline chrome, no second card style.
GRAMMAR: raised = press it, flat = read it, inset = put something in it; floating is the transient overlay above the page, not a page surface. Depth carries the affordance; colour carries rank.
NOTHING TO FILL IN: the teacher never types in this app. The name comes from the brief and the transcript is read only.
STORY: Teacher opens a dated screen, reads three blocks in one card, presses the one indigo bar. Delete sits far below, never beside copy.
FIRST VIEWPORT: Flat title block on the base — the lecture's derived name, then date and time. One raised card holding the three-part brief, with Kopiera and Dela in one row beneath it.
RANK BY ROW, NOT BY SLAB: the thumb-zone bar belongs to a screen with a single job (record, stop). Peer actions sit inline as ordinary buttons; the accent marks which one is the point.
ONE VOICE: every confirmation, download and failure surfaces in the same floating toast. Confirmations clear themselves; failures wait.
COMPONENTS: one page shell (`SoftPage`), one card (`SoftCard`), one button in three roles (`SoftButton.primary|quiet|danger`). Adding a variant is a change to this contract, not an implementation detail.
CONTRAST: body and secondary text clear AA on the base; the accent is a fill only, because as text it does not.
FINISH: `flutter test test/preview/screens_preview.dart` is the look check.

## Superseded

The earlier Närvarostämpeln direction (municipal paper, wet ultramarine stamp, hairline rules, no cards) was replaced on 2026-09-01 at the product owner's request. The comps under `.impeccable/mocks/` belong to that direction and no longer describe the build.

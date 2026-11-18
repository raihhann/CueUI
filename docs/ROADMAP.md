# CueUI development roadmap

CueUI is a working prototype with local intent inference and bounded phone-action workflows. This is a prioritized development backlog, not a list of completed features or a release-date commitment.

## P0 — Make the launcher the product

The current demo uses an assistant-style screen. The requested minimalist launcher redesign has not been implemented yet.

- [ ] Make installed apps and a small, editable favorites list the default home experience.
- [ ] Add a clear button to reveal the input bar; keep input hidden when it is not needed.
- [ ] Show the current result, permission request, or recipient choice in a compact panel, without chat bubbles or a conversation timeline.
- [ ] Keep Library, Routines, and Settings reachable through simple secondary navigation.
- [ ] Persist favorite choices and appearance; make Back and Home behavior predictable.
- [ ] Validate light/dark themes, small screens, large text, keyboard use, and portrait/landscape layouts.

**Completion criterion:** a user can open an app, enter a command, resolve a recipient choice, and return home without navigating a chat interface.

## P0 — Accessibility with intended users

Voice input, TTS, and a screen-automation service are useful building blocks. They do not establish that a blind person can independently use the launcher or that the interface suits older adults.

- [ ] Test all essential paths with TalkBack and Switch Access, including setup and permission screens.
- [ ] Review semantic labels, focus order, touch-target sizes, contrast, large text, and transient announcements.
- [ ] Speak recipient choices and action outcomes clearly; avoid conflicting TTS and microphone capture.
- [ ] Provide discoverable non-voice controls and clear recovery when recognition fails.
- [ ] Trial core tasks with blind, low-vision, and older participants; record where help is required and incorporate feedback.

**Completion criterion:** tested participants can complete agreed core tasks with their chosen assistive setup; remaining barriers are documented. Do not claim accessibility certification or universal suitability from widget tests alone.

Reference: [Android accessibility testing](https://developer.android.com/guide/topics/ui/accessibility/testing).

## P0 — Privacy controls and clearer data boundaries

- [ ] Add a strict offline setting that blocks web fallback and network-dependent speech fallback, with a useful explanation when a task cannot run.
- [ ] Make any network-dependent fallback visible and controllable before sending user content.
- [ ] Request permissions in the context of an action instead of treating every capability as mandatory setup.
- [ ] Remove or redact sensitive command content from production diagnostics and support exports.
- [ ] Add clear-all context, retention, media/transcript export, and deletion controls with documented scope.
- [ ] Review whether application-level encryption is appropriate for recordings/transcripts and define the threat model.
- [ ] Validate downloaded model integrity and improve interrupted-download handling.
- [ ] Test network requests, shared-file grants, logs, and storage behavior; obtain a security review before strong privacy claims.

**Completion criterion:** the documented data-flow inventory matches observed behavior; offline mode does not silently fall back to external processing. Local inference alone is not evidence of zero leakage.

## P0 — Reliable messaging and consequential actions

- [ ] Test multiple and identical contact names, off-screen results, account variants, languages, and changing WhatsApp layouts.
- [ ] Prefer stable recipient identity where available; never treat the first visible search match as sufficient evidence when the recipient is ambiguous.
- [ ] Revalidate the destination and attachment before sending; retain the intended file while asking follow-up questions.
- [ ] Make action-review and cancellation behavior consistent for calls, messages, attachments, and recording controls.
- [ ] Separate “Send control activated” from delivered/read status; do not invent a delivery confirmation.
- [ ] Exercise stale screens, existing drafts, manual intervention, app switching, and permission revocation.

**Completion criterion:** controlled test chats demonstrate correct target/content selection and predictable failure handling across the supported device/app matrix.

## P1 — Performance and local model quality

The recorded demo used Qwen3 0.6B on a OnePlus Nord 3 5G with 8 GB RAM / 128 GB storage and took approximately 13 seconds to trigger the command. It is one observation, not an inference-only benchmark.

- [ ] Record Android/OxygenOS version, model file/quantization, load state, prompt, and timing boundaries for each benchmark.
- [ ] Measure cold load, warm inference, full command-trigger latency, task success, peak memory, and battery impact.
- [ ] Compare model choices and context sizes on lower-memory and mid-range phones.
- [ ] Evaluate casual phrasing, unsupported requests, multilingual input, and incorrect tool arguments.
- [ ] Improve cancellation and model lifecycle behavior without sacrificing command accuracy.

**Completion criterion:** publish reproducible results and representative median/tail latency rather than a single best-case number.

## P1 — Speech, recording, and camera compatibility

- [ ] Evaluate broader offline speech/transcription support and language-pack setup.
- [ ] Test accents, recognition errors, silent recordings, long audio, and interrupted transcription.
- [ ] Improve microphone handoff; keep the current limitations for video and WhatsApp voice recording visible until resolved.
- [ ] Validate camera switching, countdown cancellation, rotation, repeated captures, app backgrounding, storage pressure, and recording recovery on real hardware.

**Completion criterion:** supported combinations are documented, and unsupported configurations return useful errors without losing or silently transmitting user data.

## P1 — Agentic execution and production readiness

The current system has one orchestrator, optional local intent extraction, and predefined execution workflows. Adding more services or labeling tools as agents would not create independent reasoning agents.

- [ ] Explore bounded plan–act–observe–recover behavior for tasks that cannot be handled reliably by the current workflows.
- [ ] Keep tool allowlists, execution limits, meaningful user approval points, and observable outcomes as planning becomes more flexible.
- [ ] Test hostile or misleading text from external app screens before using screen content in model-driven decisions.
- [ ] Add repeatable native/integration testing, release signing, dependency review, and a chosen project license.
- [ ] Keep screenshots, demos, capability labels, and privacy/accessibility statements aligned with the released build.

**Completion criterion:** supported tasks have measured success/failure behavior and transparent limits. Continue describing CueUI as a local-first launcher with agentic controls until broader autonomy is implemented and evaluated.

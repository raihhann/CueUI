# Phone validation

The Dart test suite uses simulated native results and screen trees. Run these checks on the actual Android phone before relying on capture or sending. Use a test chat you control for messaging checks.

## Interface

1. Switch Settings → Appearance between System, Light, and Dark. Restart the app and verify the selection is retained.
2. Open Assistant, Library, Routines, Apps, and Settings in portrait and landscape. Test a small screen, a large font size, and the keyboard open.
3. Check the floating bubble, its keyboard, recipient choices, permission links, and confirmation buttons.

## Accessibility

1. With TalkBack enabled, complete launcher navigation, command entry, microphone activation, recipient selection, confirmation, cancellation, and return Home without relying on sight.
2. Verify every actionable control has an understandable name, reachable focus position, and useful state announcement. Check that temporary errors and choices are announced.
3. Repeat key tasks with Switch Access, large text, and increased display size. Check that spoken feedback does not conflict with microphone recording.
4. Test onboarding and permission grants, not just the already configured app. Record where a user needs help.
5. Invite blind, low-vision, and older participants to evaluate agreed tasks with their own preferred settings. Document consented feedback and remaining barriers; do not infer accessibility from screen automation alone.

## Audio

1. Start recording, speak, pause, wait, resume, speak again, then `stop and save as meeting notes`.
2. Play the saved file. Verify paused time is absent, both speech segments are present, and duration is plausible.
3. Record while another app is open and use notification pause/resume/stop. Verify the file appears in Library after returning.
4. During recording, tap Cue's mic and say `stop and save as voice command test`. Check microphone handoff and file playback.
5. Verify empty/very short recording, denied microphone access, low storage, process interruption, and interrupted-file recovery.

## Camera

1. Take a photo and a selfie. Check orientation, saved file, thumbnail, and full-size preview.
2. Take a photo with a 3-second countdown. Cancel another countdown before capture; no image should be sent afterward.
3. Switch cameras, then capture without specifying a lens. Confirm the selected lens is retained.
4. Start video, speak, stop, and play it with sound. Check the recording indicator and stop/save behavior when the camera leaves the foreground.
5. Deny camera or microphone permissions and verify the grant-and-retry path. Test a device with only one usable camera.

## WhatsApp

1. Use a test contact to check a unique text match. Repeat with multiple similarly named contacts and with identical display names.
2. While recipient choices are visible, change the message, choose a recipient, and confirm the correct content and recipient.
3. Capture a photo, share it, and choose between contacts. Capture another file separately; verify a pending choice still refers to the original attachment.
4. Share WAV audio and MP4 video. Verify picker → preview → send; check that attachments arrive correctly in the test chat.
5. Test starting with WhatsApp in an existing chat, an empty search, a locked account, and a non-English interface. Unrecognized UI must stop for manual completion.
6. Start an actual WhatsApp voice message. Verify it is locked and recording, then use typed send/discard commands. Test cancelling before Send. Confirm that Cue's spoken replies do not enter the recording.
7. After choosing a contact, try `send it to him` and `use the other Raihan`. Restart and verify ambiguous pronouns require clarification.
8. Switch away from WhatsApp during automation. No unrelated screen's Send button should be activated.

## Transcription

1. On Android 13+, install offline speech data and transcribe a known Cue WAV recording.
2. Verify the complete spoken content, edit the transcript, then search for words from its middle and end.
3. Check silence, long recordings, missing language data, unsupported engines, and app closure during transcription. Errors must not create a fabricated transcript.

## Routines

1. Edit Bedtime's brightness, DND behavior, and alarm time before running it.
2. Run it and verify each actual system state and the alarm in the clock app.
3. Revoke DND access and run again. It should stop there, preserve the already changed brightness, and avoid executing the later alarm step.
4. Create a custom routine, restart, and run it by name. Check persistence and invalid inputs.

Record the Android version, phone model, WhatsApp version/language, speech engine/language pack, command, visible outcome, and any error for each failure. A successful build is not a substitute for these checks.

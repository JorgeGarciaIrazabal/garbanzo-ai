# Talk Mode — Research & Design

> Goal: a full-screen, hands-free **voice conversation** experience (like OpenWebUI's
> "Call" mode / ChatGPT Advanced Voice). No push-to-talk button — the app listens,
> you speak, it detects when you stop, transcribes, streams the model reply, speaks it
> back, and you can **interrupt** by talking. Scoped to **1:1 chat mode only** (not Rooms).

---

## 1. How OpenWebUI's Call mode works (reference)

OpenWebUI ships this as a full-screen overlay (`Call.svelte`) with an **event-driven
state machine** on top of the normal chat/STT/TTS stack. Key mechanisms:

| Concern | OpenWebUI approach |
|---|---|
| **State machine** | `Listening → Thinking → Speaking`, then back to `Listening`. Status text + an audio-level visualizer reflect the state. |
| **Hands-free capture (VAD)** | Browser `MediaRecorder` + **Web Audio API** analyses live audio levels. It detects when you *start* speaking and, after a **silence threshold**, decides you *finished* → auto-sends the recorded audio to `transcribeAudio`. No button press. |
| **Interruption** | While the AI speaks, `voiceInterruption` setting keeps the mic hot. User voice (or a tap) calls `stopAllAudio()`, cancels playback, and returns to Listening. UI shows "Tap to interrupt". |
| **Low-latency TTS** | The streamed reply is chunked **per sentence**. Events `chat:start` / `chat` (each sentence) / `chat:finish` drive TTS so speech starts on the *first* sentence, not after the whole answer. An `audioCache` map avoids re-synthesizing identical text. |
| **Thinking feedback** | When the model is generating but hasn't produced speakable text yet, status shows **"Thinking"**. |
| **Stay awake** | **Wake Lock API** prevents the device sleeping during a call. |
| **Cleanup** | Lifecycle teardown releases mic, audio graph, and playback on exit. |

Sources:
- <https://deepwiki.com/huntershen008/open-webui/5.2-call-and-voice-features>
- <https://docs.openwebui.com/features/chat-conversations/chat-features/>
- <https://github.com/open-webui/open-webui/discussions/9647> (voice interruption)
- <https://github.com/open-webui/open-webui/discussions/4574> (GPT-4o-like advanced voice)

---

## 2. What we already have (reuse, don't rebuild)

Everything the state machine needs already exists — Talk Mode is mostly **orchestration**.

**STT (speech → text)**
- `AudioService.transcribeAudio(bytes, filename)` → `POST /api/v1/stt/transcribe` (Faster-Whisper).
- `VoiceRecordingHelper` (`lib/features/chat/widgets/input/voice_recording_helper.dart`)
  records **WAV 16 kHz mono**:
  - Mobile: `record` package (`AudioRecorder`) with mic-permission handling.
  - Linux desktop: spawns `arecord` (ALSA) or falls back to `parecord`.

**TTS (text → speech)**
- `AudioService.speak(text, voice, speed)` → MP3 bytes; `streamSpeak(...)` streams to a temp file.
- Playback pattern already proven in `speak_button.dart`: `audioplayers` `AudioPlayer` +
  `BytesSource`, **fresh player per chunk**, text split into ~sentence chunks and
  synthesized back-to-back so playback starts on the first chunk.
- `cleanTextForSpeech()` (`utils/text_cleaner.dart`) strips markdown/emojis before TTS.
- Voice/speed/auto-play live in `SettingsProvider` (`ttsVoice`, `ttsSpeed`, `autoPlayTts`).

**Chat streaming**
- `ChatProvider.sendMessage(text)` runs the normal SSE turn.
- Live state: `streamingMessage` (`ValueNotifier<ChatMessage>`), `isSending`,
  and chunk handling in `_consumeAssistantStream`. Chunk types: `thinking`, `chunk`,
  `tool_call`, `tool_result`, `done`, `error`; **`onDone` = real end of stream**.
- `stopStreaming()` cancels the in-flight turn.

**VAD building block**
- The `record` package (7.1.1) exposes `onAmplitudeChanged(interval)` → `Amplitude`
  stream and `onStateChanged()`. This is enough for **energy-based silence detection**
  (no extra ML dependency needed for v1).

---

## 3. Gaps / new pieces required

1. **Voice Activity Detection loop** — decide "user started" / "user stopped" from the
   amplitude stream (start on level > threshold; end after ~800 ms–1.2 s below threshold).
2. **Interruption while speaking** — keep amplitude monitoring active during TTS playback;
   on sustained user speech, stop the player + `stopStreaming()` and jump to Listening.
3. **Sentence-level TTS from the live stream** — synthesize each completed sentence as
   `streamingMessage` grows, instead of waiting for `onDone` (latency win, matches OpenWebUI).
4. **A dedicated full-screen Talk UI** with the state machine + visualizer.
5. **Wake lock** — add `wakelock_plus` to keep the screen on during a call.
6. **Desktop VAD caveat** — the current Linux path uses raw `arecord`, which has **no
   amplitude stream**. Options below.

---

## 4. Platform caveats (important)

- **Amplitude/VAD availability:** `onAmplitudeChanged` is supported by the `record`
  package on Android/iOS/web. On **Linux desktop**, `VoiceRecordingHelper` currently
  bypasses `record` (uses `arecord`), so there's no amplitude stream. For Talk Mode on
  desktop, either:
  - (a) force the `record`/`parecord` path when in Talk Mode so amplitude works, or
  - (b) start with **tap-to-stop** on desktop and full VAD on mobile/web.
  Recommended: ship VAD on mobile/web first; desktop uses tap-to-stop as a fallback.
- **Recorder can't record + play simultaneously on all platforms.** True barge-in
  (listening *while* speaking) may conflict with the audio session on mobile. v1
  interruption can be a **tap-anywhere-to-interrupt** gesture; amplitude-based barge-in
  is a v2 enhancement where the platform allows it.
- **Web:** mic needs a user gesture to start; wake lock and autoplay have browser rules.

---

## 5. Proposed architecture (simplest that works)

A single controller drives a small state machine; the UI is a thin `ValueListenable`
consumer. Reuse `ChatProvider` for the actual turn so history, memory, KB, and tools
all keep working — Talk Mode is just a different *input/output surface* over the same turn.

```
lib/features/chat/talk/
  talk_mode_controller.dart   // ChangeNotifier: state machine + VAD + TTS queue
  talk_mode_page.dart         // full-screen overlay UI (visualizer + status)
  talk_vad.dart               // amplitude → speech-start/-end detection
  talk_tts_queue.dart         // sentence splitter + sequential playback + stop()
```

**States**
```
idle → listening → (VAD end) → transcribing → sending
     → thinking (isSending, no speakable text yet)
     → speaking (sentence queue draining)
     → listening   // loop
     + interrupted (user speaks/taps during speaking) → listening
     + error / ended
```

**Wiring**
- **Listen:** start recorder, subscribe to amplitude. On speech-end, `stopAndTranscribe()`
  → transcript. If empty, return to listening (say nothing).
- **Send:** `chatProvider.sendMessage(transcript)`.
- **Thinking:** while `isSending` and no sentence has completed yet, show "Thinking…"
  (optionally a short spoken "let me think"). If the model emits `thinking` chunks,
  we already know it's reasoning.
- **Speak:** watch `streamingMessage`; each time a **completed sentence** appears
  (`(?<=[.!?])\s`), enqueue it to `talk_tts_queue` which synthesizes via
  `AudioService.speak` and plays sequentially (same pattern as `speak_button`).
- **Done:** on `onDone`, flush any trailing partial sentence, let the queue drain,
  then return to Listening.
- **Interrupt:** tap (v1) or sustained mic energy (v2) → `queue.stop()` +
  `chatProvider.stopStreaming()` → Listening.

**Entry point:** a "Talk" icon in `chat_app_bar.dart` (and/or `chat_input_widget.dart`),
enabled only when a chat conversation is active. Opens `TalkModePage` as a full-screen route.

---

## 6. UX details (to feel good)

- **One clear status line:** *Listening… / Thinking… / Speaking (tap to interrupt)*.
- **Live audio visualizer** driven by the amplitude value (a pulsing orb / bars).
- **Always-visible controls:** mute mic, end call (X). Everything else hands-free.
- **Barge-in forgiveness:** small debounce so a cough doesn't cut off the AI.
- **Say when thinking:** show (and optionally speak) "Thinking…" so silence isn't dead air.
- **Graceful STT empty:** if transcription is blank, quietly resume listening.
- **Wake lock** on while the call screen is open; released on exit.
- **Error recovery:** STT/TTS/LLM failure → spoken-or-shown "sorry, try again", back to Listening.
- Reuse `SettingsProvider` voice/speed; consider a Talk-Mode-only "voice interruption" toggle.

---

## 7. Suggested build phases

1. ✅ **Skeleton + turn reuse (no VAD):** full-screen page, tap-to-talk → `sendMessage`,
   auto-speak the final reply via the existing chunked TTS. Proves the loop end-to-end.
   *(`lib/features/chat/talk/`, Talk icon in the chat app bar.)*
2. ✅ **Sentence-streamed TTS:** speak sentences as they stream (latency win) + "Thinking…"
   state. *(Controller watches `ChatProvider.streamingMessage`, enqueues each completed
   sentence; phase stays `thinking` until the first speakable sentence.)*
3. ✅ **VAD + call loop:** energy-based `TalkVad` (dBFS thresholds) over a dedicated
   `TalkRecorder` (record pkg, amplitude stream on all platforms) auto starts/stops
   listening; the phase loops listen → speak → listen until the ✕ ends the call.
   *Caveat: Linux amplitude via `parecord` is less battle-tested — tap-to-send remains
   the guaranteed fallback, and on-device threshold tuning is still pending.*
4. ✅ **Interruption:** tap barge-in (tap during speaking → back to listening) always
   works. Automatic **voice** barge-in is implemented behind a `voiceBargeIn` flag but
   **defaults off**: over speakers the mic hears the AI's own playback, and without
   acoustic echo cancellation no energy threshold separates "AI is loud" from "user is
   talking over it" — so it self-interrupts. Enable it only where there's no echo
   (headphones), or revisit with AEC.
5. ✅ **Polish:** live level-reactive orb (phase 3), wake lock (`wakelock_plus`, keeps the
   screen on during a call), mute toggle (parks the loop in listening with the mic closed),
   and tap-to-retry error UX. *(Remaining nice-to-have: waveform-bars visualizer variant.)*
6. ✅ **Desktop (Linux):** `TalkRecorder` streams raw PCM from `arecord -D default`
   and computes RMS→dBFS itself for VAD (the `record` package needs PulseAudio's
   `parecord`, which isn't always installed). **Use the ALSA `default` device**, not a
   specific `plughw:card` — on PipeWire, opening a hardware card directly fails with
   "Device or resource busy", and card auto-detection can grab a dead/floating input.
   `default` routes to the user's configured mic and shares the device. Verified E2E on
   Linux: capture → STT → LLM → sentence-streamed TTS, mute, and teardown all work.

---

## 8. Decisions (locked with Jorge)

- **VAD everywhere.** Full hands-free auto start/stop on all platforms, including Linux
  desktop. → Talk Mode must **route desktop recording through the `record`/`parecord`
  path** (not raw `arecord`) so `onAmplitudeChanged` is available. Phase 6 becomes part of
  core VAD work, not a fallback. Verify `record_linux` exposes `getAmplitude`; if not,
  fall back to reading amplitude from the PCM stream via `startStream()` and computing RMS.
- **Interruption: both tap and voice barge-in.** Tap-anywhere always interrupts; in
  addition, keep the mic hot during Speaking and use the VAD energy signal to auto-interrupt
  when the user talks over the AI (debounced to ignore coughs/echo). This requires
  **record-while-playing** — validate the audio session allows simultaneous capture +
  playback per platform; where it doesn't, tap-to-interrupt remains the guaranteed path and
  barge-in degrades gracefully. Consider basic **echo suppression** (raise the VAD threshold
  or gate the mic to the TTS envelope) so the AI's own voice doesn't self-interrupt.

### Still to confirm (non-blocking)
- **Visualizer style:** minimal pulsing orb vs. waveform bars.
- **New dependency OK?** `wakelock_plus` for keep-awake (small, well-maintained).
```

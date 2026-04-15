# Fish Audio TTS Integration Plan

## Overview

Add Fish Audio as an optional cloud TTS provider alongside the existing local Kokoro TTS. Users can choose between Kokoro (free, local, fast) and Fish Audio (API-based, higher quality, paralinguistic emotion tags like `[laugh]`, `[whisper]`, `[sigh]`). Fish Audio requires an API key from https://fish.audio.

## Architecture

### TTS Provider Abstraction
Currently `SpeechService.swift` is tightly coupled to `KokoroManager`. We need a provider abstraction so the service can route to either Kokoro or Fish Audio based on user settings.

**New enum:** `TTSProvider` — `kokoro` or `fishAudio`
**New class:** `FishAudioManager` — handles API key storage, voice selection, API calls, and audio streaming
**Modified:** `SpeechService` — routes `enqueueUtterance` to either Kokoro or Fish Audio based on active provider
**Modified:** `KokoroManager` — add `voiceEnabled` → generalized to overall voice toggle (already exists)

### Fish Audio API Details
- **Endpoint:** `POST https://api.fish.audio/v1/tts`
- **Auth:** `Authorization: Bearer <token>` header
- **Model header:** `model: s2-pro`
- **Body (JSON):**
  ```json
  {
    "text": "Hello!",
    "reference_id": "<voice-model-id>",
    "format": "pcm",
    "sample_rate": 24000,
    "latency": "balanced",
    "prosody": { "speed": 1.0, "volume": 0 }
  }
  ```
- **Response:** Streaming audio bytes (PCM/MP3/WAV)
- **Emotion control:** Embed `[tag]` in text — e.g. `"I can't believe it [gasp] you did it [laugh]"`. S2-Pro treats bracket tags as natural language descriptions with 15,000+ unique tags supported. Common: `[whisper]`, `[laugh]`, `[emphasis]`, `[sigh]`, `[gasp]`, `[pause]`, `[angry]`, `[excited]`, `[sad]`, `[clearing throat]`

### Curated Voices (5 voices)
Fish Audio has 2M+ community voices. We'll curate 5 high-quality, well-known voices by their `reference_id`. These are the most popular/highest-rated voices from the Fish Audio platform suitable for an AI assistant context:

| Name | Gender | Style | reference_id |
|---|---|---|---|
| **Aria** | Female | Warm, conversational US English | `e58b0d7efca34b2a85e5f31f30ea4a0d` |
| **Ethan** | Male | Clear, professional US English | `ef4c0a30987746099e3e5f6b1dc5b898` |
| **Mia** | Female | Friendly, expressive US English | `7f92f8afb8ec43bf81429cc1c9199cb1` |
| **Noah** | Male | Deep, calm US English narrator | `a0e99c3adca047b6ace8eb4a0e0e8c4c` |
| **Lily** | Female | Soft, gentle British English | `3ba28e01eb7a4bb0b1dc0a13f5fe7aa0` |

> **Note:** These reference_ids need to be verified at integration time by browsing https://fish.audio and selecting top-rated English voices. The IDs above are placeholders — the actual IDs should be obtained by browsing the Fish Audio voice library for their highest-rated English assistant-style voices.

### API Key Storage
Fish Audio API key stored in the existing `ProviderStore` encrypted store? No — that's for AI chat providers. Better: Store in `UserDefaults` (just an API key string) or use Keychain directly. Simplest: Store encrypted alongside Kokoro settings using a dedicated key in UserDefaults, since it's not a chat provider credential.

Actually, simplest and most consistent: Add a `fishAudioApiKey` to `KokoroManager` (which we'll rename... no, keep it, just add Fish Audio settings there) or create a new `FishAudioManager`.

**Decision:** Create `FishAudioManager` as a new `@MainActor ObservableObject` in `Tama/Sources/Voice/FishAudioManager.swift`. Store the API key in Keychain via a simple helper (or just UserDefaults for now since it's not highly sensitive — it's a TTS key, not a bank account).

## File Changes

### New Files

1. **`Tama/Sources/Voice/FishAudioManager.swift`**
   - `@MainActor final class FishAudioManager: ObservableObject`
   - Published: `apiKey`, `selectedVoice`, `voiceSpeed`, `isGenerating`
   - Static `availableVoices: [FishVoiceInfo]` (5 curated voices)
   - `generateAudio(text:) async -> Data?` — calls Fish Audio API, returns PCM audio data
   - `generateAudioBuffer(text:) async -> AVAudioPCMBuffer?` — wraps PCM into buffer
   - `streamAudio(text:) -> AsyncStream<Data>` — streaming variant
   - API key persistence in UserDefaults (key: `fishAudioApiKey`)
   - Voice selection persistence (key: `fishAudioSelectedVoice`)
   - Speed persistence (key: `fishAudioVoiceSpeed`)

2. **`Tama/Sources/Voice/TTSProvider.swift`**
   - `enum TTSProvider: String, Codable, CaseIterable` — `.kokoro`, `.fishAudio`
   - Display names, descriptions
   - Persisted in UserDefaults (key: `selectedTTSProvider`)

### Modified Files

3. **`Tama/Sources/Voice/SpeechService.swift`**
   - `enqueueUtterance` — check active provider
   - If Kokoro: existing path (KokoroManager)
   - If Fish Audio: call `FishAudioManager.shared.generateAudioBuffer(text:)` then queue playback
   - Fish Audio generation happens on a background Task (async), no serial queue needed (it's an HTTP call)

4. **`Tama/Sources/Voice/VoiceSettingsView.swift`**
   - Add provider selector at top (segmented control: "Kokoro (Local)" / "Fish Audio (Cloud)")
   - When Fish Audio selected:
     - Show API key input field (if not set)
     - Show Fish Audio voice list (5 curated voices, no download needed — just select)
     - Show speed slider (same range)
     - Show info text about emotion tags
   - When Kokoro selected: existing UI unchanged

5. **`Tama/Sources/Voice/VoiceSettingsController.swift`**
   - No changes needed (just shows VoiceSettingsView)

6. **`Tama/Sources/Onboarding/OnboardingView.swift`**
   - In the `voiceStep`:
     - After the Kokoro section, add a divider and "Cloud TTS (Optional)" section
     - Show Fish Audio as an alternative with API key input
     - Brief description: "Higher quality voices with emotion. Requires Fish Audio API key."
     - Link to fish.audio for signup

7. **`Tama/Sources/Voice/KokoroManager.swift`**
   - Add `static var activeProvider: TTSProvider` (read from UserDefaults)
   - Or better: Keep KokoroManager as-is, use the new TTSProvider enum separately

### project.yml
8. No new SPM dependencies needed — Fish Audio is a simple REST API (URLSession + JSONEncoder).

## Steps

1. Create `Tama/Sources/Voice/TTSProvider.swift` with enum `TTSProvider` (`.kokoro`, `.fishAudio`), display names, and UserDefaults persistence for the selected provider (key: `selectedTTSProvider`, default: `.kokoro`)
2. Create `Tama/Sources/Voice/FishAudioManager.swift` — an `@MainActor ObservableObject` with API key storage (UserDefaults key: `fishAudioApiKey`), voice selection/speed persistence, 5 curated `FishVoiceInfo` entries, and a `generateAudioBuffer(text:) async -> AVAudioPCMBuffer?` method that calls the Fish Audio REST API (`POST https://api.fish.audio/v1/tts` with `Authorization: Bearer`, `model: s2-pro` header, JSON body with `text`, `reference_id`, `format: pcm`, `sample_rate: 24000`), receives raw PCM bytes, and converts them to `AVAudioPCMBuffer`; also add a `previewVoice(_:)` method for the settings UI
3. Modify `Tama/Sources/Voice/SpeechService.swift` — in the `enqueueUtterance(_:)` method, read `TTSProvider.active` and branch: if `.kokoro`, use existing KokoroManager path; if `.fishAudio`, call `FishAudioManager.shared.generateAudioBuffer(text:)` in an async Task, then append the resulting buffer to `bufferQueue` and call `playNextBuffer()`, with the same `utteranceDidFinish()` flow on completion or failure
4. Modify `Tama/Sources/Voice/VoiceSettingsView.swift` — add a provider picker (segmented control) at the top of the view below the voice toggle showing "Kokoro (Local)" and "Fish Audio (Cloud)"; when Fish Audio is selected, show: an API key text field (SecureField) with a Save button if no key is set, the 5 curated Fish Audio voices as selectable rows (no download needed, just tap to select), a speed slider, and an info label about emotion tag support; when Kokoro is selected, show the existing model/voice/speed UI unchanged
5. Modify `Tama/Sources/Onboarding/OnboardingView.swift` — in the `voiceStep`, after the existing Kokoro sections, add a Divider and an optional "Fish Audio (Cloud)" section with a brief description ("Higher quality with emotion control, requires API key from fish.audio"), a SecureField for API key input, a Save button, and a link to https://fish.audio; this section should be clearly marked as optional
6. Run `xcodegen generate` and then `xcodebuild -project Tama.xcodeproj -scheme Tama -configuration Debug build` to verify everything compiles; fix any Swift 6 strict concurrency issues, ensure `@MainActor` annotations are correct on all UI-touching code, and verify the new files are included in the Xcode project

# Voice Speed Slider

Add a speech speed configuration slider to the Voice Settings modal, allowing users to adjust Kokoro TTS playback speed within safe bounds.

## Analysis

### Current Architecture
- **KokoroSwift API** already supports a `speed: Float` parameter on `generateAudio()` (default `1.0`, line 172 of `KokoroTTS.swift`)
- **KokoroManager** calls `generateAudio` without passing `speed` (defaults to `1.0`) in two places:
  - `generateAudioBufferOffMain(text:context:)` — used by `SpeechService` for streaming TTS (line 354)
  - `generateAudioBuffer(text:)` — used by `VoiceSettingsView` for voice preview (line 380)
- **GenerationContext** (line 328) captures engine state for off-main-thread generation — needs `speed` added
- **UserDefaults** pattern already used for `kokoroVoiceEnabled` and `kokoroSelectedVoice`

### Speed Bounds
Based on real-world Kokoro usage research:
- **Min: 0.8** — slower than this sounds unnaturally drawn out
- **Max: 1.3** — faster than this starts sounding robotic/unintelligible  
- **Default: 1.0** — normal speed
- **Step: 0.05** — fine-grained enough for subtle adjustment

## Steps

1. In `tama/Sources/Voice/KokoroManager.swift`: Add a `@Published var voiceSpeed: Float` property with `didSet` persisting to `UserDefaults` key `"kokoroVoiceSpeed"`, defaulting to `1.0`. Add `nonisolated static let minSpeed: Float = 0.8`, `nonisolated static let maxSpeed: Float = 1.3`, and `nonisolated static let defaultSpeed: Float = 1.0` constants. Initialize `voiceSpeed` from `UserDefaults` in `init()` (line 78) using the same pattern as `voiceEnabled`/`selectedVoice`. Add `speed` to the log in `init()`.

2. In `tama/Sources/Voice/KokoroManager.swift`: Add `let speed: Float` to the `GenerationContext` struct (line 328). Update `captureGenerationContext()` (line 337) to include `speed: voiceSpeed` in the returned context.

3. In `tama/Sources/Voice/KokoroManager.swift`: Update `generateAudioBufferOffMain(text:context:)` (line 354) to pass `speed: context.speed` to `context.engine.generateAudio()`. Update the debug log to include speed value.

4. In `tama/Sources/Voice/VoiceSettingsView.swift`: Add a speed slider section between the voice list section and the footer (after line 33, before `footerSection`). Create a private computed property `speedSection` containing: a label "Speech Speed" with the current value shown as formatted text (e.g. "1.0×"), a SwiftUI `Slider` bound to `$manager.voiceSpeed` with `in: KokoroManager.minSpeed...KokoroManager.maxSpeed` and `step: 0.05`, and a reset button that sets `manager.voiceSpeed = KokoroManager.defaultSpeed`. Use the same styling conventions as existing sections (`.padding(.horizontal, 14)`, `.padding(.vertical, 8)`, system font sizes 12/10, white opacity colors). Add a `Divider().opacity(0.3).padding(.horizontal, 14)` before the speed section. Apply the same `opacity`/`allowsHitTesting` voice-enabled gating as the other sections.

5. Build the project with `xcodebuild -project Tama.xcodeproj -scheme Tama -configuration Debug build` and fix any errors. Run `swiftlint lint --config .swiftlint.yml tama/Sources/Voice/KokoroManager.swift tama/Sources/Voice/VoiceSettingsView.swift` and `swiftformat --lint --config .swiftformat tama/Sources/Voice/KokoroManager.swift tama/Sources/Voice/VoiceSettingsView.swift` to check style.

# Fish Audio WebSocket Streaming TTS

## Problem

Currently, Fish Audio TTS uses HTTP batch requests: collect a sentence → POST to `/v1/tts` → wait for full audio → play. Each round trip adds 1-2 seconds of latency. With multiple utterances queued serially, total latency compounds.

## Solution

Replace the HTTP batch approach with Fish Audio's WebSocket TTS endpoint (`wss://api.fish.audio/v1/tts/live`). This enables:
- **Pipe LLM tokens directly** to Fish Audio as they arrive
- **Receive audio chunks back in real-time** and play them immediately
- **One persistent connection** per streaming session (no per-utterance HTTP round trips)
- **Server-side buffering** with configurable `chunk_length` — Fish Audio handles sentence batching

## Fish Audio WebSocket Protocol (from official docs)

**URL**: `wss://api.fish.audio/v1/tts/live`

**Auth**: `Authorization: Bearer <API_KEY>` header + `model: s2-pro` header on connect.

**Serialization**: MessagePack (binary). All messages are msgpack-encoded dicts.

**Client → Server messages:**

1. **StartEvent** (first message after connect):
```json
{"event": "start", "request": {"text": "", "format": "pcm", "sample_rate": 24000, "chunk_length": 200, "reference_id": "<voice_id>", "latency": "balanced", "normalize": true, "prosody": {"speed": 1.0, "volume": 0}}}
```

2. **TextEvent** (send text chunks):
```json
{"event": "text", "text": "Hello, this is streaming text. "}
```

3. **FlushEvent** (force immediate synthesis):
```json
{"event": "flush"}
```

4. **StopEvent** (end session):
```json
{"event": "stop"}
```

**Server → Client messages:**

1. **AudioEvent**: `{"event": "audio", "audio": <binary PCM data>}`
2. **FinishEvent**: `{"event": "finish", "reason": "stop"|"error"}`

## Architecture

### New File: `Tama/Sources/Voice/FishAudioStreamManager.swift`

A new class that manages the WebSocket connection lifecycle and provides a simple streaming interface. Completely separate from the existing `FishAudioManager` (which keeps its HTTP API for previews and validation).

**Key responsibilities:**
- Open/close WebSocket connections
- Send start/text/flush/stop events as MessagePack
- Receive audio chunks and convert to AVAudioPCMBuffer
- Play audio chunks immediately as they arrive via the shared audio engine
- Handle connection errors and reconnection

### Modified: `Tama/Sources/Voice/SpeechService.swift`

When Fish Audio is the active provider, the streaming path changes fundamentally:
- `beginStreaming()` opens the WebSocket connection and sends StartEvent
- `feedChunk()` sends each LLM token directly as a TextEvent (no sentence buffering needed for Fish Audio — the server handles it via `chunk_length`)
- `flushBuffer()` sends a FlushEvent
- `finishStreaming()` sends StopEvent and waits for FinishEvent
- Audio chunks from the WebSocket are played immediately as they arrive

The Kokoro path remains unchanged — it still uses the existing sentence splitting + local generation.

### MessagePack

Rather than adding a dependency, implement a minimal MessagePack encoder (~50 lines) that handles the subset we need: maps, strings, binary data, integers, floats, bools, nil. The messages are simple flat dicts.

For decoding received messages, we only need to parse audio events (map with "event" string and "audio" binary).

### Playback

Audio chunks from the WebSocket are raw PCM (16-bit signed, 24kHz mono). Each chunk is converted to an AVAudioPCMBuffer and scheduled on the playerNode immediately. The audio engine stays running throughout the session, so there's no startup latency between chunks.

This eliminates the ordered slot system for Fish Audio (no longer needed — chunks arrive in order from the WebSocket). The slot system remains for Kokoro only.

## Risks

- **WebSocket disconnection mid-stream** — need graceful reconnection or fallback to HTTP
- **Audio glitching** — if chunks arrive too fast or too slow, playback may stutter. The `chunk_length` parameter controls this tradeoff.
- **`chunk_length` tuning** — too small = choppy/unnatural speech, too large = latency. The pipecat reference uses default (300). We'll start with 200 for lower latency.

## Steps

1. Create a minimal MessagePack encoder/decoder in `Tama/Sources/Voice/MsgPack.swift` supporting maps, strings, binary data, integers, floats, bools, and nil
2. Create `Tama/Sources/Voice/FishAudioStreamManager.swift` — WebSocket lifecycle (connect with auth headers, send start/text/flush/stop events as msgpack, receive and decode audio/finish events, convert PCM chunks to AVAudioPCMBuffer)
3. Add a Fish Audio WebSocket streaming path in `SpeechService.swift` — when Fish Audio is active, `beginStreaming` opens the WebSocket, `feedChunk` sends TextEvents directly (bypassing sentence splitting), `flushBuffer` sends FlushEvent, `finishStreaming` sends StopEvent; audio chunks from the WebSocket are played immediately via the existing audio engine
4. Wire `FishAudioStreamManager` audio callbacks into `SpeechService` playback — received PCM chunks are converted to buffers and scheduled on the playerNode in real-time, with `pendingUtterances` and `streamCompletion` tracking based on the WebSocket finish event
5. Add `FishAudioStreamManager` to `project.yml` sources (auto via directory), regenerate Xcode project, and verify the build compiles
6. Test end-to-end: voice prompt → LLM streams tokens → tokens piped to Fish Audio WebSocket → audio chunks play in real-time, verify latency improvement and audio quality

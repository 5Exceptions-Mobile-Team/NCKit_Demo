# NCKit Sample — iOS

> Reference iOS app for the **NCKit** noise-cancellation framework.
> Built by [**5Exceptions**](https://5exceptions.com).

A clean, copy-paste-friendly demo of how to integrate
[**NCKit**](https://github.com/5Exceptions-Mobile-Team/NCKit) into a SwiftUI app.
Use it as a working reference, or as a starting template for your own product.

---

## What's inside

| Tab | What it shows | NCKit APIs used |
|-----|---------------|-----------------|
| **Microphone** | Real-time mic noise cancellation, A/B recording, live meters, processing stats | `NCKitProcessor`, `NCKitModelLocator` |
| **Video** | Pick a video, denoise its audio, A/B compare, save to Photos | `NCKitFileProcessor`, `NCKitAudioNormalizer`, `NCKitProcessor` |
| **How to Use** | Six copy-paste snippets that mirror exactly what the other tabs do | every public API in NCKit |

Visual design matches the [NCKit documentation site](https://docs.nckit.io) — dark
default with glassmorphic surfaces and a cyan → violet → pink accent.

---

## Requirements

- Xcode **15.2** or newer
- iOS **16.0** target (physical device recommended; mic & Photos features need a real device for full testing)
- Swift **5.9+**
- arm64 (device) or arm64 simulator
- Apple Developer team for code signing

---

## Project layout

```
KrispyiOS/
├── NCKit.xcframework/          ← Drop-in binary framework (the SDK)
├── NCKitSample.xcodeproj
└── NCKitSample/
    ├── NCKitSampleApp.swift    ← Entry point, dark theme + accent
    ├── Info.plist
    ├── Audio/
    │   ├── AudioEngine.swift       ← AVAudioEngine + NCKitProcessor (real-time)
    │   ├── VideoProcessor.swift    ← NCKitFileProcessor (offline file)
    │   ├── WaveformGenerator.swift
    │   └── WavWriter.swift
    └── UI/
        ├── Theme.swift              ← AI-transparent glass palette + helpers
        ├── ContentView.swift        ← Tab bar + 5Exceptions footer
        ├── MicrophoneView.swift
        ├── VideoImportView.swift
        ├── ComparisonPlayerView.swift
        ├── HowToUseView.swift
        └── Helpers/
            └── MediaPickerWrappers.swift
```

No CocoaPods, no SwiftPM dependencies — the app links **only** `NCKit.xcframework`.

---

## Getting started

```bash
git clone https://github.com/5Exceptions-Mobile-Team/NCKit_Demo.git
cd NCKit_Demo/KrispyiOS
open NCKitSample.xcodeproj
```

1. Select the **NCKitSample** scheme.
2. Pick your development team in **Signing & Capabilities**.
3. Connect a device and hit **⌘R**.

That's it — no `pod install`, no `xcframework` build step, no model download.
The `.xcframework` already embeds the NCKit model.

---

## How to integrate NCKit in your own app

The whole point of this sample is to make the integration obvious. Here's the
30-second version — see the **How to Use** tab in the app for the full set.

### 1. Add the framework

Drag `NCKit.xcframework` into Xcode → **Frameworks, Libraries, and Embedded Content**
→ choose **Embed & Sign**.

### 2. Locate the bundled model

```swift
import NCKit

let modelURL = try NCKitModelLocator.modelTarGzURL()
```

### 3. Create the processor once

```swift
let processor = try NCKitProcessor(
    modelURL: modelURL,
    attenLimDb: 100,      // 100 = unlimited
    postFilterBeta: 0     // 0 = off (CLI default)
)
```

### 4. Real-time mic processing

Feed exactly `processor.frameLength` samples (480 = 10 ms @ 48 kHz mono).
Call from a single serial queue.

```swift
let hop = processor.frameLength
var input  = [Float](repeating: 0, count: hop)
var output = [Float](repeating: 0, count: hop)

input.withUnsafeMutableBufferPointer { ib in
    output.withUnsafeMutableBufferPointer { ob in
        processor.processFrame(
            input:  ib.baseAddress!,
            output: ob.baseAddress!
        )
    }
}
```

### 5. Offline file processing

```swift
try NCKitFileProcessor.processFile(
    inputURL:  noisyFile,
    outputURL: cleanFile,
    processor: processor
)
```

### 6. Loudness normalization

After denoising, speech can sound quieter. Apply a one-shot speech-gated
makeup gain:

```swift
var samples: [Float] = readSamples()

NCKitAudioNormalizer.applySpeechGatedMakeupGain(
    &samples,
    sampleRate: 48_000,
    targetRmsDbfs: -18
)
```

### 7. Typed error handling

Every NCKit operation throws `NCKitError` — a `Sendable` enum.

```swift
do {
    let processor = try NCKitProcessor(modelURL: modelURL)
} catch NCKitError.missingModel(let name) {
    print("Model not embedded: \(name)")
} catch NCKitError.libraryInit {
    print("Engine init failed")
} catch {
    print(error)
}
```

---

## Permissions

The app declares the minimum Info.plist keys you'll need in your own app:

- `NSMicrophoneUsageDescription` — for live mic NC
- `NSPhotoLibraryUsageDescription` — to import videos
- `NSPhotoLibraryAddUsageDescription` — to save the enhanced result
- `UIBackgroundModes` → `audio` — to keep processing while in background

All audio runs **entirely on-device**. Nothing leaves the phone.

---

## Performance

Measured on iPhone 15 Pro (arm64):

| Operation | Time |
|-----------|------|
| Model load | ~200 ms (cold), then cached |
| Per-frame denoise (10 ms hop) | ~0.4 ms |
| File processing | ~5–10× real-time |

The model is loaded once per `NCKitProcessor` instance. Reuse the processor —
don't recreate it per chunk.

---

## Privacy

- All inference runs locally with the bundled NCKit ONNX model.
- No network calls, no analytics, no telemetry.
- Audio buffers never leave the device.
- Recordings are stored in the app's temp directory and shared via `ShareLink`
  only if the user taps the share button.

---

## Troubleshooting

**Black screen on launch / model fails to load**
The xcframework must be embedded (not just linked). Confirm
*Embed & Sign* under **Frameworks, Libraries, and Embedded Content**.

**No audio on simulator**
Simulator microphone input depends on macOS permissions. Test on a device for
realistic behaviour.

**"Microphone Access" alert keeps appearing**
You denied the permission. Tap **Open Settings** and re-enable it for
*NCKit Sample*.

**Video saved but no audio**
Make sure the source video has an audio track. The sample throws
`ProcessingError.noAudioTrack` for video-only files.

---

## Links

- **NCKit documentation** — [docs.nckit.io](https://docs.nckit.io)
- **NCKit framework repo** — [github.com/5Exceptions-Mobile-Team/NCKit](https://github.com/5Exceptions-Mobile-Team/NCKit)
- **This sample** — [github.com/5Exceptions-Mobile-Team/NCKit_Demo](https://github.com/5Exceptions-Mobile-Team/NCKit_Demo)
- **5Exceptions** — [5exceptions.com](https://5exceptions.com)
- **Sales / licensing** — [sdk@5exceptions.com](mailto:sdk@5exceptions.com)

---

## License

The sample app source in this repository is released under the **MIT License**
so you can copy it freely into your own projects.

`NCKit.xcframework` is distributed under a separate commercial license.
Contact [sdk@5exceptions.com](mailto:sdk@5exceptions.com) for production
licensing terms.

---

<p align="center">
  Built by <a href="https://5exceptions.com"><b>5Exceptions</b></a> · Powered by NCKit
</p>

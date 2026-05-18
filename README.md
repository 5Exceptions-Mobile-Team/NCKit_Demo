# NCKit Sample — iOS

Reference iOS app for the **NCKit** noise-cancellation SDK.

A clean, copy-paste-friendly demo of how to integrate NCKit into a SwiftUI app. Use it as a working reference or as a starting template for your own product.

---

## What's inside

| Tab | What it shows | NCKit APIs used |
|-----|---------------|-----------------|
| **Audio** | Real-time mic noise cancellation, A/B recording, live meters | `NCKitProcessor`, `NCKitModelLocator` |
| **Video** | Pick a video, denoise its audio, A/B compare, save to Photos | `NCKitFileProcessor`, `NCKitAudioNormalizer`, `NCKitProcessor` |
| **How to Use** | Copy-paste snippets that mirror what the other tabs do | every public API in NCKit |

Visual design matches the [NCKit documentation site](https://docs.nckit.io) — dark theme with glassmorphic surfaces.

---

## Requirements

- Xcode **15.2** or newer
- iOS **16.0** target (physical device recommended for mic & Photos)
- Swift **5.9+**
- arm64 (device) or arm64 simulator
- Apple Developer team for code signing

---

## Project layout

```
KrispyiOS/
├── NCKitSample.xcodeproj
└── NCKitSample/
    ├── NCKitSampleApp.swift
    ├── Audio/
    │   ├── AudioEngine.swift
    │   ├── VideoProcessor.swift
    │   └── …
    └── UI/
        ├── ContentView.swift
        ├── AudioView.swift
        ├── VideoImportView.swift
        └── HowToUseView.swift
```

NCKit is added via **Swift Package Manager** (tag `1.0.1`). No CocoaPods required.

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

The SDK is resolved from the NCKit git package — no manual xcframework download.

---

## How to integrate NCKit in your own app

See the **How to Use** tab in the app, or the [documentation](https://docs.nckit.io/docs/getting-started/quick-start).

### Quick steps

1. Add package: `https://github.com/5Exceptions-Mobile-Team/NCKit.git` → version **1.0.1**
2. **Embed & Sign** on your app target
3. `import NCKit` and call `NCKitModelLocator.modelTarGzURL()` → `NCKitProcessor` → `NCKitFileProcessor`

---

## Permissions

| Key | When needed |
|-----|-------------|
| `NSMicrophoneUsageDescription` | Live mic NC |
| `NSPhotoLibraryUsageDescription` | Import videos |
| `NSPhotoLibraryAddUsageDescription` | Save enhanced video |

All audio runs **entirely on-device**.

---

## Links

- **Documentation** — [docs.nckit.io](https://docs.nckit.io)
- **NCKit SDK** — [GitHub](https://github.com/5Exceptions-Mobile-Team/NCKit)

---

## License

Sample app source is **MIT License** — copy freely into your projects.

`NCKit.xcframework` is distributed under a separate commercial license. See [License](https://docs.nckit.io/docs/legal/license).

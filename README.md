# NCKit Sample

Reference SwiftUI app for the [NCKit](https://github.com/5Exceptions-Mobile-Team/NCKit) iOS SDK.

## Requirements

- Xcode 15.2+
- iOS 15.0+
- Physical device recommended (microphone, Photos)

## Run

```bash
git clone https://github.com/5Exceptions-Mobile-Team/NCKit_Demo.git
cd NCKit_Demo
open NCKitSample.xcodeproj
```

1. Scheme: **NCKitSample**
2. Set your **Signing** team
3. Build & Run (⌘R)

NCKit is pulled via SPM from `https://github.com/5Exceptions-Mobile-Team/NCKit.git` (tag **1.0.1**).

## What the app demonstrates

| Tab | APIs |
|-----|------|
| Audio | `NCKitProcessor`, `NCKitModelLocator` |
| Video | `NCKitFileProcessor`, `NCKitAudioNormalizer` |
| How to Use | In-app integration snippets |

## Permissions

- `NSMicrophoneUsageDescription` — live mic
- `NSPhotoLibraryUsageDescription` / `NSPhotoLibraryAddUsageDescription` — import and save video

## Docs
- [SDK repo](https://github.com/5Exceptions-Mobile-Team/NCKit)

Sample source: MIT. `NCKit.xcframework`: see [license](https://docs.nckit.io/docs/legal/license).

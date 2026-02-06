# Quran Accessibility App

**Voice-first Quran recitation app for blind users.**

Built with Flutter, C++ native audio engine, and full TalkBack/VoiceOver support.

---

## Features

- 🎧 **Audio Playback** — Gapless Ayah-level recitation with sub-10ms seek
- 🔁 **Memorization** — Repeat loops with configurable count and pause intervals
- 🎤 **Voice Control** — Natural speech commands ("Play Surah Rahman")
- 📥 **Offline Mode** — Download Surahs for offline listening
- ♿ **Accessibility** — 100% screen reader compatible, 48dp touch targets

---

## Architecture

```
Native Audio Engine (C++/Oboe)
        ↓
Playback Orchestration (Dart)
        ↓
Voice Intent Router
        ↓
Download System
        ↓
UI Layer (Flutter)
```

---

## Prerequisites

- Flutter SDK 3.16+
- Android Studio (for Android)
- Xcode 15+ (for iOS)
- NDK 25+ (for native C++ build)

---

## Project Structure

```
lib/
├── main.dart                    # App entry point
├── screens/
│   ├── surah_list_screen.dart   # Surah navigation
│   ├── player_screen.dart       # Playback controls
│   └── download_screen.dart     # Download manager
├── widgets/
│   ├── playback_controls.dart   # Reusable buttons
│   ├── voice_trigger_button.dart
│   └── transcript_overlay.dart
├── services/
│   ├── playback_state_controller.dart
│   ├── playback_command_queue.dart
│   ├── repeat_orchestrator.dart
│   ├── accessibility_announcer.dart
│   ├── audio_focus_manager.dart
│   ├── playback_persistence.dart
│   ├── speech_capture.dart
│   ├── intent_extractor.dart
│   ├── confidence_arbiter.dart
│   ├── speech_service.dart
│   ├── voice_intent_router.dart
│   ├── download_queue.dart
│   ├── batch_downloader.dart
│   ├── extraction_sandbox.dart
│   ├── download_integrity.dart
│   ├── storage_manager.dart
│   ├── reciter_manager.dart
│   └── download_service.dart
├── models/
│   ├── surah.dart
│   ├── ayah.dart
│   └── recitation_audio.dart
└── database/
    ├── database_helper.dart
    └── schema_v3.dart

native/
├── CMakeLists.txt
├── audio_engine/
│   ├── audio_engine.h
│   └── audio_engine.cpp
├── ffi_bridge/
│   ├── ffi_exports.cpp
│   └── audio_engine_ffi.dart
├── phonetic_matcher/
│   ├── fuzzy_matcher.h
│   └── fuzzy_matcher.cpp
└── integrity_validator/
    ├── checksum.h
    └── checksum.cpp
```

---

## Build Instructions

### 1. Clone Repository

```bash
git clone https://github.com/Anaskhan6/quran-accessibility-app.git
cd quran-accessibility-app
```

### 2. Install Dependencies

```bash
flutter pub get
```

### 3. Build for Android

```bash
# Debug build
flutter build apk --debug

# Release build
flutter build apk --release

# Install on device
flutter install
```

### 4. Build for iOS

```bash
cd ios && pod install && cd ..
flutter build ios --release
```

### 5. Run Development Server

```bash
flutter run
```

---

## Native Build (C++)

The native audio engine requires NDK configuration.

### Android (CMake)

The `android/app/build.gradle.kts` already includes:

```kotlin
externalNativeBuild {
    cmake {
        path = file("../../native/CMakeLists.txt")
    }
}
```

NDK will compile automatically during `flutter build`.

### Manual CMake Build

```bash
cd native
mkdir build && cd build
cmake ..
make
```

---

## Testing

### Run All Tests

```bash
flutter test
```

### Run Specific Test

```bash
flutter test test/database_test.dart
flutter test test/gapless_transition_test.dart
flutter test test/repeat_determinism_test.dart
```

### Accessibility Testing

1. Enable TalkBack (Android) or VoiceOver (iOS)
2. Navigate all screens with screen reader
3. Verify all actions announce correctly

---

## Voice Commands

| Command | Action |
|---------|--------|
| "Play Surah Rahman" | Start playback |
| "Pause" | Pause playback |
| "Repeat Ayah 5" | Repeat current Ayah |
| "Repeat 10 times" | Set repeat count |
| "Next Ayah" | Skip forward |
| "Previous Ayah" | Skip backward |
| "Faster" / "Slower" | Adjust speed |
| "Stop repeat" | Exit repeat mode |

---

## Configuration

### Storage Quota

Default: 2GB. Modify in `storage_manager.dart`:

```dart
StorageConfig(
  quotaBytes: 2 * 1024 * 1024 * 1024,
  warningThreshold: 0.8,
)
```

### Reciters

Pre-configured reciters in `reciter_manager.dart`:

- Abdul Basit (default)
- Mishary Rashid
- Husary

---

## Accessibility Compliance

- WCAG 2.1 Level AA
- All interactive elements have semantic labels
- Minimum 48dp touch targets
- Voice command parity for all actions
- Audio feedback for state changes

---

## License

MIT License

---

## Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/name`)
3. Commit changes (`git commit -m 'Add feature'`)
4. Push to branch (`git push origin feature/name`)
5. Open Pull Request

---

## Acknowledgments

- [EveryAyah](https://everyayah.com) — Audio recitations
- [Tanzil](https://tanzil.net) — Verified Quran text
- [Oboe](https://github.com/google/oboe) — Low-latency audio

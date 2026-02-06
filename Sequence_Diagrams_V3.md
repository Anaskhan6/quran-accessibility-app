# Sequence Diagrams V3 — Corrected Architecture

## 1. Complete Playback Flow with Error Handling

```mermaid
sequenceDiagram
    participant User
    participant UI
    participant AudioEngine
    participant CPP as C++ Native (Oboe)
    participant DB as Database
    participant Storage
    participant API

    User->>UI: Voice Command / Tap Play
    UI->>AudioEngine: Initialize Playback(surah_id, ayah_number)
    
    AudioEngine->>DB: Fetch Ayah + Recitation Metadata
    DB-->>AudioEngine: Ayah Info + Audio Path
    
    AudioEngine->>Storage: Check Local Audio File
    
    alt File Exists Locally
        Storage-->>AudioEngine: Local Path
        AudioEngine->>CPP: Validate Audio Checksum
        
        alt Checksum Valid
            CPP-->>AudioEngine: Valid
            AudioEngine->>CPP: StartPlayback(file_path)
            Note over CPP: Oboe Native Audio<br/>Sub-10ms latency
            CPP-->>UI: Playback State: PLAYING
            UI-->>User: Audio Feedback + Haptic
            
            Note over AudioEngine,CPP: Preload next Ayah at 80% progress
            AudioEngine->>DB: Get Next Ayah Audio Path
            AudioEngine->>CPP: PreloadBuffer(next_file_path)
            
        else Checksum Invalid
            CPP-->>AudioEngine: Corrupted
            AudioEngine->>DB: Log Error(AUDIO_CORRUPTED, ayah_id)
            AudioEngine->>Storage: Delete Corrupted File
            AudioEngine->>API: Request Fresh Audio URL
            API-->>AudioEngine: Audio URL
            AudioEngine->>Storage: Download + Save
            AudioEngine->>CPP: Validate New Checksum
            AudioEngine->>CPP: StartPlayback(file_path)
        end
        
    else File Not Found - Stream
        Storage-->>AudioEngine: Not Found
        AudioEngine->>API: Fetch Streaming URL
        
        alt Network Available
            API-->>AudioEngine: Stream URL
            
            Note over AudioEngine,CPP: Streaming uses Dart just_audio<br/>NOT C++ Oboe (different track)
            AudioEngine->>UI: Stream via just_audio
            UI-->>User: Audio Feedback "Streaming..."
            
            Note over AudioEngine,Storage: Cache in background
            par Background Download
                AudioEngine->>Storage: Save Audio File
                AudioEngine->>CPP: Validate Checksum
                CPP-->>DB: Update RecitationAudio.local_audio_path
            end
            
        else Network Unavailable
            API-->>AudioEngine: Network Error
            AudioEngine->>DB: Log Error(NETWORK_FAILED)
            AudioEngine-->>UI: Error State
            UI-->>User: "Offline mode required. Download this Surah?"
            
            User->>UI: Download Now / Cancel
            alt Download Now
                UI->>AudioEngine: Queue Batch Download
            else Cancel
                UI-->>User: Return to Surah List
            end
        end
    end
```

---

## 2. Batch ZIP Download Flow (CORRECTED)

```mermaid
sequenceDiagram
    participant User
    participant UI
    participant DownloadManager
    participant Storage
    participant API
    participant CPP as C++ Integrity
    participant DB as Database

    User->>UI: Download Surah 2 (Al-Baqarah)
    UI->>DownloadManager: EnqueueSurah(surah_id=2, reciter_id=1)
    
    DownloadManager->>Storage: Check Available Space
    Storage-->>DownloadManager: 500 MB available
    
    DownloadManager->>API: Estimate Download Size
    Note over API: Server returns metadata:<br/>surah_2_reciter_1.zip<br/>Size: 14.5 MB
    API-->>DownloadManager: Metadata (size, checksum)
    
    alt Sufficient Space
        DownloadManager-->>UI: Download Starting
        UI-->>User: "Downloading Surah Al-Baqarah ZIP..."
        
        DownloadManager->>API: Request "surah_2_reciter_1.zip"
        API-->>DownloadManager: Stream Binary Data
        
        loop Stream Chunks
            API-->>DownloadManager: Chunk (1 MB)
            DownloadManager->>Storage: Append to "temp_2.zip"
            DownloadManager-->>UI: Progress (N MB / 14.5 MB)
            UI-->>User: Progress Bar Update
        end
        
        DownloadManager->>CPP: ValidateZipChecksum("temp_2.zip", expected_checksum)
        
        alt Checksum Invalid
            CPP-->>DownloadManager: False (Corrupted)
            DownloadManager->>Storage: Delete "temp_2.zip"
            DownloadManager->>DB: Log Error(DOWNLOAD_CORRUPTED)
            DownloadManager-->>UI: Error
            UI-->>User: "Download corrupted. Retry?"
            
            User->>UI: Retry
            DownloadManager->>API: Re-request ZIP (resume if supported)
            
        else Checksum Valid
            CPP-->>DownloadManager: True (Intact)
            
            DownloadManager->>CPP: ExtractZip("temp_2.zip", "/audio/reciter_1/2/")
            Note over CPP: C++ native unzip<br/>Fast decompression<br/>Validates each file
            
            loop For Each Extracted Ayah
                CPP->>CPP: Validate Audio File Checksum
                alt Audio Valid
                    CPP->>DB: Insert RecitationAudio(ayah_id, local_path, checksum)
                else Audio Corrupted
                    CPP->>DB: Log Error(EXTRACTED_FILE_CORRUPTED, ayah_id)
                end
            end
            
            CPP-->>DownloadManager: Extraction Complete (286 files)
            
            DownloadManager->>Storage: Delete "temp_2.zip"
            DownloadManager->>DB: UPDATE Downloads SET downloaded=1, zip_checksum=?
            DownloadManager-->>UI: Success
            UI-->>User: "Surah Al-Baqarah downloaded. 286 Ayahs ready offline."
        end
        
    else Insufficient Space
        DownloadManager-->>UI: Storage Full (need 14.5 MB, have 5 MB)
        UI-->>User: "Free up 10 MB to download this Surah."
        UI->>UI: Show Cleanup Options
        
        User->>UI: Delete Old Downloads
        UI->>DownloadManager: ClearCache(least_recently_used)
        DownloadManager->>Storage: Delete Unused Surah ZIPs
        Storage-->>DownloadManager: Space Freed (50 MB)
        DownloadManager-->>UI: Retry Download?
        
        User->>UI: Yes
        UI->>DownloadManager: EnqueueSurah(surah_id=2)
    end
    
    Note over User,DB: Edge Case: Download Interrupted (Phone call, app killed)
    
    User->>UI: Force Close App (or Network Lost)
    DownloadManager->>DB: Save Download Progress (partial: 8.2 MB / 14.5 MB)
    
    Note over User,DB: Later... User reopens app
    
    User->>UI: Reopen App
    UI->>DB: Check Incomplete Downloads
    DB-->>UI: Partial Download Found (surah_2, 8.2 MB)
    UI-->>User: "Resume download of Surah Al-Baqarah?"
    
    User->>UI: Yes
    UI->>DownloadManager: ResumeDownload(surah_2)
    DownloadManager->>API: Request with Range Header (bytes=8600000-)
    Note over API: HTTP 206 Partial Content<br/>Resume from byte offset
    API-->>DownloadManager: Stream Remaining Data (6.3 MB)
```

---

## 3. Repeat Loop Flow with State Preservation

```mermaid
sequenceDiagram
    participant User
    participant UI
    participant RepeatEngine
    participant AudioEngine
    participant CPP as C++ Oboe
    participant DB as Database
    participant Timer

    User->>UI: Set Repeat Range (Voice: "Repeat Ayah 5 to 10, 7 times")
    UI->>RepeatEngine: ConfigureLoop(mode=RANGE, start=5, end=10, count=7)
    
    RepeatEngine->>DB: Save Repeat State (UserProgress table)
    DB-->>RepeatEngine: State Saved
    
    RepeatEngine->>UI: Announce Config
    UI-->>User: "Repeating Ayah 5 to 10 of Surah Baqarah, 7 times"
    
    loop For each repeat iteration (1 to 7)
        Note over RepeatEngine: Iteration N of 7
        
        loop For each Ayah in range (5 to 10)
            RepeatEngine->>AudioEngine: PlayAyah(surah_id, ayah_num)
            AudioEngine->>DB: Get Audio Path
            DB-->>AudioEngine: local_audio_path
            AudioEngine->>CPP: StartPlayback(path)
            
            Note over CPP: Native Oboe playback<br/>Gapless transition<br/><10ms seek
            
            CPP-->>UI: Playback State: REPEATING
            UI-->>User: Audio + Visual Indicator "Ayah 5/10, Repeat 1/7"
            
            CPP-->>AudioEngine: Playback Ended
            AudioEngine-->>RepeatEngine: Ayah Completed
        end
        
        RepeatEngine->>DB: Update repeat_current = N
        
        alt More Repeats Remaining (N < 7)
            RepeatEngine->>Timer: Start Pause Interval (2 seconds)
            
            loop Countdown
                Timer-->>UI: Countdown Tick (3...2...1...)
                UI-->>User: Voice "Repeating in 3...2...1..."
            end
            
            Timer-->>RepeatEngine: Resume Signal
            Note over RepeatEngine: Continue to next iteration
            
        else All Repeats Complete (N == 7)
            RepeatEngine->>DB: Clear Repeat State (repeat_mode = NULL)
            RepeatEngine-->>UI: Repeat Completed
            UI-->>User: "Repeat completed. May Allah bless your memorization."
        end
    end
    
    Note over User,DB: Edge Case: App Closed During Repeat
    
    User->>UI: Force Close App
    UI->>DB: Persist Current State
    DB->>DB: Save (repeat_mode=RANGE, repeat_current=3, last_ayah=7)
    
    Note over User,DB: Later... User reopens app
    
    User->>UI: Reopen App
    UI->>DB: Restore UserProgress
    DB-->>UI: Found: repeat_mode=RANGE, current_iteration=3/7, at Ayah 7
    UI-->>User: "Continue repeating Ayah 5-10? (Iteration 3 of 7)"
    
    User->>UI: "Yes" (Voice or Tap)
    UI->>RepeatEngine: Resume from iteration 3, Ayah 8
    RepeatEngine->>AudioEngine: Play Ayah 8
    
    User->>UI: "No, cancel"
    UI->>DB: Clear Repeat State
    DB-->>UI: Cleared
    UI-->>User: "Repeat cancelled"
```

---

## 4. Voice Command with C++ Phonetic Matching

```mermaid
sequenceDiagram
    participant User
    participant UI
    participant VAD as Voice Activity Detection
    participant STT as Speech-to-Text
    participant Parser as Intent Parser
    participant CPP as C++ Phonetic Matcher
    participant AudioEngine
    participant DB as Database

    User->>UI: Speaks "Play Juz 3"
    
    UI->>VAD: Detect Voice Activity
    VAD-->>UI: Speech Detected
    
    Note over UI,AudioEngine: Duck Quran audio (C++ Oboe)<br/>to 30% via native mixer
    UI->>AudioEngine: DuckAudio(0.3)
    AudioEngine->>CPP: SetVolume(30%)
    
    UI->>STT: Transcribe Speech
    STT-->>UI: Text: "play juz three"
    STT-->>UI: Confidence: 0.88 (High)
    
    UI->>Parser: ParseIntent(text, confidence)
    Parser-->>Parser: Extract Intent: PlayJuzIntent
    Parser-->>Parser: Extract Parameter: juz_number=3
    
    Parser->>DB: Get Juz Ayah Range
    DB-->>Parser: JuzMap [(surah=2, start=253, end=286), (surah=3, start=1, end=92)]
    
    Parser-->>UI: Action: PlayJuzRange(juz=3)
    
    alt High Confidence (>0.85)
        UI->>AudioEngine: PlayJuz(3)
        AudioEngine->>DB: Fetch First Ayah (Surah 2, Ayah 253)
        DB-->>AudioEngine: Audio Path
        AudioEngine->>CPP: StartPlayback(path)
        
        UI->>AudioEngine: RestoreVolume(1.0)
        AudioEngine->>CPP: SetVolume(100%)
        
        UI-->>User: "Playing Juz 3, starting from Surah Al-Baqarah, Ayah 253"
        CPP-->>User: Begin Playback
        
    else Medium Confidence (0.5-0.85)
        UI-->>User: "Did you mean play Juz 3?"
        User->>UI: "Yes" / "No"
        alt Confirmed
            UI->>AudioEngine: PlayJuz(3)
        else Rejected
            UI-->>User: "Please try again"
            UI->>AudioEngine: RestoreVolume(1.0)
        end
        
    else Low Confidence (<0.5)
        UI-->>User: "I didn't understand. Try: Play Juz [number]"
        UI->>AudioEngine: RestoreVolume(1.0)
    end
```

---

## 5. Audio Engine Separation (Oboe vs just_audio)

```mermaid
sequenceDiagram
    participant User
    participant UI
    participant QuranTrack as Quran Track (C++ Oboe)
    participant UITrack as UI Track (Dart just_audio)
    participant AudioFocus as Android AudioFocus Manager

    Note over User,AudioFocus: Scenario 1: Quran Playback + UI Earcon
    
    User->>UI: Play Surah
    UI->>QuranTrack: StartPlayback()
    QuranTrack->>AudioFocus: Request AUDIOFOCUS_GAIN
    AudioFocus-->>QuranTrack: Granted
    QuranTrack-->>User: Recitation Audio (100%)
    
    Note over UI: User taps a button
    UI->>UITrack: Play Earcon Sound (beep.mp3)
    UITrack->>AudioFocus: Request AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK
    AudioFocus->>QuranTrack: onAudioFocusChange(LOSS_TRANSIENT_CAN_DUCK)
    QuranTrack->>QuranTrack: Duck to 70% volume
    
    UITrack-->>User: Beep Sound (100%)
    UITrack->>AudioFocus: Abandon Focus
    AudioFocus->>QuranTrack: onAudioFocusChange(GAIN)
    QuranTrack->>QuranTrack: Restore to 100% volume
    
    Note over User,AudioFocus: Scenario 2: TalkBack Interruption
    
    User->>UI: Activate TalkBack (accessibility)
    UI->>UITrack: TalkBack TTS Output
    UITrack->>AudioFocus: Request AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK
    AudioFocus->>QuranTrack: onAudioFocusChange(LOSS_TRANSIENT_CAN_DUCK)
    QuranTrack->>QuranTrack: Duck to 30% (lower for speech)
    
    UITrack-->>User: TalkBack Speech
    UITrack->>AudioFocus: Abandon Focus
    AudioFocus->>QuranTrack: onAudioFocusChange(GAIN)
    QuranTrack->>QuranTrack: Ramp to 100% (500ms fade)
    
    Note over User,AudioFocus: Scenario 3: Phone Call
    
    AudioFocus->>QuranTrack: onAudioFocusChange(LOSS)
    QuranTrack->>QuranTrack: Pause Playback + Save Position
    QuranTrack->>UI: Notify State Change (PAUSED_INTERRUPTED)
    UI-->>User: Show Notification "Paused for call"
    
    Note over User: Call ends
    
    AudioFocus->>QuranTrack: onAudioFocusChange(GAIN)
    QuranTrack->>QuranTrack: Resume from Saved Position
    QuranTrack->>UI: Notify State Change (PLAYING)
    UI-->>User: Resume Playback
```

---

## 6. Multi-Translation Support (Normalized Schema)

```mermaid
sequenceDiagram
    participant User
    participant UI
    participant DB as Database
    participant AudioEngine

    Note over User,AudioEngine: User has English (Sahih) active
    
    User->>UI: Play Surah 1, Ayah 1
    UI->>DB: Fetch Ayah with Translation
    
    DB->>DB: Query:
    Note over DB: SELECT a.text_arabic, at.text_content<br/>FROM Ayah a<br/>LEFT JOIN AyahTranslation at<br/>  ON a.id = at.ayah_id<br/>WHERE a.surah_id = 1<br/>  AND a.ayah_number = 1<br/>  AND at.translation_id = 2
    
    DB-->>UI: {arabic: "بِسْمِ ٱللَّهِ...", translation: "In the name of Allah..."}
    UI-->>User: Display + TTS Read Translation
    
    Note over User,AudioEngine: User switches to Urdu translation
    
    User->>UI: Voice: "Switch to Urdu translation"
    UI->>DB: UPDATE UserProgress SET active_translation_id = 3
    DB-->>UI: Updated
    
    Note over UI,DB: NO UPDATE of 6,236 Ayah rows!<br/>Just change user preference
    
    UI->>DB: Fetch Same Ayah (with new translation_id)
    
    DB->>DB: Query:
    Note over DB: Same query structure,<br/>but translation_id = 3 (Urdu)
    
    DB-->>UI: {arabic: "بِسْمِ ٱللَّهِ...", translation: "اللہ کے نام سے..."}
    UI-->>User: Display + TTS Read Urdu Translation
    
    Note over User,AudioEngine: Instant switch, no data migration
```

---

## 7. State Machine Transitions (Updated)

```mermaid
stateDiagram-v2
    [*] --> IDLE
    
    IDLE --> LOADING: User plays Surah/Juz
    LOADING --> PLAYING: Audio ready (local)
    LOADING --> STREAMING: Audio ready (remote)
    LOADING --> ERROR: Load failed
    
    PLAYING --> PAUSED: User pauses
    PLAYING --> REPEATING: Repeat mode active
    PLAYING --> STOPPED: User stops
    PLAYING --> INTERRUPTED: Phone call / Focus lost
    
    STREAMING --> PLAYING: Cached locally
    STREAMING --> ERROR: Network lost
    
    PAUSED --> PLAYING: User resumes
    PAUSED --> STOPPED: User stops
    
    REPEATING --> PAUSED: Pause interval
    PAUSED --> REPEATING: Resume repeat
    REPEATING --> PLAYING: Repeat completed
    REPEATING --> STOPPED: User cancels repeat
    
    INTERRUPTED --> PLAYING: Focus regained
    INTERRUPTED --> STOPPED: User cancels
    
    ERROR --> IDLE: Reset
    ERROR --> LOADING: Retry
    
    STOPPED --> IDLE: Cleanup
    
    note right of LOADING
        - Fetch metadata from DB
        - Check local vs remote
        - Validate checksums
    end note
    
    note right of PLAYING
        - C++ Oboe native playback
        - <10ms seek latency
        - Preload next Ayah buffer
    end note
    
    note right of STREAMING
        - Dart just_audio
        - Progressive download
        - Background caching
    end note
    
    note right of REPEATING
        - Loop active
        - Track iteration count
        - Configurable pause intervals
    end note
    
    note right of INTERRUPTED
        - Save exact position
        - Preserve repeat state
        - Wait for audio focus
    end note
```

---

## Performance Metrics (With Corrections)

### Critical Path Latencies

| Operation | Target | Flutter/Dart | C++ Native | Improvement |
|-----------|--------|--------------|------------|-------------|
| Ayah seek (Oboe) | <10ms | ~20ms (just_audio) | ~5ms | **4x faster** |
| Phonetic match | <5ms | ~15ms | ~2ms | **7.5x faster** |
| ZIP extraction | <2s | ~5s | ~1.5s | **3.3x faster** |
| Checksum (14MB ZIP) | <100ms | ~250ms | ~60ms | **4x faster** |
| Voice command (end-to-end) | <1000ms | ~1200ms | ~800ms | **1.5x faster** |

### Network Efficiency (Batch vs Individual)

| Metric | Individual Ayah Downloads | Batch ZIP Download | Improvement |
|--------|---------------------------|---------------------|-------------|
| Requests (Surah Baqarah) | 286 requests | 1 request | **286x fewer** |
| Total Data Transfer | ~15 MB (uncompressed) | ~10.5 MB (compressed) | **30% smaller** |
| Download Time (3G) | ~8 minutes | ~2 minutes | **4x faster** |
| Server Load | High (286 connections) | Low (1 connection) | **Massive reduction** |
| Partial Download Recovery | Complex (track 286 files) | Simple (resume 1 ZIP) | **Easy resume** |

### Memory Footprint

- **IDLE state:** 50 MB
- **PLAYING state (Oboe):** 90 MB (native buffers smaller)
- **STREAMING state (just_audio):** 140 MB (Dart overhead)
- **REPEATING state:** 110 MB (with preload)
- **DOWNLOADING state:** 130 MB (ZIP buffer + extraction)
- **Max allowed:** 200 MB (auto-cleanup threshold)

---

END OF SEQUENCE DIAGRAMS V3

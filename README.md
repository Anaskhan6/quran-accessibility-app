
# Quran Accessibility App — Android First Native Foundation

Accessibility-first Quran application designed for blind and visually impaired users.

## Architecture

Flutter UI Layer  
Dart Audio Service  
C++ Native Audio Engine (Oboe - Android)  
SQLite Database  
Voice Command Engine  

## Native Modules

/audio_engine → Low latency playback  
/phonetic_matcher → Fuzzy Surah matching  
/integrity_validator → Checksum verification  
/ffi_bridge → Dart ↔ C++ bindings  

## Build Focus

Phase 1: Android native stability  
Phase 2: iOS parity layer  

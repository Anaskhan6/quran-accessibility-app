# CMakeLists.txt
# Native Audio Engine for Quran Accessibility App
# Uses Oboe for low-latency audio on Android

cmake_minimum_required(VERSION 3.10)
project(quran_native VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Oboe for low-latency audio (Android)
# Clone: git submodule add https://github.com/google/oboe.git native/oboe
add_subdirectory(oboe)

# Native library
add_library(quran_native SHARED
    audio_engine/audio_engine.cpp
    phonetic_matcher/fuzzy_matcher.cpp
    integrity_validator/checksum.cpp
    ffi_bridge/ffi_exports.cpp
)

# Include directories
target_include_directories(quran_native PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/audio_engine
    ${CMAKE_CURRENT_SOURCE_DIR}/phonetic_matcher
    ${CMAKE_CURRENT_SOURCE_DIR}/integrity_validator
)

# Link Oboe and Android libraries
target_link_libraries(quran_native
    oboe
    android
    log
    OpenSLES
)

# Compiler warnings
target_compile_options(quran_native PRIVATE
    -Wall
    -Wextra
    -Wpedantic
)

# Symbol visibility for FFI exports
set_target_properties(quran_native PROPERTIES
    CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN ON
)

/**
 * ffi_exports.cpp
 * 
 * Central FFI exports for all native modules
 * Links audio_engine, phonetic_matcher, and integrity_validator
 */

#include "../audio_engine/audio_engine.h"
#include "../phonetic_matcher/fuzzy_matcher.h"
#include "../integrity_validator/checksum.h"

// All FFI exports are defined in the individual module files:
// - audio_engine.cpp: audio_engine_* functions
// - fuzzy_matcher.cpp: phonetic_matcher_* functions
// - checksum.cpp: integrity_validator_* functions

// This file ensures all modules are linked together
// and provides any cross-module functionality if needed

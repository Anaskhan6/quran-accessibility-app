/**
 * checksum.cpp
 * 
 * SHA256 integrity validation implementation
 * Target: <100ms for 14MB files
 */

#include "checksum.h"
#include <fstream>
#include <sstream>
#include <iomanip>
#include <cstring>
#include <android/log.h>
#include <chrono>

#define LOG_TAG "QuranIntegrity"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace quran {

// ============================================================================
// SHA256 CONSTANTS
// ============================================================================

static constexpr uint32_t K[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
};

// Helper macros
#define ROTR(x, n) (((x) >> (n)) | ((x) << (32 - (n))))
#define CH(x, y, z) (((x) & (y)) ^ (~(x) & (z)))
#define MAJ(x, y, z) (((x) & (y)) ^ ((x) & (z)) ^ ((y) & (z)))
#define EP0(x) (ROTR(x, 2) ^ ROTR(x, 13) ^ ROTR(x, 22))
#define EP1(x) (ROTR(x, 6) ^ ROTR(x, 11) ^ ROTR(x, 25))
#define SIG0(x) (ROTR(x, 7) ^ ROTR(x, 18) ^ ((x) >> 3))
#define SIG1(x) (ROTR(x, 17) ^ ROTR(x, 19) ^ ((x) >> 10))

// ============================================================================
// FILE VALIDATION
// ============================================================================

ValidationResult IntegrityValidator::validateAudioFile(
    const std::string& filePath,
    const std::string& expectedChecksum) {
    
    auto start = std::chrono::high_resolution_clock::now();
    
    std::string actual = calculateFileChecksum(filePath);
    
    auto end = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end - start);
    LOGI("Checksum calculated in %lld ms", duration.count());
    
    if (actual.empty()) {
        return {false, "", "Failed to read file"};
    }
    
    bool valid = (actual == expectedChecksum);
    return {
        valid,
        actual,
        valid ? "Checksum valid" : "Checksum mismatch"
    };
}

std::string IntegrityValidator::calculateFileChecksum(const std::string& filePath) {
    std::ifstream file(filePath, std::ios::binary);
    if (!file.is_open()) {
        LOGE("Failed to open file: %s", filePath.c_str());
        return "";
    }
    
    // Read file into buffer
    std::vector<uint8_t> data;
    constexpr size_t bufferSize = 8192;
    std::vector<uint8_t> buffer(bufferSize);
    
    while (file.read(reinterpret_cast<char*>(buffer.data()), bufferSize)) {
        data.insert(data.end(), buffer.begin(), buffer.begin() + file.gcount());
    }
    data.insert(data.end(), buffer.begin(), buffer.begin() + file.gcount());
    
    file.close();
    
    return sha256(data);
}

bool IntegrityValidator::validateAudioDuration(
    const std::string& filePath,
    double expectedDuration,
    double tolerance) {
    
    // TODO: Implement actual duration extraction from MP3
    // For now, return true for testing
    LOGI("Duration validation: %s (expected: %.2fs)", filePath.c_str(), expectedDuration);
    (void)tolerance;
    return true;
}

// ============================================================================
// TEXT VALIDATION
// ============================================================================

ValidationResult IntegrityValidator::validateQuranText(
    const std::string& text,
    const std::string& expectedChecksum) {
    
    std::string actual = calculateTextChecksum(text);
    bool valid = (actual == expectedChecksum);
    
    if (!valid) {
        LOGE("Quran text checksum mismatch! Expected: %s, Got: %s",
             expectedChecksum.c_str(), actual.c_str());
    }
    
    return {
        valid,
        actual,
        valid ? "Text integrity verified" : "CRITICAL: Quran text corrupted"
    };
}

std::string IntegrityValidator::calculateTextChecksum(const std::string& text) {
    return sha256(text);
}

// ============================================================================
// ZIP VALIDATION
// ============================================================================

ValidationResult IntegrityValidator::validateZipFile(
    const std::string& zipPath,
    const std::string& expectedChecksum) {
    
    return validateAudioFile(zipPath, expectedChecksum);
}

// ============================================================================
// SHA256 IMPLEMENTATION
// ============================================================================

void IntegrityValidator::sha256Init(SHA256Context& ctx) {
    ctx.state[0] = 0x6a09e667;
    ctx.state[1] = 0xbb67ae85;
    ctx.state[2] = 0x3c6ef372;
    ctx.state[3] = 0xa54ff53a;
    ctx.state[4] = 0x510e527f;
    ctx.state[5] = 0x9b05688c;
    ctx.state[6] = 0x1f83d9ab;
    ctx.state[7] = 0x5be0cd19;
    ctx.count = 0;
    std::memset(ctx.buffer, 0, 64);
}

void IntegrityValidator::sha256Transform(uint32_t* state, const uint8_t* block) {
    uint32_t w[64];
    uint32_t a, b, c, d, e, f, g, h;
    
    // Prepare message schedule
    for (int i = 0; i < 16; ++i) {
        w[i] = (block[i * 4] << 24) | (block[i * 4 + 1] << 16) |
               (block[i * 4 + 2] << 8) | block[i * 4 + 3];
    }
    for (int i = 16; i < 64; ++i) {
        w[i] = SIG1(w[i - 2]) + w[i - 7] + SIG0(w[i - 15]) + w[i - 16];
    }
    
    // Initialize working variables
    a = state[0]; b = state[1]; c = state[2]; d = state[3];
    e = state[4]; f = state[5]; g = state[6]; h = state[7];
    
    // Main loop
    for (int i = 0; i < 64; ++i) {
        uint32_t t1 = h + EP1(e) + CH(e, f, g) + K[i] + w[i];
        uint32_t t2 = EP0(a) + MAJ(a, b, c);
        h = g; g = f; f = e; e = d + t1;
        d = c; c = b; b = a; a = t1 + t2;
    }
    
    // Update state
    state[0] += a; state[1] += b; state[2] += c; state[3] += d;
    state[4] += e; state[5] += f; state[6] += g; state[7] += h;
}

void IntegrityValidator::sha256Update(SHA256Context& ctx, const uint8_t* data, size_t len) {
    size_t bufferIndex = static_cast<size_t>(ctx.count & 63);
    ctx.count += len;
    
    size_t remaining = 64 - bufferIndex;
    size_t i = 0;
    
    if (len >= remaining) {
        std::memcpy(ctx.buffer + bufferIndex, data, remaining);
        sha256Transform(ctx.state, ctx.buffer);
        
        for (i = remaining; i + 63 < len; i += 64) {
            sha256Transform(ctx.state, data + i);
        }
        bufferIndex = 0;
    }
    
    std::memcpy(ctx.buffer + bufferIndex, data + i, len - i);
}

void IntegrityValidator::sha256Final(SHA256Context& ctx, uint8_t* hash) {
    uint8_t pad[64] = {0x80};
    uint64_t bits = ctx.count * 8;
    
    size_t padLen = (ctx.count & 63) < 56 ? 
                    56 - (ctx.count & 63) : 
                    120 - (ctx.count & 63);
    
    sha256Update(ctx, pad, padLen);
    
    uint8_t lenBytes[8];
    for (int i = 0; i < 8; ++i) {
        lenBytes[7 - i] = static_cast<uint8_t>(bits >> (i * 8));
    }
    sha256Update(ctx, lenBytes, 8);
    
    for (int i = 0; i < 8; ++i) {
        hash[i * 4] = static_cast<uint8_t>(ctx.state[i] >> 24);
        hash[i * 4 + 1] = static_cast<uint8_t>(ctx.state[i] >> 16);
        hash[i * 4 + 2] = static_cast<uint8_t>(ctx.state[i] >> 8);
        hash[i * 4 + 3] = static_cast<uint8_t>(ctx.state[i]);
    }
}

std::string IntegrityValidator::sha256(const std::vector<uint8_t>& data) {
    SHA256Context ctx;
    sha256Init(ctx);
    sha256Update(ctx, data.data(), data.size());
    
    uint8_t hash[32];
    sha256Final(ctx, hash);
    
    std::ostringstream result;
    for (int i = 0; i < 32; ++i) {
        result << std::hex << std::setfill('0') << std::setw(2) 
               << static_cast<int>(hash[i]);
    }
    
    return result.str();
}

std::string IntegrityValidator::sha256(const std::string& data) {
    std::vector<uint8_t> bytes(data.begin(), data.end());
    return sha256(bytes);
}

} // namespace quran

// ============================================================================
// FFI EXPORTS IMPLEMENTATION
// ============================================================================

extern "C" {

void* integrity_validator_create() {
    return new quran::IntegrityValidator();
}

void integrity_validator_destroy(void* validator) {
    delete static_cast<quran::IntegrityValidator*>(validator);
}

int integrity_validator_validate_audio(
    void* validator,
    const char* filePath,
    const char* expectedChecksum) {
    
    if (!validator || !filePath || !expectedChecksum) return 0;
    
    auto result = static_cast<quran::IntegrityValidator*>(validator)
        ->validateAudioFile(std::string(filePath), std::string(expectedChecksum));
    
    return result.valid ? 1 : 0;
}

char* integrity_validator_calculate_checksum(
    void* validator,
    const char* filePath) {
    
    if (!validator || !filePath) return nullptr;
    
    std::string checksum = static_cast<quran::IntegrityValidator*>(validator)
        ->calculateFileChecksum(std::string(filePath));
    
    if (checksum.empty()) return nullptr;
    
    char* result = static_cast<char*>(malloc(checksum.size() + 1));
    std::strcpy(result, checksum.c_str());
    return result;
}

int integrity_validator_validate_text(
    void* validator,
    const char* text,
    const char* expectedChecksum) {
    
    if (!validator || !text || !expectedChecksum) return 0;
    
    auto result = static_cast<quran::IntegrityValidator*>(validator)
        ->validateQuranText(std::string(text), std::string(expectedChecksum));
    
    return result.valid ? 1 : 0;
}

int integrity_validator_validate_zip(
    void* validator,
    const char* zipPath,
    const char* expectedChecksum) {
    
    if (!validator || !zipPath || !expectedChecksum) return 0;
    
    auto result = static_cast<quran::IntegrityValidator*>(validator)
        ->validateZipFile(std::string(zipPath), std::string(expectedChecksum));
    
    return result.valid ? 1 : 0;
}

void free_string(char* str) {
    free(str);
}

} // extern "C"

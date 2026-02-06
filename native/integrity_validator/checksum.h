/**
 * checksum.h
 * 
 * Integrity validation for Quran text and audio files
 * Uses SHA256 for file checksums
 * Target: <100ms for 14MB files
 */

#ifndef QURAN_CHECKSUM_H
#define QURAN_CHECKSUM_H

#include <string>
#include <vector>
#include <cstdint>

namespace quran {

/**
 * Checksum validation result
 */
struct ValidationResult {
    bool valid;
    std::string actualChecksum;
    std::string message;
};

/**
 * IntegrityValidator
 * 
 * SHA256 checksum validation for audio files and Quran text
 * Enforces Tanzil verified text integrity
 */
class IntegrityValidator {
public:
    IntegrityValidator() = default;
    ~IntegrityValidator() = default;

    // ========================================================================
    // FILE VALIDATION
    // ========================================================================

    /**
     * Validate audio file checksum
     * @param filePath Path to audio file
     * @param expectedChecksum Expected SHA256 hash (hex string)
     * @return Validation result
     */
    ValidationResult validateAudioFile(
        const std::string& filePath,
        const std::string& expectedChecksum
    );

    /**
     * Calculate SHA256 checksum of file
     * @param filePath Path to file
     * @return SHA256 hash as hex string
     */
    std::string calculateFileChecksum(const std::string& filePath);

    /**
     * Validate audio file by duration
     * @param filePath Path to audio file
     * @param expectedDuration Expected duration in seconds
     * @param tolerance Allowed deviation in seconds
     * @return true if within tolerance
     */
    bool validateAudioDuration(
        const std::string& filePath,
        double expectedDuration,
        double tolerance = 0.5
    );

    // ========================================================================
    // TEXT VALIDATION
    // ========================================================================

    /**
     * Validate Quran text checksum (Tanzil verified)
     * @param text Arabic text content
     * @param expectedChecksum Expected SHA256 hash
     * @return Validation result
     */
    ValidationResult validateQuranText(
        const std::string& text,
        const std::string& expectedChecksum
    );

    /**
     * Calculate checksum of text
     * @param text Text content
     * @return SHA256 hash as hex string
     */
    std::string calculateTextChecksum(const std::string& text);

    // ========================================================================
    // ZIP VALIDATION
    // ========================================================================

    /**
     * Validate downloaded ZIP file
     * @param zipPath Path to ZIP file
     * @param expectedChecksum Expected SHA256 hash
     * @return Validation result
     */
    ValidationResult validateZipFile(
        const std::string& zipPath,
        const std::string& expectedChecksum
    );

    // ========================================================================
    // SHA256 IMPLEMENTATION
    // ========================================================================

    /**
     * Calculate SHA256 hash of data
     * @param data Raw bytes
     * @return SHA256 hash as hex string
     */
    static std::string sha256(const std::vector<uint8_t>& data);

    /**
     * Calculate SHA256 hash of string
     * @param data String content
     * @return SHA256 hash as hex string
     */
    static std::string sha256(const std::string& data);

private:
    // SHA256 internal state
    struct SHA256Context {
        uint32_t state[8];
        uint64_t count;
        uint8_t buffer[64];
    };

    static void sha256Init(SHA256Context& ctx);
    static void sha256Update(SHA256Context& ctx, const uint8_t* data, size_t len);
    static void sha256Final(SHA256Context& ctx, uint8_t* hash);
    static void sha256Transform(uint32_t* state, const uint8_t* block);
};

} // namespace quran

// ============================================================================
// FFI EXPORTS
// ============================================================================

extern "C" {

/**
 * Create validator instance
 */
__attribute__((visibility("default")))
void* integrity_validator_create();

/**
 * Destroy validator instance
 */
__attribute__((visibility("default")))
void integrity_validator_destroy(void* validator);

/**
 * Validate audio file checksum
 * @return 1 if valid, 0 if invalid
 */
__attribute__((visibility("default")))
int integrity_validator_validate_audio(
    void* validator,
    const char* filePath,
    const char* expectedChecksum
);

/**
 * Calculate file checksum
 * @return Checksum string (caller must free with free_string)
 */
__attribute__((visibility("default")))
char* integrity_validator_calculate_checksum(
    void* validator,
    const char* filePath
);

/**
 * Validate Quran text checksum
 * @return 1 if valid, 0 if invalid
 */
__attribute__((visibility("default")))
int integrity_validator_validate_text(
    void* validator,
    const char* text,
    const char* expectedChecksum
);

/**
 * Validate ZIP file checksum
 * @return 1 if valid, 0 if invalid
 */
__attribute__((visibility("default")))
int integrity_validator_validate_zip(
    void* validator,
    const char* zipPath,
    const char* expectedChecksum
);

/**
 * Free string allocated by validator
 */
__attribute__((visibility("default")))
void free_string(char* str);

} // extern "C"

#endif // QURAN_CHECKSUM_H

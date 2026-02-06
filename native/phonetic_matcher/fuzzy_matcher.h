/**
 * fuzzy_matcher.h
 * 
 * Phonetic matching for Surah name recognition
 * Uses Levenshtein distance and Jaro-Winkler similarity
 * Target: <5ms for 114 Surahs
 */

#ifndef QURAN_FUZZY_MATCHER_H
#define QURAN_FUZZY_MATCHER_H

#include <string>
#include <vector>
#include <unordered_map>

namespace quran {

/**
 * Match result with confidence score
 */
struct MatchResult {
    int surahId;
    double confidence;
    std::string matchedAlias;
};

/**
 * PhoneticMatcher
 * 
 * Fuzzy string matching for Surah names
 * Supports Arabic, English, and transliterated names
 */
class PhoneticMatcher {
public:
    PhoneticMatcher();
    ~PhoneticMatcher() = default;

    /**
     * Initialize with Surah alias dictionary
     * Call once at startup
     */
    void initialize();

    /**
     * Find Surah by name (fuzzy match)
     * @param input User input (any language)
     * @return Surah ID (1-114) or -1 if not found
     */
    int findSurah(const std::string& input);

    /**
     * Find Surah with confidence score
     * @param input User input
     * @return Best match result with confidence
     */
    MatchResult findSurahWithConfidence(const std::string& input);

    /**
     * Get all matches above threshold
     * @param input User input
     * @param threshold Minimum confidence (0.0-1.0)
     * @return Vector of matches
     */
    std::vector<MatchResult> findAllMatches(
        const std::string& input, 
        double threshold = 0.5
    );

    /**
     * Update alias dictionary
     * Use when loading new language packs
     * @param surahId Surah number (1-114)
     * @param aliases List of aliases for this Surah
     */
    void addAliases(int surahId, const std::vector<std::string>& aliases);

    /**
     * Clear all aliases
     */
    void clearAliases();

    // ========================================================================
    // STRING SIMILARITY ALGORITHMS
    // ========================================================================

    /**
     * Levenshtein edit distance
     * @return Number of edits (insertions, deletions, substitutions)
     */
    static int levenshteinDistance(const std::string& s1, const std::string& s2);

    /**
     * Jaro similarity (0.0 to 1.0)
     */
    static double jaroSimilarity(const std::string& s1, const std::string& s2);

    /**
     * Jaro-Winkler similarity (0.0 to 1.0)
     * Gives higher weight to prefix matches
     */
    static double jaroWinklerSimilarity(const std::string& s1, const std::string& s2);

private:
    // Surah ID -> List of aliases
    std::unordered_map<int, std::vector<std::string>> aliasDict_;
    
    // Normalized lowercase string
    static std::string normalize(const std::string& input);
    
    // Load default Surah aliases
    void loadDefaultAliases();
};

} // namespace quran

// ============================================================================
// FFI EXPORTS
// ============================================================================

extern "C" {

/**
 * Create phonetic matcher instance
 */
__attribute__((visibility("default")))
void* phonetic_matcher_create();

/**
 * Destroy phonetic matcher instance
 */
__attribute__((visibility("default")))
void phonetic_matcher_destroy(void* matcher);

/**
 * Initialize with default Surah aliases
 */
__attribute__((visibility("default")))
void phonetic_matcher_initialize(void* matcher);

/**
 * Find Surah by name
 * @return Surah ID (1-114) or -1 if not found
 */
__attribute__((visibility("default")))
int phonetic_matcher_find_surah(void* matcher, const char* input);

/**
 * Find Surah with confidence
 * @param outConfidence Pointer to store confidence value
 * @return Surah ID
 */
__attribute__((visibility("default")))
int phonetic_matcher_find_with_confidence(
    void* matcher, 
    const char* input,
    double* outConfidence
);

/**
 * Add aliases for a Surah
 * @param aliases Comma-separated list of aliases
 */
__attribute__((visibility("default")))
void phonetic_matcher_add_aliases(
    void* matcher, 
    int surahId, 
    const char* aliases
);

} // extern "C"

#endif // QURAN_FUZZY_MATCHER_H

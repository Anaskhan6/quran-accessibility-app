/**
 * fuzzy_matcher.cpp
 * 
 * Phonetic matching implementation
 * Target: <5ms for 114 Surahs
 */

#include "fuzzy_matcher.h"
#include <algorithm>
#include <cctype>
#include <cmath>
#include <sstream>
#include <android/log.h>

#define LOG_TAG "QuranPhoneticMatcher"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)

namespace quran {

// ============================================================================
// CONSTRUCTOR
// ============================================================================

PhoneticMatcher::PhoneticMatcher() {
    loadDefaultAliases();
}

void PhoneticMatcher::initialize() {
    loadDefaultAliases();
    LOGI("PhoneticMatcher initialized with %zu Surahs", aliasDict_.size());
}

// ============================================================================
// MAIN MATCHING FUNCTIONS
// ============================================================================

int PhoneticMatcher::findSurah(const std::string& input) {
    MatchResult result = findSurahWithConfidence(input);
    return result.confidence >= 0.8 ? result.surahId : -1;
}

MatchResult PhoneticMatcher::findSurahWithConfidence(const std::string& input) {
    std::string normalizedInput = normalize(input);
    MatchResult bestMatch{-1, 0.0, ""};
    
    for (const auto& [surahId, aliases] : aliasDict_) {
        for (const auto& alias : aliases) {
            std::string normalizedAlias = normalize(alias);
            
            // Step 1: Exact match
            if (normalizedInput == normalizedAlias) {
                return {surahId, 1.0, alias};
            }
            
            // Step 2: Levenshtein distance (threshold: 2 edits)
            int distance = levenshteinDistance(normalizedInput, normalizedAlias);
            if (distance <= 2) {
                double confidence = 1.0 - (distance / static_cast<double>(
                    std::max(normalizedInput.length(), normalizedAlias.length())
                ));
                if (confidence > bestMatch.confidence) {
                    bestMatch = {surahId, confidence, alias};
                }
            }
            
            // Step 3: Jaro-Winkler similarity (threshold: 0.85)
            double jwSimilarity = jaroWinklerSimilarity(normalizedInput, normalizedAlias);
            if (jwSimilarity >= 0.85 && jwSimilarity > bestMatch.confidence) {
                bestMatch = {surahId, jwSimilarity, alias};
            }
        }
    }
    
    return bestMatch;
}

std::vector<MatchResult> PhoneticMatcher::findAllMatches(
    const std::string& input, 
    double threshold) {
    
    std::vector<MatchResult> results;
    std::string normalizedInput = normalize(input);
    
    for (const auto& [surahId, aliases] : aliasDict_) {
        double bestScore = 0.0;
        std::string bestAlias;
        
        for (const auto& alias : aliases) {
            double score = jaroWinklerSimilarity(normalizedInput, normalize(alias));
            if (score > bestScore) {
                bestScore = score;
                bestAlias = alias;
            }
        }
        
        if (bestScore >= threshold) {
            results.push_back({surahId, bestScore, bestAlias});
        }
    }
    
    // Sort by confidence descending
    std::sort(results.begin(), results.end(), 
              [](const MatchResult& a, const MatchResult& b) {
                  return a.confidence > b.confidence;
              });
    
    return results;
}

// ============================================================================
// ALIAS MANAGEMENT
// ============================================================================

void PhoneticMatcher::addAliases(int surahId, const std::vector<std::string>& aliases) {
    auto& current = aliasDict_[surahId];
    current.insert(current.end(), aliases.begin(), aliases.end());
}

void PhoneticMatcher::clearAliases() {
    aliasDict_.clear();
}

// ============================================================================
// STRING SIMILARITY ALGORITHMS
// ============================================================================

int PhoneticMatcher::levenshteinDistance(const std::string& s1, const std::string& s2) {
    const size_t m = s1.size();
    const size_t n = s2.size();
    
    if (m == 0) return static_cast<int>(n);
    if (n == 0) return static_cast<int>(m);
    
    std::vector<std::vector<int>> dp(m + 1, std::vector<int>(n + 1));
    
    for (size_t i = 0; i <= m; ++i) dp[i][0] = static_cast<int>(i);
    for (size_t j = 0; j <= n; ++j) dp[0][j] = static_cast<int>(j);
    
    for (size_t i = 1; i <= m; ++i) {
        for (size_t j = 1; j <= n; ++j) {
            int cost = (s1[i - 1] == s2[j - 1]) ? 0 : 1;
            dp[i][j] = std::min({
                dp[i - 1][j] + 1,       // deletion
                dp[i][j - 1] + 1,       // insertion
                dp[i - 1][j - 1] + cost // substitution
            });
        }
    }
    
    return dp[m][n];
}

double PhoneticMatcher::jaroSimilarity(const std::string& s1, const std::string& s2) {
    if (s1.empty() && s2.empty()) return 1.0;
    if (s1.empty() || s2.empty()) return 0.0;
    
    const size_t len1 = s1.size();
    const size_t len2 = s2.size();
    const size_t matchWindow = std::max(len1, len2) / 2 - 1;
    
    std::vector<bool> s1Matched(len1, false);
    std::vector<bool> s2Matched(len2, false);
    
    size_t matches = 0;
    size_t transpositions = 0;
    
    // Find matches
    for (size_t i = 0; i < len1; ++i) {
        size_t start = (i > matchWindow) ? i - matchWindow : 0;
        size_t end = std::min(i + matchWindow + 1, len2);
        
        for (size_t j = start; j < end; ++j) {
            if (s2Matched[j] || s1[i] != s2[j]) continue;
            s1Matched[i] = true;
            s2Matched[j] = true;
            ++matches;
            break;
        }
    }
    
    if (matches == 0) return 0.0;
    
    // Count transpositions
    size_t k = 0;
    for (size_t i = 0; i < len1; ++i) {
        if (!s1Matched[i]) continue;
        while (!s2Matched[k]) ++k;
        if (s1[i] != s2[k]) ++transpositions;
        ++k;
    }
    
    double m = static_cast<double>(matches);
    return (m / len1 + m / len2 + (m - transpositions / 2.0) / m) / 3.0;
}

double PhoneticMatcher::jaroWinklerSimilarity(const std::string& s1, const std::string& s2) {
    double jaro = jaroSimilarity(s1, s2);
    
    // Calculate common prefix (up to 4 chars)
    size_t prefixLen = 0;
    size_t maxPrefix = std::min({s1.size(), s2.size(), size_t(4)});
    for (size_t i = 0; i < maxPrefix; ++i) {
        if (std::tolower(s1[i]) == std::tolower(s2[i])) {
            ++prefixLen;
        } else {
            break;
        }
    }
    
    // Scaling factor p = 0.1 is standard
    constexpr double p = 0.1;
    return jaro + prefixLen * p * (1.0 - jaro);
}

// ============================================================================
// PRIVATE METHODS
// ============================================================================

std::string PhoneticMatcher::normalize(const std::string& input) {
    std::string result;
    result.reserve(input.size());
    
    for (char c : input) {
        if (std::isalpha(c)) {
            result += std::tolower(c);
        }
        // Skip hyphens, spaces, diacritics
    }
    
    return result;
}

void PhoneticMatcher::loadDefaultAliases() {
    // Core Surahs with common aliases
    aliasDict_ = {
        {1, {"fatiha", "fatihah", "alfatiha", "opening", "الفاتحة"}},
        {2, {"baqarah", "baqara", "albaqarah", "cow", "البقرة"}},
        {3, {"imran", "alimran", "aliimran", "البقرة"}},
        {4, {"nisa", "nisaa", "alnisa", "women", "النساء"}},
        {5, {"maidah", "maida", "almaidah", "table", "المائدة"}},
        {6, {"anam", "anaam", "alanam", "cattle", "الأنعام"}},
        {7, {"araf", "aaraf", "alaraf", "heights", "الأعراف"}},
        {8, {"anfal", "alanfal", "spoils", "الأنفال"}},
        {9, {"tawbah", "tawba", "attawbah", "repentance", "التوبة"}},
        {10, {"yunus", "jonah", "يونس"}},
        {11, {"hud", "هود"}},
        {12, {"yusuf", "joseph", "يوسف"}},
        {13, {"raad", "rad", "thunder", "الرعد"}},
        {14, {"ibrahim", "abraham", "إبراهيم"}},
        {15, {"hijr", "alhijr", "الحجر"}},
        {16, {"nahl", "bee", "النحل"}},
        {17, {"isra", "israa", "alisra", "journey", "الإسراء"}},
        {18, {"kahf", "alkahf", "cave", "الكهف"}},
        {19, {"maryam", "mary", "مريم"}},
        {20, {"taha", "طه"}},
        {21, {"anbiya", "prophets", "الأنبياء"}},
        {22, {"hajj", "pilgrimage", "الحج"}},
        {23, {"muminun", "believers", "المؤمنون"}},
        {24, {"nur", "noor", "light", "النور"}},
        {25, {"furqan", "criterion", "الفرقان"}},
        {26, {"shuara", "poets", "الشعراء"}},
        {27, {"naml", "ant", "النمل"}},
        {28, {"qasas", "stories", "القصص"}},
        {29, {"ankabut", "spider", "العنكبوت"}},
        {30, {"rum", "romans", "الروم"}},
        {31, {"luqman", "لقمان"}},
        {32, {"sajdah", "prostration", "السجدة"}},
        {33, {"ahzab", "confederates", "الأحزاب"}},
        {34, {"saba", "sheba", "سبإ"}},
        {35, {"fatir", "originator", "فاطر"}},
        {36, {"yasin", "yaseen", "يس"}},
        {37, {"saffat", "rankers", "الصافات"}},
        {38, {"sad", "ص"}},
        {39, {"zumar", "groups", "الزمر"}},
        {40, {"ghafir", "forgiver", "غافر"}},
        {41, {"fussilat", "explained", "فصلت"}},
        {42, {"shura", "consultation", "الشورى"}},
        {43, {"zukhruf", "gold", "الزخرف"}},
        {44, {"dukhan", "smoke", "الدخان"}},
        {45, {"jathiyah", "kneeling", "الجاثية"}},
        {46, {"ahqaf", "dunes", "الأحقاف"}},
        {47, {"muhammad", "محمد"}},
        {48, {"fath", "victory", "الفتح"}},
        {49, {"hujurat", "rooms", "الحجرات"}},
        {50, {"qaf", "ق"}},
        {51, {"dhariyat", "winds", "الذاريات"}},
        {52, {"tur", "mount", "الطور"}},
        {53, {"najm", "star", "النجم"}},
        {54, {"qamar", "moon", "القمر"}},
        {55, {"rahman", "rehman", "rahmaan", "arrahman", "merciful", "الرحمن"}},
        {56, {"waqiah", "event", "الواقعة"}},
        {57, {"hadid", "iron", "الحديد"}},
        {58, {"mujadilah", "pleading", "المجادلة"}},
        {59, {"hashr", "gathering", "الحشر"}},
        {60, {"mumtahanah", "examined", "الممتحنة"}},
        {61, {"saff", "ranks", "الصف"}},
        {62, {"jumuah", "friday", "الجمعة"}},
        {63, {"munafiqun", "hypocrites", "المنافقون"}},
        {64, {"taghabun", "loss", "التغابن"}},
        {65, {"talaq", "divorce", "الطلاق"}},
        {66, {"tahrim", "prohibition", "التحريم"}},
        {67, {"mulk", "sovereignty", "الملك"}},
        {68, {"qalam", "pen", "القلم"}},
        {69, {"haqqah", "reality", "الحاقة"}},
        {70, {"maarij", "ways", "المعارج"}},
        {71, {"nuh", "noah", "نوح"}},
        {72, {"jinn", "الجن"}},
        {73, {"muzzammil", "wrapped", "المزمل"}},
        {74, {"muddaththir", "cloaked", "المدثر"}},
        {75, {"qiyamah", "resurrection", "القيامة"}},
        {76, {"insan", "man", "الإنسان"}},
        {77, {"mursalat", "emissaries", "المرسلات"}},
        {78, {"naba", "news", "النبأ"}},
        {79, {"naziat", "extractors", "النازعات"}},
        {80, {"abasa", "frowned", "عبس"}},
        {81, {"takwir", "folding", "التكوير"}},
        {82, {"infitar", "cleaving", "الانفطار"}},
        {83, {"mutaffifin", "defrauders", "المطففين"}},
        {84, {"inshiqaq", "splitting", "الانشقاق"}},
        {85, {"buruj", "constellations", "البروج"}},
        {86, {"tariq", "star", "الطارق"}},
        {87, {"ala", "most high", "الأعلى"}},
        {88, {"ghashiyah", "overwhelming", "الغاشية"}},
        {89, {"fajr", "dawn", "الفجر"}},
        {90, {"balad", "city", "البلد"}},
        {91, {"shams", "sun", "الشمس"}},
        {92, {"layl", "night", "الليل"}},
        {93, {"duha", "morning", "الضحى"}},
        {94, {"sharh", "relief", "الشرح"}},
        {95, {"tin", "fig", "التين"}},
        {96, {"alaq", "clot", "العلق"}},
        {97, {"qadr", "power", "القدر"}},
        {98, {"bayyinah", "evidence", "البينة"}},
        {99, {"zalzalah", "earthquake", "الزلزلة"}},
        {100, {"adiyat", "chargers", "العاديات"}},
        {101, {"qariah", "calamity", "القارعة"}},
        {102, {"takathur", "rivalry", "التكاثر"}},
        {103, {"asr", "time", "العصر"}},
        {104, {"humazah", "slanderer", "الهمزة"}},
        {105, {"fil", "elephant", "الفيل"}},
        {106, {"quraysh", "قريش"}},
        {107, {"maun", "assistance", "الماعون"}},
        {108, {"kawthar", "abundance", "الكوثر"}},
        {109, {"kafirun", "disbelievers", "الكافرون"}},
        {110, {"nasr", "help", "النصر"}},
        {111, {"masad", "lahab", "flame", "المسد"}},
        {112, {"ikhlas", "ikhlaas", "sincerity", "الإخلاص"}},
        {113, {"falaq", "daybreak", "الفلق"}},
        {114, {"nas", "naas", "mankind", "الناس"}}
    };
}

} // namespace quran

// ============================================================================
// FFI EXPORTS IMPLEMENTATION
// ============================================================================

extern "C" {

void* phonetic_matcher_create() {
    return new quran::PhoneticMatcher();
}

void phonetic_matcher_destroy(void* matcher) {
    delete static_cast<quran::PhoneticMatcher*>(matcher);
}

void phonetic_matcher_initialize(void* matcher) {
    if (matcher) {
        static_cast<quran::PhoneticMatcher*>(matcher)->initialize();
    }
}

int phonetic_matcher_find_surah(void* matcher, const char* input) {
    if (!matcher || !input) return -1;
    return static_cast<quran::PhoneticMatcher*>(matcher)->findSurah(
        std::string(input)
    );
}

int phonetic_matcher_find_with_confidence(
    void* matcher, 
    const char* input,
    double* outConfidence) {
    
    if (!matcher || !input) return -1;
    
    auto result = static_cast<quran::PhoneticMatcher*>(matcher)
        ->findSurahWithConfidence(std::string(input));
    
    if (outConfidence) {
        *outConfidence = result.confidence;
    }
    
    return result.surahId;
}

void phonetic_matcher_add_aliases(
    void* matcher, 
    int surahId, 
    const char* aliases) {
    
    if (!matcher || !aliases) return;
    
    std::vector<std::string> aliasList;
    std::stringstream ss(aliases);
    std::string item;
    
    while (std::getline(ss, item, ',')) {
        // Trim whitespace
        size_t start = item.find_first_not_of(" \t");
        size_t end = item.find_last_not_of(" \t");
        if (start != std::string::npos) {
            aliasList.push_back(item.substr(start, end - start + 1));
        }
    }
    
    static_cast<quran::PhoneticMatcher*>(matcher)->addAliases(surahId, aliasList);
}

} // extern "C"

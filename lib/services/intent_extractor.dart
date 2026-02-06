/// intent_extractor.dart
///
/// Intent Extraction Layer
/// Converts raw speech to structured VoiceIntent
///
/// Handles:
/// - Command verb recognition
/// - Surah name phonetic matching
/// - Ayah/verse number extraction
/// - Number word parsing

import 'voice_intent_router.dart';
import 'speech_capture.dart';

// ============================================================================
// SURAH DICTIONARY
// ============================================================================

/// Surah name to ID mapping with aliases
const Map<int, List<String>> surahAliases = {
  1: ['fatiha', 'fatihah', 'al-fatiha', 'alfatiha', 'opening'],
  2: ['baqara', 'baqarah', 'al-baqara', 'cow'],
  3: ['imran', 'al-imran', 'ali-imran', 'family of imran'],
  4: ['nisa', 'nisaa', 'al-nisa', 'women'],
  5: ['maida', 'maidah', 'al-maida', 'table spread'],
  6: ['anam', 'al-anam', 'cattle'],
  7: ['araf', 'al-araf', 'heights'],
  18: ['kahf', 'al-kahf', 'cave'],
  36: ['yasin', 'yaseen', 'ya-sin'],
  55: ['rahman', 'ar-rahman', 'rehman', 'rahmaan', 'merciful'],
  56: ['waqia', 'waqiah', 'al-waqia', 'event'],
  67: ['mulk', 'al-mulk', 'dominion', 'sovereignty'],
  78: ['naba', 'an-naba', 'tidings'],
  112: ['ikhlas', 'al-ikhlas', 'sincerity', 'purity'],
  113: ['falaq', 'al-falaq', 'daybreak', 'dawn'],
  114: ['nas', 'an-nas', 'mankind', 'people'],
};

/// Number words to integers
const Map<String, int> numberWords = {
  'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5,
  'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10,
  'eleven': 11, 'twelve': 12, 'thirteen': 13, 'fourteen': 14, 'fifteen': 15,
  'twenty': 20, 'thirty': 30, 'fifty': 50, 'hundred': 100,
  'first': 1, 'second': 2, 'third': 3, 'fourth': 4, 'fifth': 5,
  'once': 1, 'twice': 2, 'thrice': 3,
};

// ============================================================================
// EXTRACTED ENTITIES
// ============================================================================

class ExtractedEntities {
  final int? surahId;
  final String? surahName;
  final int? ayahNumber;
  final int? endAyahNumber;
  final int? repeatCount;
  final double? speedValue;
  final double surahConfidence;

  const ExtractedEntities({
    this.surahId,
    this.surahName,
    this.ayahNumber,
    this.endAyahNumber,
    this.repeatCount,
    this.speedValue,
    this.surahConfidence = 0.0,
  });

  Map<String, dynamic> toMap() => {
    'surahId': surahId,
    'surahName': surahName,
    'ayahNumber': ayahNumber,
    'endAyahNumber': endAyahNumber,
    'repeatCount': repeatCount,
    'speed': speedValue,
  };
}

// ============================================================================
// INTENT EXTRACTOR
// ============================================================================

class IntentExtractor {
  /// Extract intent from speech result
  VoiceIntent extract(SpeechResult speech) {
    final text = speech.text.toLowerCase().trim();
    final words = text.split(RegExp(r'\s+'));

    // Detect intent type
    final intentType = _detectIntentType(words);

    // Extract entities
    final entities = _extractEntities(text, words);

    return VoiceIntent(
      type: intentType,
      rawText: speech.text,
      confidence: speech.confidence * (entities.surahConfidence > 0 ? entities.surahConfidence : 1.0),
      entities: entities.toMap(),
      timestamp: DateTime.now(),
    );
  }

  // ===========================================================================
  // INTENT DETECTION
  // ===========================================================================

  VoiceIntentType _detectIntentType(List<String> words) {
    if (words.isEmpty) return VoiceIntentType.unknown;

    // Play commands
    if (_containsAny(words, ['play', 'start', 'begin', 'recite', 'read'])) {
      if (_containsAny(words, ['surah', 'sura', 'chapter'])) {
        return VoiceIntentType.play;
      }
      return VoiceIntentType.play;
    }

    // Pause/Resume
    if (_containsAny(words, ['pause', 'hold'])) return VoiceIntentType.pause;
    if (_containsAny(words, ['resume', 'continue'])) return VoiceIntentType.resume;
    if (_containsAny(words, ['stop', 'end', 'finish'])) return VoiceIntentType.stop;

    // Navigation
    if (_containsAny(words, ['next'])) {
      if (_containsAny(words, ['surah', 'sura', 'chapter'])) return VoiceIntentType.nextSurah;
      return VoiceIntentType.nextAyah;
    }
    if (_containsAny(words, ['previous', 'back', 'last'])) {
      if (_containsAny(words, ['surah', 'sura', 'chapter'])) return VoiceIntentType.previousSurah;
      return VoiceIntentType.previousAyah;
    }
    if (_containsAny(words, ['go', 'jump', 'skip', 'seek'])) {
      if (_containsAny(words, ['surah', 'sura', 'chapter'])) return VoiceIntentType.seekToSurah;
      if (_containsAny(words, ['ayah', 'verse', 'ayat'])) return VoiceIntentType.seekToAyah;
    }

    // Repeat
    if (_containsAny(words, ['repeat', 'loop', 'again'])) {
      // Check for range
      if (_containsAny(words, ['to', 'through', 'until'])) {
        return VoiceIntentType.repeatRange;
      }
      // Check for specific ayah
      if (_containsAny(words, ['ayah', 'verse', 'ayat'])) {
        return VoiceIntentType.repeatAyah;
      }
      // Check for count
      if (_hasNumber(words)) {
        return VoiceIntentType.repeatTimes;
      }
      return VoiceIntentType.repeatCurrent;
    }
    if (_containsAny(words, ['stop']) && _containsAny(words, ['repeat', 'loop'])) {
      return VoiceIntentType.stopRepeat;
    }

    // Speed
    if (_containsAny(words, ['faster', 'speed', 'up', 'quicker'])) return VoiceIntentType.speedUp;
    if (_containsAny(words, ['slower', 'slow', 'down'])) return VoiceIntentType.slowDown;

    // Volume
    if (_containsAny(words, ['louder', 'volume']) && _containsAny(words, ['up'])) return VoiceIntentType.volumeUp;
    if (_containsAny(words, ['quieter', 'softer', 'volume']) && _containsAny(words, ['down'])) return VoiceIntentType.volumeDown;
    if (_containsAny(words, ['mute', 'silent'])) return VoiceIntentType.mute;

    // Info
    if (_containsAny(words, ['what', 'which']) && _containsAny(words, ['playing', 'reciting'])) {
      return VoiceIntentType.whatIsPlaying;
    }
    if (_containsAny(words, ['help', 'commands'])) return VoiceIntentType.help;

    return VoiceIntentType.unknown;
  }

  // ===========================================================================
  // ENTITY EXTRACTION
  // ===========================================================================

  ExtractedEntities _extractEntities(String text, List<String> words) {
    int? surahId;
    String? surahName;
    double surahConfidence = 0.0;
    int? ayahNumber;
    int? endAyahNumber;
    int? repeatCount;

    // Find Surah
    final surahResult = _findSurah(text);
    if (surahResult != null) {
      surahId = surahResult.$1;
      surahName = surahResult.$2;
      surahConfidence = surahResult.$3;
    }

    // Find Ayah numbers
    final numbers = _extractNumbers(text, words);
    if (numbers.isNotEmpty) {
      ayahNumber = numbers[0];
      if (numbers.length > 1) {
        endAyahNumber = numbers[1];
      }
    }

    // Find repeat count
    if (_containsAny(words, ['times', 'time'])) {
      final countMatch = RegExp(r'(\d+)\s*times?').firstMatch(text);
      if (countMatch != null) {
        repeatCount = int.tryParse(countMatch.group(1)!);
      } else {
        // Check number words
        for (final word in words) {
          if (numberWords.containsKey(word) && words.indexOf(word) < words.indexOf('times')) {
            repeatCount = numberWords[word];
            break;
          }
        }
      }
    }

    // Check "infinite" or "forever"
    if (_containsAny(words, ['infinite', 'forever', 'infinitely'])) {
      repeatCount = -1;
    }

    return ExtractedEntities(
      surahId: surahId,
      surahName: surahName,
      ayahNumber: ayahNumber,
      endAyahNumber: endAyahNumber,
      repeatCount: repeatCount,
      surahConfidence: surahConfidence,
    );
  }

  /// Find Surah by name with phonetic matching
  (int, String, double)? _findSurah(String text) {
    final lower = text.toLowerCase();
    double bestScore = 0.0;
    int? bestId;
    String? bestName;

    for (final entry in surahAliases.entries) {
      for (final alias in entry.value) {
        if (lower.contains(alias)) {
          // Exact match
          return (entry.key, alias, 1.0);
        }

        // Fuzzy match
        final score = _similarityScore(lower, alias);
        if (score > bestScore && score > 0.6) {
          bestScore = score;
          bestId = entry.key;
          bestName = alias;
        }
      }
    }

    if (bestId != null) {
      return (bestId, bestName!, bestScore);
    }
    return null;
  }

  /// Extract all numbers from text
  List<int> _extractNumbers(String text, List<String> words) {
    final numbers = <int>[];

    // Numeric digits
    final digitMatches = RegExp(r'\b(\d+)\b').allMatches(text);
    for (final match in digitMatches) {
      final num = int.tryParse(match.group(1)!);
      if (num != null && num > 0 && num <= 286) { // Max Ayah count
        numbers.add(num);
      }
    }

    // Number words
    for (final word in words) {
      if (numberWords.containsKey(word)) {
        numbers.add(numberWords[word]!);
      }
    }

    return numbers;
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  bool _containsAny(List<String> words, List<String> targets) {
    for (final target in targets) {
      if (words.contains(target)) return true;
    }
    return false;
  }

  bool _hasNumber(List<String> words) {
    for (final word in words) {
      if (int.tryParse(word) != null || numberWords.containsKey(word)) {
        return true;
      }
    }
    return false;
  }

  /// Simple similarity score (Jaccard-like)
  double _similarityScore(String text, String target) {
    if (text.contains(target)) return 1.0;

    // Character overlap
    final textChars = text.split('').toSet();
    final targetChars = target.split('').toSet();
    final intersection = textChars.intersection(targetChars).length;
    final union = textChars.union(targetChars).length;

    if (union == 0) return 0.0;
    return intersection / union;
  }
}

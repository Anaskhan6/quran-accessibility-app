/// download_integrity.dart
///
/// Download Integrity Validation
/// SHA256 checksum verification for audio files

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

// ============================================================================
// MODELS
// ============================================================================

/// Validation result
class ValidationResult {
  final bool isValid;
  final String? expectedChecksum;
  final String? actualChecksum;
  final String? error;

  const ValidationResult({
    required this.isValid,
    this.expectedChecksum,
    this.actualChecksum,
    this.error,
  });
}

/// Manifest entry
class ManifestEntry {
  final String fileName;
  final String checksum;
  final int sizeBytes;

  const ManifestEntry({
    required this.fileName,
    required this.checksum,
    required this.sizeBytes,
  });

  factory ManifestEntry.fromJson(Map<String, dynamic> json) => ManifestEntry(
    fileName: json['fileName'],
    checksum: json['checksum'],
    sizeBytes: json['sizeBytes'],
  );
}

/// Manifest validation result
class ManifestValidationResult {
  final bool isValid;
  final int validCount;
  final int invalidCount;
  final List<String> invalidFiles;
  final List<String> missingFiles;

  const ManifestValidationResult({
    required this.isValid,
    this.validCount = 0,
    this.invalidCount = 0,
    this.invalidFiles = const [],
    this.missingFiles = const [],
  });
}

// ============================================================================
// INTEGRITY VALIDATOR
// ============================================================================

class DownloadIntegrity {
  final _progressController = StreamController<double>.broadcast();
  
  Stream<double> get progressStream => _progressController.stream;

  // ===========================================================================
  // PUBLIC API
  // ===========================================================================

  /// Validate single file checksum
  Future<ValidationResult> validateFile(String filePath, String expectedChecksum) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return ValidationResult(
          isValid: false,
          error: 'File not found',
        );
      }
      
      final actualChecksum = await calculateChecksum(filePath);
      final isValid = actualChecksum.toLowerCase() == expectedChecksum.toLowerCase();
      
      return ValidationResult(
        isValid: isValid,
        expectedChecksum: expectedChecksum,
        actualChecksum: actualChecksum,
        error: isValid ? null : 'Checksum mismatch',
      );
      
    } catch (e) {
      return ValidationResult(
        isValid: false,
        error: e.toString(),
      );
    }
  }

  /// Calculate SHA256 checksum
  Future<String> calculateChecksum(String filePath) async {
    final file = File(filePath);
    final sink = AccumulatorSink<Digest>();
    final input = sha256.startChunkedConversion(sink);
    
    final length = await file.length();
    int processed = 0;
    
    await for (final chunk in file.openRead()) {
      input.add(chunk);
      processed += chunk.length;
      _progressController.add(processed / length);
    }
    
    input.close();
    return sink.events.single.toString();
  }

  /// Validate against manifest
  Future<ManifestValidationResult> validateManifest(
    String manifestPath,
    String baseDir,
  ) async {
    try {
      final manifestFile = File(manifestPath);
      if (!await manifestFile.exists()) {
        return const ManifestValidationResult(
          isValid: false,
          missingFiles: ['manifest.json'],
        );
      }
      
      final content = await manifestFile.readAsString();
      final List<dynamic> entries = json.decode(content);
      
      int validCount = 0;
      int invalidCount = 0;
      final invalidFiles = <String>[];
      final missingFiles = <String>[];
      
      for (final entry in entries) {
        final manifest = ManifestEntry.fromJson(entry);
        final filePath = '$baseDir/${manifest.fileName}';
        
        final file = File(filePath);
        if (!await file.exists()) {
          missingFiles.add(manifest.fileName);
          invalidCount++;
          continue;
        }
        
        final result = await validateFile(filePath, manifest.checksum);
        if (result.isValid) {
          validCount++;
        } else {
          invalidFiles.add(manifest.fileName);
          invalidCount++;
        }
      }
      
      return ManifestValidationResult(
        isValid: invalidCount == 0 && missingFiles.isEmpty,
        validCount: validCount,
        invalidCount: invalidCount,
        invalidFiles: invalidFiles,
        missingFiles: missingFiles,
      );
      
    } catch (e) {
      return ManifestValidationResult(
        isValid: false,
        invalidFiles: ['Error: $e'],
      );
    }
  }

  /// Validate Surah audio files
  Future<ManifestValidationResult> validateSurahAudio({
    required int surahId,
    required int reciterId,
    required String audioDir,
    required Map<String, String> expectedChecksums,
  }) async {
    int validCount = 0;
    int invalidCount = 0;
    final invalidFiles = <String>[];
    final missingFiles = <String>[];
    
    for (final entry in expectedChecksums.entries) {
      final filePath = '$audioDir/${entry.key}';
      final file = File(filePath);
      
      if (!await file.exists()) {
        missingFiles.add(entry.key);
        invalidCount++;
        continue;
      }
      
      final result = await validateFile(filePath, entry.value);
      if (result.isValid) {
        validCount++;
      } else {
        invalidFiles.add(entry.key);
        invalidCount++;
      }
    }
    
    return ManifestValidationResult(
      isValid: invalidCount == 0 && missingFiles.isEmpty,
      validCount: validCount,
      invalidCount: invalidCount,
      invalidFiles: invalidFiles,
      missingFiles: missingFiles,
    );
  }

  Future<void> dispose() async {
    await _progressController.close();
  }
}

/// Accumulator sink for chunked hashing
class AccumulatorSink<T> implements Sink<T> {
  final List<T> events = [];
  
  @override
  void add(T event) => events.add(event);
  
  @override
  void close() {}
}

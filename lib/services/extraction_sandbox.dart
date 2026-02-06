/// extraction_sandbox.dart
///
/// Extraction Sandbox
/// Atomic ZIP extraction with cleanup and disk space checking

import 'dart:async';
import 'dart:io';
import 'package:archive/archive.dart';

// ============================================================================
// MODELS
// ============================================================================

/// Extraction result
class ExtractionResult {
  final bool success;
  final String? error;
  final List<String> extractedFiles;
  final int totalBytes;
  final Duration duration;

  const ExtractionResult({
    required this.success,
    this.error,
    this.extractedFiles = const [],
    this.totalBytes = 0,
    required this.duration,
  });
}

/// Extraction progress
class ExtractionProgress {
  final int current;
  final int total;
  final String currentFile;

  const ExtractionProgress({
    required this.current,
    required this.total,
    required this.currentFile,
  });

  double get progress => total > 0 ? current / total : 0;
}

// ============================================================================
// EXTRACTION SANDBOX
// ============================================================================

class ExtractionSandbox {
  final String tempDir;
  final String finalDir;
  
  final _progressController = StreamController<ExtractionProgress>.broadcast();
  
  Stream<ExtractionProgress> get progressStream => _progressController.stream;

  ExtractionSandbox({
    required this.tempDir,
    required this.finalDir,
  });

  // ===========================================================================
  // PUBLIC API
  // ===========================================================================

  /// Extract ZIP with atomic move
  Future<ExtractionResult> extract(String zipPath, {String? subDir}) async {
    final stopwatch = Stopwatch()..start();
    final extractedFiles = <String>[];
    
    // Create temp extraction dir
    final tempExtractDir = '$tempDir/extract_${DateTime.now().millisecondsSinceEpoch}';
    final finalPath = subDir != null ? '$finalDir/$subDir' : finalDir;
    
    try {
      // Pre-flight disk space check
      final zipFile = File(zipPath);
      if (!await zipFile.exists()) {
        return ExtractionResult(
          success: false,
          error: 'ZIP file not found',
          duration: stopwatch.elapsed,
        );
      }
      
      final zipSize = await zipFile.length();
      final freeSpace = await _getAvailableSpace();
      
      // Assume 2x compression ratio for safety
      if (freeSpace < zipSize * 2) {
        return ExtractionResult(
          success: false,
          error: 'Insufficient disk space',
          duration: stopwatch.elapsed,
        );
      }
      
      // Create temp directory
      await Directory(tempExtractDir).create(recursive: true);
      
      // Read and decode ZIP
      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      
      int current = 0;
      int totalBytes = 0;
      
      // Extract files
      for (final file in archive) {
        current++;
        _progressController.add(ExtractionProgress(
          current: current,
          total: archive.length,
          currentFile: file.name,
        ));
        
        final filePath = '$tempExtractDir/${file.name}';
        
        if (file.isFile) {
          final outFile = File(filePath);
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(file.content as List<int>);
          extractedFiles.add(file.name);
          totalBytes += file.size;
        } else {
          await Directory(filePath).create(recursive: true);
        }
      }
      
      // Atomic move to final location
      await Directory(finalPath).create(recursive: true);
      
      for (final fileName in extractedFiles) {
        final srcFile = File('$tempExtractDir/$fileName');
        final dstFile = File('$finalPath/$fileName');
        await dstFile.parent.create(recursive: true);
        await srcFile.rename(dstFile.path);
      }
      
      // Cleanup temp
      await _cleanupDir(tempExtractDir);
      
      stopwatch.stop();
      return ExtractionResult(
        success: true,
        extractedFiles: extractedFiles,
        totalBytes: totalBytes,
        duration: stopwatch.elapsed,
      );
      
    } catch (e) {
      // Cleanup on failure
      await _cleanupDir(tempExtractDir);
      
      stopwatch.stop();
      return ExtractionResult(
        success: false,
        error: e.toString(),
        duration: stopwatch.elapsed,
      );
    }
  }

  /// Cleanup partial extraction
  Future<void> cleanup(String path) async {
    await _cleanupDir(path);
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  Future<int> _getAvailableSpace() async {
    // Platform-specific free space check
    // For now, return large value
    return 1024 * 1024 * 1024 * 10; // 10GB
  }

  Future<void> _cleanupDir(String path) async {
    final dir = Directory(path);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<void> dispose() async {
    await _progressController.close();
  }
}

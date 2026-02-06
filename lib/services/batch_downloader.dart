/// batch_downloader.dart
///
/// ZIP Batch Downloader
/// Chunked HTTP downloads with resume and exponential backoff

import 'dart:async';
import 'dart:io';
import 'download_queue.dart';

// ============================================================================
// MODELS
// ============================================================================

/// Download progress event
class DownloadProgress {
  final String id;
  final int downloadedBytes;
  final int? totalBytes;
  final double speedBytesPerSecond;
  final Duration? estimatedRemaining;

  const DownloadProgress({
    required this.id,
    required this.downloadedBytes,
    this.totalBytes,
    this.speedBytesPerSecond = 0,
    this.estimatedRemaining,
  });

  double get progress => totalBytes != null && totalBytes! > 0 ? downloadedBytes / totalBytes! : 0;
}

/// Chunk info for resumable downloads
class ChunkInfo {
  final String id;
  final String tempPath;
  final int downloadedBytes;
  final int? totalBytes;
  final DateTime lastModified;

  const ChunkInfo({
    required this.id,
    required this.tempPath,
    required this.downloadedBytes,
    this.totalBytes,
    required this.lastModified,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'tempPath': tempPath,
    'downloadedBytes': downloadedBytes,
    'totalBytes': totalBytes,
    'lastModified': lastModified.toIso8601String(),
  };

  factory ChunkInfo.fromJson(Map<String, dynamic> json) => ChunkInfo(
    id: json['id'],
    tempPath: json['tempPath'],
    downloadedBytes: json['downloadedBytes'],
    totalBytes: json['totalBytes'],
    lastModified: DateTime.parse(json['lastModified']),
  );
}

// ============================================================================
// CONFIGURATION
// ============================================================================

class BatchDownloaderConfig {
  /// Chunk size for streaming (64KB)
  final int chunkSize;
  
  /// Connection timeout
  final Duration connectionTimeout;
  
  /// Read timeout
  final Duration readTimeout;
  
  /// Base retry delay
  final Duration baseRetryDelay;
  
  /// Max retry delay
  final Duration maxRetryDelay;

  const BatchDownloaderConfig({
    this.chunkSize = 65536,
    this.connectionTimeout = const Duration(seconds: 30),
    this.readTimeout = const Duration(seconds: 60),
    this.baseRetryDelay = const Duration(seconds: 2),
    this.maxRetryDelay = const Duration(minutes: 5),
  });
}

// ============================================================================
// BATCH DOWNLOADER
// ============================================================================

class BatchDownloader {
  final BatchDownloaderConfig config;
  final HttpClient _httpClient;
  
  // Track in-progress downloads
  final Map<String, ChunkInfo> _chunks = {};
  final Map<String, bool> _cancellations = {};
  
  // Streams
  final _progressController = StreamController<DownloadProgress>.broadcast();
  
  Stream<DownloadProgress> get progressStream => _progressController.stream;

  BatchDownloader({this.config = const BatchDownloaderConfig()})
      : _httpClient = HttpClient() {
    _httpClient.connectionTimeout = config.connectionTimeout;
  }

  // ===========================================================================
  // PUBLIC API
  // ===========================================================================

  /// Download file with resume support
  Future<bool> download(DownloadItem item) async {
    final url = item.request.url;
    final destPath = item.request.destinationPath;
    final id = item.id;
    
    _cancellations[id] = false;
    
    // Get or create chunk info
    var chunk = _chunks[id];
    final tempPath = '$destPath.tmp';
    
    int startByte = 0;
    if (chunk != null && await File(chunk.tempPath).exists()) {
      startByte = chunk.downloadedBytes;
    }
    
    try {
      final uri = Uri.parse(url);
      final request = await _httpClient.getUrl(uri);
      
      // Add Range header for resume
      if (startByte > 0) {
        request.headers.add('Range', 'bytes=$startByte-');
      }
      
      final response = await request.close();
      
      // Handle response codes
      if (response.statusCode != 200 && response.statusCode != 206) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      
      // Get total size
      int? totalBytes;
      if (response.statusCode == 206) {
        // Partial content
        final contentRange = response.headers.value('content-range');
        if (contentRange != null) {
          final match = RegExp(r'bytes \d+-\d+/(\d+)').firstMatch(contentRange);
          if (match != null) {
            totalBytes = int.tryParse(match.group(1)!);
          }
        }
        totalBytes = totalBytes ?? (startByte + response.contentLength);
      } else {
        totalBytes = response.contentLength > 0 ? response.contentLength : null;
      }
      
      // Open file for writing
      final file = File(tempPath);
      final sink = file.openWrite(mode: startByte > 0 ? FileMode.append : FileMode.write);
      
      int downloadedBytes = startByte;
      final stopwatch = Stopwatch()..start();
      
      try {
        await for (final data in response) {
          // Check cancellation
          if (_cancellations[id] == true) {
            await sink.close();
            _saveChunk(id, tempPath, downloadedBytes, totalBytes);
            return false;
          }
          
          sink.add(data);
          downloadedBytes += data.length;
          
          // Calculate speed
          final speed = stopwatch.elapsedMilliseconds > 0
              ? downloadedBytes / (stopwatch.elapsedMilliseconds / 1000)
              : 0.0;
          
          // Emit progress
          _progressController.add(DownloadProgress(
            id: id,
            downloadedBytes: downloadedBytes,
            totalBytes: totalBytes,
            speedBytesPerSecond: speed,
            estimatedRemaining: totalBytes != null && speed > 0
                ? Duration(seconds: ((totalBytes - downloadedBytes) / speed).round())
                : null,
          ));
          
          // Update chunk info periodically
          _chunks[id] = ChunkInfo(
            id: id,
            tempPath: tempPath,
            downloadedBytes: downloadedBytes,
            totalBytes: totalBytes,
            lastModified: DateTime.now(),
          );
        }
        
        await sink.close();
        
        // Move temp to final
        await file.rename(destPath);
        
        // Cleanup
        _chunks.remove(id);
        _cancellations.remove(id);
        
        return true;
        
      } catch (e) {
        await sink.close();
        _saveChunk(id, tempPath, downloadedBytes, totalBytes);
        rethrow;
      }
      
    } catch (e) {
      // Don't rethrow for cancellation
      if (_cancellations[id] == true) {
        return false;
      }
      rethrow;
    }
  }

  /// Cancel download
  void cancel(String id) {
    _cancellations[id] = true;
  }

  /// Check if download is resumable
  bool isResumable(String id) {
    return _chunks.containsKey(id);
  }

  /// Get resume info
  ChunkInfo? getResumeInfo(String id) {
    return _chunks[id];
  }

  /// Clear resume data
  Future<void> clearResumeData(String id) async {
    final chunk = _chunks.remove(id);
    if (chunk != null) {
      final file = File(chunk.tempPath);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  // ===========================================================================
  // BATCH OPERATIONS
  // ===========================================================================

  /// Download Surah ZIP (all Ayahs for a Surah)
  Future<bool> downloadSurahZip({
    required int surahId,
    required int reciterId,
    required String baseUrl,
    required String destDir,
  }) async {
    final url = '$baseUrl/surah_${surahId}_reciter_$reciterId.zip';
    final destPath = '$destDir/surah_${surahId}_reciter_$reciterId.zip';
    final id = 'surah_${surahId}_$reciterId';
    
    final item = DownloadItem(
      request: DownloadRequest(
        id: id,
        url: url,
        destinationPath: destPath,
        surahId: surahId,
        reciterId: reciterId,
      ),
    );
    
    return download(item);
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  void _saveChunk(String id, String tempPath, int bytes, int? total) {
    _chunks[id] = ChunkInfo(
      id: id,
      tempPath: tempPath,
      downloadedBytes: bytes,
      totalBytes: total,
      lastModified: DateTime.now(),
    );
  }

  /// Calculate exponential backoff delay
  Duration getRetryDelay(int attempt) {
    final delay = config.baseRetryDelay * (1 << attempt);
    return delay > config.maxRetryDelay ? config.maxRetryDelay : delay;
  }

  // ===========================================================================
  // LIFECYCLE
  // ===========================================================================

  Future<void> dispose() async {
    _httpClient.close();
    await _progressController.close();
  }
}

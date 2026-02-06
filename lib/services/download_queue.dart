/// download_queue.dart
///
/// Download Queue Manager
/// Priority queue with concurrency control and network awareness

import 'dart:async';
import 'dart:collection';

// ============================================================================
// ENUMS
// ============================================================================

/// Download priority
enum DownloadPriority {
  /// User explicitly requested
  userRequested,
  
  /// Predictive preload
  preload,
  
  /// Background sync
  background,
}

/// Download item state
enum DownloadItemState {
  pending,
  downloading,
  paused,
  completed,
  failed,
  cancelled,
}

/// Network preference
enum NetworkPreference {
  wifiOnly,
  wifiPreferred,
  any,
}

/// Current network state
enum NetworkState {
  wifi,
  cellular,
  none,
}

// ============================================================================
// MODELS
// ============================================================================

/// Download request
class DownloadRequest {
  final String id;
  final String url;
  final String destinationPath;
  final DownloadPriority priority;
  final int? surahId;
  final int? reciterId;
  final String? expectedChecksum;
  final int? expectedSizeBytes;

  const DownloadRequest({
    required this.id,
    required this.url,
    required this.destinationPath,
    this.priority = DownloadPriority.userRequested,
    this.surahId,
    this.reciterId,
    this.expectedChecksum,
    this.expectedSizeBytes,
  });
}

/// Download item with state
class DownloadItem {
  final DownloadRequest request;
  DownloadItemState state;
  double progress;
  int downloadedBytes;
  int? totalBytes;
  String? error;
  DateTime queuedAt;
  DateTime? startedAt;
  DateTime? completedAt;
  int retryCount;

  DownloadItem({required this.request})
      : state = DownloadItemState.pending,
        progress = 0.0,
        downloadedBytes = 0,
        queuedAt = DateTime.now(),
        retryCount = 0;

  String get id => request.id;

  Duration get elapsed {
    if (startedAt == null) return Duration.zero;
    final end = completedAt ?? DateTime.now();
    return end.difference(startedAt!);
  }

  double get speedBytesPerSecond {
    if (elapsed.inSeconds == 0) return 0;
    return downloadedBytes / elapsed.inSeconds;
  }

  Duration get estimatedRemaining {
    if (speedBytesPerSecond == 0 || totalBytes == null) return Duration.zero;
    final remaining = totalBytes! - downloadedBytes;
    return Duration(seconds: (remaining / speedBytesPerSecond).round());
  }

  String get accessibilityLabel {
    switch (state) {
      case DownloadItemState.pending: return 'Waiting to download';
      case DownloadItemState.downloading: return 'Downloading ${(progress * 100).round()}%';
      case DownloadItemState.paused: return 'Download paused';
      case DownloadItemState.completed: return 'Download complete';
      case DownloadItemState.failed: return 'Download failed';
      case DownloadItemState.cancelled: return 'Download cancelled';
    }
  }
}

/// Queue statistics
class QueueStats {
  final int pending;
  final int downloading;
  final int completed;
  final int failed;
  final int totalBytes;
  final int downloadedBytes;

  const QueueStats({
    required this.pending,
    required this.downloading,
    required this.completed,
    required this.failed,
    required this.totalBytes,
    required this.downloadedBytes,
  });

  double get overallProgress {
    if (totalBytes == 0) return 0;
    return downloadedBytes / totalBytes;
  }
}

// ============================================================================
// DOWNLOAD QUEUE
// ============================================================================

class DownloadQueueManager {
  // Configuration
  final int maxConcurrent;
  final NetworkPreference networkPreference;
  final int maxRetries;
  final Duration retryDelay;

  // State
  final Map<String, DownloadItem> _items = {};
  final Queue<String> _pendingQueue = Queue();
  final Set<String> _activeDownloads = {};
  NetworkState _networkState = NetworkState.wifi;
  bool _isPaused = false;

  // Streams
  final _itemController = StreamController<DownloadItem>.broadcast();
  final _statsController = StreamController<QueueStats>.broadcast();
  final _completedController = StreamController<DownloadItem>.broadcast();
  final _failedController = StreamController<DownloadItem>.broadcast();

  Stream<DownloadItem> get itemStream => _itemController.stream;
  Stream<QueueStats> get statsStream => _statsController.stream;
  Stream<DownloadItem> get completedStream => _completedController.stream;
  Stream<DownloadItem> get failedStream => _failedController.stream;

  bool get isPaused => _isPaused;
  int get pendingCount => _pendingQueue.length;
  int get activeCount => _activeDownloads.length;

  /// Executor function (set by downloader)
  Future<bool> Function(DownloadItem)? executor;

  /// Progress callback
  void Function(String id, int bytes, int? total)? onProgress;

  DownloadQueueManager({
    this.maxConcurrent = 3,
    this.networkPreference = NetworkPreference.wifiPreferred,
    this.maxRetries = 3,
    this.retryDelay = const Duration(seconds: 5),
  });

  // ===========================================================================
  // PUBLIC API
  // ===========================================================================

  /// Enqueue download request
  String enqueue(DownloadRequest request) {
    if (_items.containsKey(request.id)) {
      return request.id; // Already exists
    }

    final item = DownloadItem(request: request);
    _items[request.id] = item;

    // Insert by priority
    _insertByPriority(request.id, request.priority);

    _emitItem(item);
    _emitStats();
    _processQueue();

    return request.id;
  }

  /// Pause specific download
  void pause(String id) {
    final item = _items[id];
    if (item == null) return;

    if (item.state == DownloadItemState.downloading) {
      item.state = DownloadItemState.paused;
      _activeDownloads.remove(id);
      _emitItem(item);
      _processQueue();
    }
  }

  /// Resume specific download
  void resume(String id) {
    final item = _items[id];
    if (item == null) return;

    if (item.state == DownloadItemState.paused) {
      item.state = DownloadItemState.pending;
      _pendingQueue.addFirst(id);
      _emitItem(item);
      _processQueue();
    }
  }

  /// Cancel specific download
  void cancel(String id) {
    final item = _items[id];
    if (item == null) return;

    item.state = DownloadItemState.cancelled;
    _activeDownloads.remove(id);
    _pendingQueue.remove(id);
    _emitItem(item);
    _emitStats();
  }

  /// Pause all downloads
  void pauseAll() {
    _isPaused = true;
    for (final id in _activeDownloads.toList()) {
      pause(id);
    }
  }

  /// Resume all downloads
  void resumeAll() {
    _isPaused = false;
    for (final item in _items.values) {
      if (item.state == DownloadItemState.paused) {
        resume(item.id);
      }
    }
  }

  /// Cancel all downloads
  void cancelAll() {
    for (final id in _items.keys.toList()) {
      cancel(id);
    }
    _pendingQueue.clear();
    _activeDownloads.clear();
  }

  /// Retry failed download
  void retry(String id) {
    final item = _items[id];
    if (item == null || item.state != DownloadItemState.failed) return;

    item.state = DownloadItemState.pending;
    item.error = null;
    item.progress = 0;
    item.downloadedBytes = 0;
    _pendingQueue.addFirst(id);
    _emitItem(item);
    _processQueue();
  }

  /// Update network state
  void updateNetworkState(NetworkState state) {
    _networkState = state;
    _processQueue();
  }

  /// Get item by ID
  DownloadItem? getItem(String id) => _items[id];

  /// Get all items
  List<DownloadItem> getAllItems() => _items.values.toList();

  /// Get current stats
  QueueStats getStats() {
    int pending = 0, downloading = 0, completed = 0, failed = 0;
    int totalBytes = 0, downloadedBytes = 0;

    for (final item in _items.values) {
      switch (item.state) {
        case DownloadItemState.pending: pending++; break;
        case DownloadItemState.downloading: downloading++; break;
        case DownloadItemState.completed: completed++; break;
        case DownloadItemState.failed: failed++; break;
        default: break;
      }
      if (item.totalBytes != null) totalBytes += item.totalBytes!;
      downloadedBytes += item.downloadedBytes;
    }

    return QueueStats(
      pending: pending,
      downloading: downloading,
      completed: completed,
      failed: failed,
      totalBytes: totalBytes,
      downloadedBytes: downloadedBytes,
    );
  }

  // ===========================================================================
  // QUEUE PROCESSING
  // ===========================================================================

  void _insertByPriority(String id, DownloadPriority priority) {
    if (_pendingQueue.isEmpty) {
      _pendingQueue.add(id);
      return;
    }

    // User requested goes to front
    if (priority == DownloadPriority.userRequested) {
      _pendingQueue.addFirst(id);
    } else {
      _pendingQueue.add(id);
    }
  }

  void _processQueue() {
    if (_isPaused) return;
    if (!_canDownload()) return;

    while (_activeDownloads.length < maxConcurrent && _pendingQueue.isNotEmpty) {
      final id = _pendingQueue.removeFirst();
      final item = _items[id];
      if (item == null) continue;

      _startDownload(item);
    }
  }

  bool _canDownload() {
    switch (networkPreference) {
      case NetworkPreference.wifiOnly:
        return _networkState == NetworkState.wifi;
      case NetworkPreference.wifiPreferred:
        return _networkState != NetworkState.none;
      case NetworkPreference.any:
        return _networkState != NetworkState.none;
    }
  }

  Future<void> _startDownload(DownloadItem item) async {
    item.state = DownloadItemState.downloading;
    item.startedAt = DateTime.now();
    _activeDownloads.add(item.id);
    _emitItem(item);

    try {
      final success = executor != null ? await executor!(item) : false;

      if (success) {
        item.state = DownloadItemState.completed;
        item.progress = 1.0;
        item.completedAt = DateTime.now();
        _completedController.add(item);
      } else {
        _handleFailure(item, 'Download failed');
      }
    } catch (e) {
      _handleFailure(item, e.toString());
    }

    _activeDownloads.remove(item.id);
    _emitItem(item);
    _emitStats();
    _processQueue();
  }

  void _handleFailure(DownloadItem item, String error) {
    item.retryCount++;

    if (item.retryCount < maxRetries) {
      // Schedule retry
      item.state = DownloadItemState.pending;
      item.error = error;
      Future.delayed(retryDelay * item.retryCount, () {
        if (item.state == DownloadItemState.pending) {
          _pendingQueue.addFirst(item.id);
          _processQueue();
        }
      });
    } else {
      item.state = DownloadItemState.failed;
      item.error = error;
      _failedController.add(item);
    }
  }

  /// Update progress for item
  void updateProgress(String id, int bytes, int? total) {
    final item = _items[id];
    if (item == null) return;

    item.downloadedBytes = bytes;
    item.totalBytes = total;
    item.progress = total != null && total > 0 ? bytes / total : 0;
    _emitItem(item);
  }

  // ===========================================================================
  // STREAMS
  // ===========================================================================

  void _emitItem(DownloadItem item) {
    _itemController.add(item);
  }

  void _emitStats() {
    _statsController.add(getStats());
  }

  // ===========================================================================
  // LIFECYCLE
  // ===========================================================================

  Future<void> dispose() async {
    cancelAll();
    await _itemController.close();
    await _statsController.close();
    await _completedController.close();
    await _failedController.close();
  }
}

/// download_screen.dart
///
/// Download Manager Screen
/// Queue display, progress, storage usage

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'dart:async';

// ============================================================================
// MODELS (would import from download_queue.dart)
// ============================================================================

enum DownloadItemState { pending, downloading, paused, completed, failed, cancelled }

class MockDownloadItem {
  final String id;
  final String name;
  final int surahId;
  DownloadItemState state;
  double progress;
  int downloadedBytes;
  int totalBytes;

  MockDownloadItem({
    required this.id,
    required this.name,
    required this.surahId,
    this.state = DownloadItemState.pending,
    this.progress = 0,
    this.downloadedBytes = 0,
    this.totalBytes = 1000000,
  });

  String get accessibilityLabel {
    switch (state) {
      case DownloadItemState.pending: return '$name, waiting';
      case DownloadItemState.downloading: return '$name, ${(progress * 100).round()}%';
      case DownloadItemState.paused: return '$name, paused';
      case DownloadItemState.completed: return '$name, complete';
      case DownloadItemState.failed: return '$name, failed';
      case DownloadItemState.cancelled: return '$name, cancelled';
    }
  }
}

// ============================================================================
// DOWNLOAD SCREEN
// ============================================================================

class DownloadScreen extends StatefulWidget {
  final VoidCallback? onBack;

  const DownloadScreen({super.key, this.onBack});

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen> {
  // Mock data
  final List<MockDownloadItem> _items = [
    MockDownloadItem(id: '1', name: 'Surah Al-Baqara', surahId: 2, state: DownloadItemState.downloading, progress: 0.45),
    MockDownloadItem(id: '2', name: 'Surah Al-Imran', surahId: 3, state: DownloadItemState.pending),
    MockDownloadItem(id: '3', name: 'Surah Al-Kahf', surahId: 18, state: DownloadItemState.completed, progress: 1.0),
  ];
  
  int _usedBytes = 512 * 1024 * 1024; // 512MB
  int _quotaBytes = 2 * 1024 * 1024 * 1024; // 2GB

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final activeCount = _items.where((i) => i.state == DownloadItemState.downloading).length;
      SemanticsService.announce(
        'Downloads. $activeCount active. ${_formatBytes(_usedBytes)} of ${_formatBytes(_quotaBytes)} used.',
        TextDirection.ltr,
      );
    });
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  void _pauseItem(MockDownloadItem item) {
    setState(() {
      item.state = DownloadItemState.paused;
    });
    SemanticsService.announce('${item.name} paused', TextDirection.ltr);
  }

  void _resumeItem(MockDownloadItem item) {
    setState(() {
      item.state = DownloadItemState.downloading;
    });
    SemanticsService.announce('${item.name} resuming', TextDirection.ltr);
  }

  void _cancelItem(MockDownloadItem item) {
    setState(() {
      item.state = DownloadItemState.cancelled;
    });
    SemanticsService.announce('${item.name} cancelled', TextDirection.ltr);
  }

  void _retryItem(MockDownloadItem item) {
    setState(() {
      item.state = DownloadItemState.pending;
      item.progress = 0;
    });
    SemanticsService.announce('${item.name} retrying', TextDirection.ltr);
  }

  @override
  Widget build(BuildContext context) {
    final usagePercent = _usedBytes / _quotaBytes;

    return Scaffold(
      appBar: AppBar(
        leading: Semantics(
          button: true,
          label: 'Back',
          child: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: widget.onBack,
          ),
        ),
        title: Semantics(
          header: true,
          child: const Text('Downloads'),
        ),
      ),
      body: Column(
        children: [
          // Storage usage bar
          Semantics(
            label: 'Storage usage ${(usagePercent * 100).round()}%. '
                '${_formatBytes(_usedBytes)} of ${_formatBytes(_quotaBytes)} used.',
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ExcludeSemantics(
                        child: Text(
                          'Storage',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                      ExcludeSemantics(
                        child: Text(
                          '${_formatBytes(_usedBytes)} / ${_formatBytes(_quotaBytes)}',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: usagePercent,
                      backgroundColor: Colors.grey[200],
                      color: usagePercent > 0.9
                          ? Colors.red
                          : usagePercent > 0.7
                              ? Colors.orange
                              : Theme.of(context).primaryColor,
                      minHeight: 8,
                    ),
                  ),
                  if (usagePercent > 0.8)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        usagePercent > 0.9
                            ? 'Storage almost full'
                            : 'Storage running low',
                        style: TextStyle(
                          color: usagePercent > 0.9 ? Colors.red : Colors.orange,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          
          const Divider(height: 1),
          
          // Download list
          Expanded(
            child: _items.isEmpty
                ? Center(
                    child: Semantics(
                      label: 'No downloads',
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.download_done, size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            'No downloads',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (context, index) => _DownloadItemTile(
                      item: _items[index],
                      onPause: () => _pauseItem(_items[index]),
                      onResume: () => _resumeItem(_items[index]),
                      onCancel: () => _cancelItem(_items[index]),
                      onRetry: () => _retryItem(_items[index]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// DOWNLOAD ITEM TILE
// ============================================================================

class _DownloadItemTile extends StatelessWidget {
  final MockDownloadItem item;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;

  const _DownloadItemTile({
    required this.item,
    this.onPause,
    this.onResume,
    this.onCancel,
    this.onRetry,
  });

  IconData get _stateIcon {
    switch (item.state) {
      case DownloadItemState.pending: return Icons.hourglass_empty;
      case DownloadItemState.downloading: return Icons.downloading;
      case DownloadItemState.paused: return Icons.pause;
      case DownloadItemState.completed: return Icons.check_circle;
      case DownloadItemState.failed: return Icons.error;
      case DownloadItemState.cancelled: return Icons.cancel;
    }
  }

  Color get _stateColor {
    switch (item.state) {
      case DownloadItemState.pending: return Colors.grey;
      case DownloadItemState.downloading: return Colors.blue;
      case DownloadItemState.paused: return Colors.orange;
      case DownloadItemState.completed: return Colors.green;
      case DownloadItemState.failed: return Colors.red;
      case DownloadItemState.cancelled: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: item.accessibilityLabel,
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // State icon
            Icon(_stateIcon, color: _stateColor, size: 28),
            const SizedBox(width: 16),
            
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: Text(
                      item.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (item.state == DownloadItemState.downloading) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: item.progress,
                        minHeight: 4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ExcludeSemantics(
                      child: Text(
                        '${(item.progress * 100).round()}%',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            
            // Actions
            if (item.state == DownloadItemState.downloading)
              Semantics(
                button: true,
                label: 'Pause',
                child: IconButton(
                  icon: const Icon(Icons.pause),
                  onPressed: onPause,
                ),
              ),
            if (item.state == DownloadItemState.paused)
              Semantics(
                button: true,
                label: 'Resume',
                child: IconButton(
                  icon: const Icon(Icons.play_arrow),
                  onPressed: onResume,
                ),
              ),
            if (item.state == DownloadItemState.failed)
              Semantics(
                button: true,
                label: 'Retry',
                child: IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: onRetry,
                ),
              ),
            if (item.state != DownloadItemState.completed &&
                item.state != DownloadItemState.cancelled)
              Semantics(
                button: true,
                label: 'Cancel',
                child: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: onCancel,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

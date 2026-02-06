/// playback_command_queue.dart
///
/// FIFO Command Queue for Audio Playback
/// Prevents race conditions between voice, repeat, and UI commands
/// 
/// Priority Order: Stop > Pause > Seek > Play > Repeat

import 'dart:async';
import 'dart:collection';

/// Command priority levels
enum CommandPriority {
  /// Lowest priority (background operations)
  low,
  
  /// Normal priority (user-initiated)
  normal,
  
  /// High priority (important operations)
  high,
  
  /// Critical priority (stop/emergency)
  critical,
}

/// Command types
enum CommandType {
  play,
  pause,
  stop,
  seek,
  load,
  preload,
  repeatStart,
  repeatStop,
  volumeSet,
  volumeDuck,
  volumeRestore,
  speedSet,
}

/// Cancellation token for command execution
class CancellationToken {
  bool _isCancelled = false;
  final List<VoidCallback> _listeners = [];

  /// Check if cancelled
  bool get isCancelled => _isCancelled;

  /// Cancel this token
  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    for (final listener in _listeners) {
      listener();
    }
    _listeners.clear();
  }

  /// Add cancellation listener
  void addListener(VoidCallback listener) {
    if (_isCancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }

  /// Remove listener
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  /// Throw if cancelled
  void throwIfCancelled() {
    if (_isCancelled) {
      throw CancelledException();
    }
  }
}

/// Exception thrown when command is cancelled
class CancelledException implements Exception {
  @override
  String toString() => 'Command was cancelled';
}

typedef VoidCallback = void Function();

/// Playback command with metadata
class PlaybackCommand {
  final CommandType type;
  final CommandPriority priority;
  final Map<String, dynamic> params;
  final CancellationToken? token;
  final DateTime createdAt;
  final Completer<bool> completer;

  PlaybackCommand({
    required this.type,
    this.priority = CommandPriority.normal,
    this.params = const {},
    this.token,
  })  : createdAt = DateTime.now(),
        completer = Completer<bool>();

  /// Get result future
  Future<bool> get result => completer.future;

  /// Check if this command should preempt another
  bool shouldPreempt(PlaybackCommand other) {
    // Higher priority always preempts
    if (priority.index > other.priority.index) return true;
    
    // Stop preempts everything
    if (type == CommandType.stop) return true;
    
    // Pause preempts play
    if (type == CommandType.pause && other.type == CommandType.play) {
      return true;
    }
    
    return false;
  }

  /// Check if this command supersedes another (same type, newer)
  bool supersedes(PlaybackCommand other) {
    if (type != other.type) return false;
    return createdAt.isAfter(other.createdAt);
  }

  @override
  String toString() => 'Command($type, priority=$priority)';
}

/// Command execution result
class CommandResult {
  final bool success;
  final String? error;
  final DateTime executedAt;
  final Duration executionTime;

  CommandResult({
    required this.success,
    this.error,
    required this.executedAt,
    required this.executionTime,
  });
}

/// Playback Command Queue
/// 
/// Manages command execution with:
/// - FIFO ordering within same priority
/// - Priority preemption
/// - Cancellation support
/// - Command coalescing (duplicate removal)
class PlaybackCommandQueue {
  final Queue<PlaybackCommand> _queue = Queue();
  PlaybackCommand? _currentCommand;
  bool _isProcessing = false;
  bool _isPaused = false;

  final _commandExecutor = StreamController<PlaybackCommand>.broadcast();
  final _resultController = StreamController<CommandResult>.broadcast();

  /// Stream of commands being executed
  Stream<PlaybackCommand> get onCommandExecuting => _commandExecutor.stream;

  /// Stream of command results
  Stream<CommandResult> get onCommandResult => _resultController.stream;

  /// Current queue length
  int get length => _queue.length;

  /// Whether queue is empty
  bool get isEmpty => _queue.isEmpty;

  /// Whether currently processing
  bool get isProcessing => _isProcessing;

  /// Command executor function (set by AudioService)
  Future<bool> Function(PlaybackCommand)? executor;

  /// Enqueue a command
  Future<bool> enqueue(PlaybackCommand command) {
    // Check for cancellation
    if (command.token?.isCancelled ?? false) {
      command.completer.complete(false);
      return command.result;
    }

    // Remove superseded commands
    _queue.removeWhere((queued) {
      if (command.supersedes(queued)) {
        queued.token?.cancel();
        queued.completer.complete(false);
        return true;
      }
      return false;
    });

    // Check if should preempt current
    if (_currentCommand != null && command.shouldPreempt(_currentCommand!)) {
      _currentCommand!.token?.cancel();
    }

    // Insert by priority
    _insertByPriority(command);

    // Start processing if not already
    if (!_isProcessing && !_isPaused) {
      _processQueue();
    }

    return command.result;
  }

  /// Insert command in priority order
  void _insertByPriority(PlaybackCommand command) {
    if (_queue.isEmpty) {
      _queue.add(command);
      return;
    }

    // Find insertion point
    final list = _queue.toList();
    int insertIndex = list.length;
    
    for (int i = 0; i < list.length; i++) {
      if (command.priority.index > list[i].priority.index) {
        insertIndex = i;
        break;
      }
    }

    list.insert(insertIndex, command);
    _queue.clear();
    _queue.addAll(list);
  }

  /// Process queue
  Future<void> _processQueue() async {
    if (_isProcessing || _isPaused || _queue.isEmpty) return;
    
    _isProcessing = true;

    while (_queue.isNotEmpty && !_isPaused) {
      _currentCommand = _queue.removeFirst();
      final command = _currentCommand!;

      // Skip cancelled commands
      if (command.token?.isCancelled ?? false) {
        command.completer.complete(false);
        continue;
      }

      _commandExecutor.add(command);
      final startTime = DateTime.now();

      try {
        bool success = false;
        
        if (executor != null) {
          success = await executor!(command);
        }

        final result = CommandResult(
          success: success,
          executedAt: startTime,
          executionTime: DateTime.now().difference(startTime),
        );

        _resultController.add(result);
        command.completer.complete(success);

      } catch (e) {
        final result = CommandResult(
          success: false,
          error: e.toString(),
          executedAt: startTime,
          executionTime: DateTime.now().difference(startTime),
        );

        _resultController.add(result);
        command.completer.complete(false);
      }
    }

    _currentCommand = null;
    _isProcessing = false;
  }

  /// Pause queue processing
  void pause() {
    _isPaused = true;
  }

  /// Resume queue processing
  void resume() {
    _isPaused = false;
    if (!_isProcessing) {
      _processQueue();
    }
  }

  /// Cancel all pending commands
  void cancelAll() {
    for (final command in _queue) {
      command.token?.cancel();
      command.completer.complete(false);
    }
    _queue.clear();
  }

  /// Cancel commands of specific type
  void cancelType(CommandType type) {
    _queue.removeWhere((command) {
      if (command.type == type) {
        command.token?.cancel();
        command.completer.complete(false);
        return true;
      }
      return false;
    });
  }

  /// Clear queue (without cancelling)
  void clear() {
    _queue.clear();
  }

  /// Dispose resources
  Future<void> dispose() async {
    cancelAll();
    await _commandExecutor.close();
    await _resultController.close();
  }

  // ===========================================================================
  // CONVENIENCE METHODS
  // ===========================================================================

  /// Enqueue play command
  Future<bool> play() {
    return enqueue(PlaybackCommand(
      type: CommandType.play,
      priority: CommandPriority.normal,
    ));
  }

  /// Enqueue pause command
  Future<bool> doPause() {
    return enqueue(PlaybackCommand(
      type: CommandType.pause,
      priority: CommandPriority.high,
    ));
  }

  /// Enqueue stop command (critical priority)
  Future<bool> stop() {
    return enqueue(PlaybackCommand(
      type: CommandType.stop,
      priority: CommandPriority.critical,
    ));
  }

  /// Enqueue seek command
  Future<bool> seek(double positionSeconds) {
    return enqueue(PlaybackCommand(
      type: CommandType.seek,
      priority: CommandPriority.normal,
      params: {'position': positionSeconds},
    ));
  }

  /// Enqueue load command
  Future<bool> load(String filePath, {bool preload = false}) {
    return enqueue(PlaybackCommand(
      type: CommandType.load,
      priority: CommandPriority.normal,
      params: {'filePath': filePath, 'preload': preload},
    ));
  }

  /// Enqueue repeat start command
  Future<bool> startRepeat({
    required int mode,
    required int count,
    int? startAyah,
    int? endAyah,
    int pauseIntervalMs = 0,
  }) {
    return enqueue(PlaybackCommand(
      type: CommandType.repeatStart,
      priority: CommandPriority.normal,
      params: {
        'mode': mode,
        'count': count,
        'startAyah': startAyah,
        'endAyah': endAyah,
        'pauseIntervalMs': pauseIntervalMs,
      },
    ));
  }

  /// Enqueue repeat stop command
  Future<bool> stopRepeat() {
    return enqueue(PlaybackCommand(
      type: CommandType.repeatStop,
      priority: CommandPriority.high,
    ));
  }
}

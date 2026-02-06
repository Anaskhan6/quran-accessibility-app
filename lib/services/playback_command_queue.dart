/// playback_command_queue.dart
///
/// FIFO Command Queue for Audio Playback
/// Priority: Stop > Pause > Seek > Play > Repeat

import 'dart:async';
import 'dart:collection';

enum CommandPriority { low, normal, high, critical }
enum CommandType { play, pause, stop, seek, load, preload, repeatStart, repeatStop, volumeSet, volumeDuck, volumeRestore, speedSet }

typedef VoidCallback = void Function();

class CancellationToken {
  bool _isCancelled = false;
  final List<VoidCallback> _listeners = [];

  bool get isCancelled => _isCancelled;

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    for (final listener in _listeners) listener();
    _listeners.clear();
  }

  void addListener(VoidCallback listener) => _isCancelled ? listener() : _listeners.add(listener);
}

class CancelledException implements Exception {
  @override
  String toString() => 'Command was cancelled';
}

class PlaybackCommand {
  final CommandType type;
  final CommandPriority priority;
  final Map<String, dynamic> params;
  final CancellationToken? token;
  final DateTime createdAt;
  final Completer<bool> completer;

  PlaybackCommand({required this.type, this.priority = CommandPriority.normal, this.params = const {}, this.token})
      : createdAt = DateTime.now(),
        completer = Completer<bool>();

  Future<bool> get result => completer.future;

  bool shouldPreempt(PlaybackCommand other) {
    if (priority.index > other.priority.index) return true;
    if (type == CommandType.stop) return true;
    if (type == CommandType.pause && other.type == CommandType.play) return true;
    return false;
  }

  bool supersedes(PlaybackCommand other) => type == other.type && createdAt.isAfter(other.createdAt);
}

class CommandResult {
  final bool success;
  final String? error;
  final DateTime executedAt;
  final Duration executionTime;

  CommandResult({required this.success, this.error, required this.executedAt, required this.executionTime});
}

class PlaybackCommandQueue {
  final Queue<PlaybackCommand> _queue = Queue();
  PlaybackCommand? _currentCommand;
  bool _isProcessing = false;
  bool _isPaused = false;

  final _commandExecutor = StreamController<PlaybackCommand>.broadcast();
  final _resultController = StreamController<CommandResult>.broadcast();

  Stream<PlaybackCommand> get onCommandExecuting => _commandExecutor.stream;
  Stream<CommandResult> get onCommandResult => _resultController.stream;
  int get length => _queue.length;
  bool get isEmpty => _queue.isEmpty;
  bool get isProcessing => _isProcessing;

  Future<bool> Function(PlaybackCommand)? executor;

  Future<bool> enqueue(PlaybackCommand command) {
    if (command.token?.isCancelled ?? false) {
      command.completer.complete(false);
      return command.result;
    }

    _queue.removeWhere((queued) {
      if (command.supersedes(queued)) {
        queued.token?.cancel();
        queued.completer.complete(false);
        return true;
      }
      return false;
    });

    if (_currentCommand != null && command.shouldPreempt(_currentCommand!)) {
      _currentCommand!.token?.cancel();
    }

    _insertByPriority(command);
    if (!_isProcessing && !_isPaused) _processQueue();
    return command.result;
  }

  void _insertByPriority(PlaybackCommand command) {
    if (_queue.isEmpty) { _queue.add(command); return; }
    final list = _queue.toList();
    int insertIndex = list.length;
    for (int i = 0; i < list.length; i++) {
      if (command.priority.index > list[i].priority.index) { insertIndex = i; break; }
    }
    list.insert(insertIndex, command);
    _queue.clear();
    _queue.addAll(list);
  }

  Future<void> _processQueue() async {
    if (_isProcessing || _isPaused || _queue.isEmpty) return;
    _isProcessing = true;

    while (_queue.isNotEmpty && !_isPaused) {
      _currentCommand = _queue.removeFirst();
      final command = _currentCommand!;
      if (command.token?.isCancelled ?? false) { command.completer.complete(false); continue; }

      _commandExecutor.add(command);
      final startTime = DateTime.now();

      try {
        bool success = executor != null ? await executor!(command) : false;
        _resultController.add(CommandResult(success: success, executedAt: startTime, executionTime: DateTime.now().difference(startTime)));
        command.completer.complete(success);
      } catch (e) {
        _resultController.add(CommandResult(success: false, error: e.toString(), executedAt: startTime, executionTime: DateTime.now().difference(startTime)));
        command.completer.complete(false);
      }
    }

    _currentCommand = null;
    _isProcessing = false;
  }

  void pause() => _isPaused = true;
  void resume() { _isPaused = false; if (!_isProcessing) _processQueue(); }
  void cancelAll() { for (final cmd in _queue) { cmd.token?.cancel(); cmd.completer.complete(false); } _queue.clear(); }
  void cancelType(CommandType type) { _queue.removeWhere((cmd) { if (cmd.type == type) { cmd.token?.cancel(); cmd.completer.complete(false); return true; } return false; }); }
  void clear() => _queue.clear();

  Future<void> dispose() async { cancelAll(); await _commandExecutor.close(); await _resultController.close(); }

  // Convenience methods
  Future<bool> play() => enqueue(PlaybackCommand(type: CommandType.play, priority: CommandPriority.normal));
  Future<bool> doPause() => enqueue(PlaybackCommand(type: CommandType.pause, priority: CommandPriority.high));
  Future<bool> stop() => enqueue(PlaybackCommand(type: CommandType.stop, priority: CommandPriority.critical));
  Future<bool> seek(double positionSeconds) => enqueue(PlaybackCommand(type: CommandType.seek, priority: CommandPriority.normal, params: {'position': positionSeconds}));
  Future<bool> load(String filePath, {bool preload = false}) => enqueue(PlaybackCommand(type: CommandType.load, priority: CommandPriority.normal, params: {'filePath': filePath, 'preload': preload}));
  Future<bool> startRepeat({required int mode, required int count, int? startAyah, int? endAyah, int pauseIntervalMs = 0}) =>
      enqueue(PlaybackCommand(type: CommandType.repeatStart, priority: CommandPriority.normal, params: {'mode': mode, 'count': count, 'startAyah': startAyah, 'endAyah': endAyah, 'pauseIntervalMs': pauseIntervalMs}));
  Future<bool> stopRepeat() => enqueue(PlaybackCommand(type: CommandType.repeatStop, priority: CommandPriority.high));
}

/// player_screen.dart
///
/// Player Screen
/// Playback controls bound to PlaybackStateController

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'dart:async';

// Import services (would use proper imports in real app)
// import '../services/playback_state_controller.dart';
// import '../services/repeat_orchestrator.dart';

// ============================================================================
// PLAYER SCREEN
// ============================================================================

class PlayerScreen extends StatefulWidget {
  final int surahId;
  final String surahName;
  final int totalAyahs;
  final void Function()? onVoiceActivate;
  final void Function()? onBack;

  const PlayerScreen({
    super.key,
    required this.surahId,
    required this.surahName,
    required this.totalAyahs,
    this.onVoiceActivate,
    this.onBack,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  // State - would be bound to PlaybackStateController streams
  bool _isPlaying = false;
  int _currentAyah = 1;
  double _progress = 0.0;
  Duration _position = Duration.zero;
  Duration _duration = const Duration(minutes: 2);
  bool _isRepeatEnabled = false;
  int _repeatCount = 0;
  int _repeatTarget = 3;
  double _speed = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SemanticsService.announce(
        'Player. ${widget.surahName}. ${widget.totalAyahs} verses. Double tap play to begin.',
        TextDirection.ltr,
      );
    });
  }

  void _togglePlay() {
    setState(() {
      _isPlaying = !_isPlaying;
    });
    SemanticsService.announce(
      _isPlaying ? 'Playing' : 'Paused',
      TextDirection.ltr,
    );
  }

  void _previousAyah() {
    if (_currentAyah > 1) {
      setState(() {
        _currentAyah--;
        _progress = 0;
      });
      SemanticsService.announce(
        'Ayah $_currentAyah',
        TextDirection.ltr,
      );
    }
  }

  void _nextAyah() {
    if (_currentAyah < widget.totalAyahs) {
      setState(() {
        _currentAyah++;
        _progress = 0;
      });
      SemanticsService.announce(
        'Ayah $_currentAyah',
        TextDirection.ltr,
      );
    }
  }

  void _toggleRepeat() {
    setState(() {
      _isRepeatEnabled = !_isRepeatEnabled;
      _repeatCount = 0;
    });
    SemanticsService.announce(
      _isRepeatEnabled
          ? 'Repeat enabled. $_repeatTarget times.'
          : 'Repeat disabled',
      TextDirection.ltr,
    );
  }

  void _adjustSpeed(double delta) {
    setState(() {
      _speed = (_speed + delta).clamp(0.5, 2.0);
    });
    SemanticsService.announce(
      'Speed ${_speed}x',
      TextDirection.ltr,
    );
  }

  void _seekToAyah(int ayah) {
    setState(() {
      _currentAyah = ayah.clamp(1, widget.totalAyahs);
      _progress = 0;
    });
    SemanticsService.announce(
      'Ayah $_currentAyah',
      TextDirection.ltr,
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Semantics(
          button: true,
          label: 'Back to Surah list',
          child: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: widget.onBack,
          ),
        ),
        title: Semantics(
          header: true,
          child: Text(widget.surahName),
        ),
        actions: [
          Semantics(
            button: true,
            label: 'Voice command',
            child: IconButton(
              icon: const Icon(Icons.mic),
              onPressed: widget.onVoiceActivate,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            
            // Surah info
            Semantics(
              label: '${widget.surahName}, Ayah $_currentAyah of ${widget.totalAyahs}',
              child: Column(
                children: [
                  ExcludeSemantics(
                    child: Text(
                      widget.surahName,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ExcludeSemantics(
                    child: Text(
                      'Ayah $_currentAyah of ${widget.totalAyahs}',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 48),
            
            // Repeat indicator
            if (_isRepeatEnabled)
              Semantics(
                liveRegion: true,
                label: 'Repeat $_repeatCount of $_repeatTarget',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: ExcludeSemantics(
                    child: Text(
                      'Repeat $_repeatCount / $_repeatTarget',
                      style: TextStyle(
                        color: Theme.of(context).primaryColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            
            const Spacer(),
            
            // Progress slider
            Semantics(
              slider: true,
              label: 'Playback progress',
              value: '${(_progress * 100).round()} percent',
              hint: 'Swipe left or right to seek',
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 4,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                      ),
                      child: Slider(
                        value: _progress,
                        onChanged: (value) {
                          setState(() => _progress = value);
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          ExcludeSemantics(
                            child: Text(_formatDuration(_position)),
                          ),
                          ExcludeSemantics(
                            child: Text(_formatDuration(_duration)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 32),
            
            // Playback controls
            _PlaybackControls(
              isPlaying: _isPlaying,
              isRepeatEnabled: _isRepeatEnabled,
              speed: _speed,
              onPlayPause: _togglePlay,
              onPrevious: _previousAyah,
              onNext: _nextAyah,
              onRepeatToggle: _toggleRepeat,
              onSpeedDown: () => _adjustSpeed(-0.25),
              onSpeedUp: () => _adjustSpeed(0.25),
            ),
            
            const SizedBox(height: 48),
          ],
        ),
      ),
      
      // Voice FAB
      floatingActionButton: Semantics(
        button: true,
        label: 'Voice command',
        child: FloatingActionButton(
          onPressed: widget.onVoiceActivate,
          child: const Icon(Icons.mic),
        ),
      ),
    );
  }
}

// ============================================================================
// PLAYBACK CONTROLS
// ============================================================================

class _PlaybackControls extends StatelessWidget {
  final bool isPlaying;
  final bool isRepeatEnabled;
  final double speed;
  final VoidCallback? onPlayPause;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onRepeatToggle;
  final VoidCallback? onSpeedDown;
  final VoidCallback? onSpeedUp;

  const _PlaybackControls({
    required this.isPlaying,
    required this.isRepeatEnabled,
    required this.speed,
    this.onPlayPause,
    this.onPrevious,
    this.onNext,
    this.onRepeatToggle,
    this.onSpeedDown,
    this.onSpeedUp,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Main controls row
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Previous
            Semantics(
              button: true,
              label: 'Previous Ayah',
              child: IconButton(
                icon: const Icon(Icons.skip_previous),
                iconSize: 48,
                onPressed: onPrevious,
              ),
            ),
            
            const SizedBox(width: 24),
            
            // Play/Pause
            Semantics(
              button: true,
              label: isPlaying ? 'Pause' : 'Play',
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                  ),
                  iconSize: 48,
                  onPressed: onPlayPause,
                ),
              ),
            ),
            
            const SizedBox(width: 24),
            
            // Next
            Semantics(
              button: true,
              label: 'Next Ayah',
              child: IconButton(
                icon: const Icon(Icons.skip_next),
                iconSize: 48,
                onPressed: onNext,
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 24),
        
        // Secondary controls
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Speed down
            Semantics(
              button: true,
              label: 'Decrease speed',
              child: IconButton(
                icon: const Icon(Icons.remove),
                onPressed: onSpeedDown,
              ),
            ),
            
            // Speed indicator
            Semantics(
              label: 'Speed ${speed}x',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: ExcludeSemantics(
                  child: Text(
                    '${speed}x',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
            
            // Speed up
            Semantics(
              button: true,
              label: 'Increase speed',
              child: IconButton(
                icon: const Icon(Icons.add),
                onPressed: onSpeedUp,
              ),
            ),
            
            const SizedBox(width: 24),
            
            // Repeat toggle
            Semantics(
              button: true,
              label: isRepeatEnabled ? 'Disable repeat' : 'Enable repeat',
              toggled: isRepeatEnabled,
              child: IconButton(
                icon: Icon(
                  Icons.repeat,
                  color: isRepeatEnabled ? Theme.of(context).primaryColor : null,
                ),
                onPressed: onRepeatToggle,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

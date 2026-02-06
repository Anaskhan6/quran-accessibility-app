/// playback_controls.dart
///
/// Reusable Playback Controls Widget
/// Large touch zones, semantic labels, state reflection

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

// ============================================================================
// PLAYBACK BUTTON
// ============================================================================

/// Large accessible button for playback controls
class PlaybackButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final double size;
  final bool isPrimary;
  final bool isToggled;

  const PlaybackButton({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.size = 48,
    this.isPrimary = false,
    this.isToggled = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Semantics(
      button: true,
      label: label,
      enabled: onPressed != null,
      toggled: isToggled,
      child: Material(
        color: isPrimary ? theme.primaryColor : Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Container(
            width: size + 16,
            height: size + 16,
            // Minimum touch target 48x48
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            child: Icon(
              icon,
              size: size,
              color: isPrimary
                  ? Colors.white
                  : isToggled
                      ? theme.primaryColor
                      : null,
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// PLAY PAUSE BUTTON
// ============================================================================

class PlayPauseButton extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback? onPressed;
  final double size;

  const PlayPauseButton({
    super.key,
    required this.isPlaying,
    this.onPressed,
    this.size = 64,
  });

  @override
  Widget build(BuildContext context) {
    return PlaybackButton(
      icon: isPlaying ? Icons.pause : Icons.play_arrow,
      label: isPlaying ? 'Pause' : 'Play',
      onPressed: onPressed,
      size: size,
      isPrimary: true,
    );
  }
}

// ============================================================================
// SEEK SLIDER
// ============================================================================

class SeekSlider extends StatelessWidget {
  final double value;
  final Duration position;
  final Duration duration;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;

  const SeekSlider({
    super.key,
    required this.value,
    required this.position,
    required this.duration,
    this.onChanged,
    this.onChangeEnd,
  });

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      slider: true,
      label: 'Playback position',
      value: '${_formatDuration(position)} of ${_formatDuration(duration)}',
      hint: 'Swipe to seek',
      increasedValue: 'Seek forward',
      decreasedValue: 'Seek backward',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 10,
                  pressedElevation: 8,
                ),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
              ),
              child: Slider(
                value: value.clamp(0.0, 1.0),
                onChanged: onChanged,
                onChangeEnd: onChangeEnd,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ExcludeSemantics(
                    child: Text(
                      _formatDuration(position),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                  ExcludeSemantics(
                    child: Text(
                      _formatDuration(duration),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// REPEAT CONTROLS
// ============================================================================

class RepeatControls extends StatelessWidget {
  final bool isEnabled;
  final int currentCount;
  final int targetCount;
  final VoidCallback? onToggle;
  final VoidCallback? onIncreaseCount;
  final VoidCallback? onDecreaseCount;

  const RepeatControls({
    super.key,
    required this.isEnabled,
    required this.currentCount,
    required this.targetCount,
    this.onToggle,
    this.onIncreaseCount,
    this.onDecreaseCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Semantics(
      container: true,
      label: isEnabled
          ? 'Repeat enabled. $currentCount of $targetCount'
          : 'Repeat disabled',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Toggle
          PlaybackButton(
            icon: Icons.repeat,
            label: isEnabled ? 'Disable repeat' : 'Enable repeat',
            onPressed: onToggle,
            isToggled: isEnabled,
          ),
          
          if (isEnabled) ...[
            const SizedBox(width: 8),
            
            // Count controls
            Semantics(
              button: true,
              label: 'Decrease repeat count',
              child: IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: onDecreaseCount,
                iconSize: 24,
              ),
            ),
            
            Semantics(
              liveRegion: true,
              label: '$targetCount times',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: ExcludeSemantics(
                  child: Text(
                    '${targetCount}x',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.primaryColor,
                    ),
                  ),
                ),
              ),
            ),
            
            Semantics(
              button: true,
              label: 'Increase repeat count',
              child: IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: onIncreaseCount,
                iconSize: 24,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================================
// SPEED CONTROLS
// ============================================================================

class SpeedControls extends StatelessWidget {
  final double speed;
  final VoidCallback? onIncrease;
  final VoidCallback? onDecrease;
  final VoidCallback? onReset;

  const SpeedControls({
    super.key,
    required this.speed,
    this.onIncrease,
    this.onDecrease,
    this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Playback speed ${speed}x',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            label: 'Slower',
            child: IconButton(
              icon: const Icon(Icons.remove),
              onPressed: onDecrease,
            ),
          ),
          
          GestureDetector(
            onDoubleTap: onReset,
            child: Semantics(
              label: '${speed}x. Double tap to reset',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ExcludeSemantics(
                  child: Text(
                    '${speed}x',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ),
          
          Semantics(
            button: true,
            label: 'Faster',
            child: IconButton(
              icon: const Icon(Icons.add),
              onPressed: onIncrease,
            ),
          ),
        ],
      ),
    );
  }
}

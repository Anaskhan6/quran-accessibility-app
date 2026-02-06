/// voice_trigger_button.dart
///
/// Voice Trigger Button
/// FAB with listening indicator and accessibility

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

// ============================================================================
// VOICE TRIGGER BUTTON
// ============================================================================

class VoiceTriggerButton extends StatefulWidget {
  final bool isListening;
  final bool isProcessing;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPressStart;
  final VoidCallback? onLongPressEnd;

  const VoiceTriggerButton({
    super.key,
    this.isListening = false,
    this.isProcessing = false,
    this.onPressed,
    this.onLongPressStart,
    this.onLongPressEnd,
  });

  @override
  State<VoiceTriggerButton> createState() => _VoiceTriggerButtonState();
}

class _VoiceTriggerButtonState extends State<VoiceTriggerButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(VoiceTriggerButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isListening && !oldWidget.isListening) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isListening && oldWidget.isListening) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String get _accessibilityLabel {
    if (widget.isProcessing) return 'Processing voice command';
    if (widget.isListening) return 'Listening. Tap to stop';
    return 'Voice command. Tap to speak';
  }

  String get _accessibilityHint {
    if (widget.isProcessing) return 'Please wait';
    if (widget.isListening) return 'Speak your command now';
    return 'Double tap to activate voice, or hold to speak';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      label: _accessibilityLabel,
      hint: _accessibilityHint,
      child: GestureDetector(
        onLongPressStart: (_) => widget.onLongPressStart?.call(),
        onLongPressEnd: (_) => widget.onLongPressEnd?.call(),
        child: AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: widget.isListening ? _pulseAnimation.value : 1.0,
              child: FloatingActionButton.large(
                onPressed: widget.onPressed,
                backgroundColor: widget.isListening
                    ? Colors.red
                    : widget.isProcessing
                        ? Colors.orange
                        : theme.primaryColor,
                child: widget.isProcessing
                    ? const SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 3,
                        ),
                      )
                    : Icon(
                        widget.isListening ? Icons.mic : Icons.mic_none,
                        size: 36,
                        color: Colors.white,
                      ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ============================================================================
// MINI VOICE BUTTON (for app bar)
// ============================================================================

class MiniVoiceButton extends StatelessWidget {
  final bool isListening;
  final VoidCallback? onPressed;

  const MiniVoiceButton({
    super.key,
    this.isListening = false,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: isListening ? 'Stop listening' : 'Voice command',
      child: IconButton(
        icon: Icon(
          isListening ? Icons.mic : Icons.mic_none,
          color: isListening ? Colors.red : null,
        ),
        onPressed: onPressed,
      ),
    );
  }
}

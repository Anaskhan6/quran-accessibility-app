/// transcript_overlay.dart
///
/// Transcript Overlay
/// Shows speech transcript and confidence confirmation

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

// ============================================================================
// TRANSCRIPT OVERLAY
// ============================================================================

class TranscriptOverlay extends StatelessWidget {
  final String transcript;
  final double confidence;
  final bool isListening;
  final bool needsConfirmation;
  final String? confirmationPrompt;
  final VoidCallback? onConfirm;
  final VoidCallback? onDeny;
  final VoidCallback? onDismiss;

  const TranscriptOverlay({
    super.key,
    required this.transcript,
    required this.confidence,
    this.isListening = false,
    this.needsConfirmation = false,
    this.confirmationPrompt,
    this.onConfirm,
    this.onDeny,
    this.onDismiss,
  });

  Color get _confidenceColor {
    if (confidence >= 0.8) return Colors.green;
    if (confidence >= 0.5) return Colors.orange;
    return Colors.red;
  }

  String get _confidenceLabel {
    if (confidence >= 0.8) return 'High confidence';
    if (confidence >= 0.5) return 'Medium confidence';
    return 'Low confidence';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black87,
      child: SafeArea(
        child: Semantics(
          container: true,
          liveRegion: true,
          label: needsConfirmation
              ? confirmationPrompt ?? 'Confirm command'
              : isListening
                  ? 'Listening'
                  : transcript,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Close button
                Align(
                  alignment: Alignment.topRight,
                  child: Semantics(
                    button: true,
                    label: 'Close',
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: onDismiss,
                    ),
                  ),
                ),
                
                const Spacer(),
                
                // Listening indicator
                if (isListening) ...[
                  const _ListeningIndicator(),
                  const SizedBox(height: 24),
                  ExcludeSemantics(
                    child: Text(
                      'Listening...',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
                
                // Transcript
                if (transcript.isNotEmpty && !isListening) ...[
                  ExcludeSemantics(
                    child: Text(
                      '"$transcript"',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Confidence indicator
                  ExcludeSemantics(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: _confidenceColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _confidenceLabel,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                
                // Confirmation prompt
                if (needsConfirmation) ...[
                  const SizedBox(height: 32),
                  ExcludeSemantics(
                    child: Text(
                      confirmationPrompt ?? 'Did you mean this?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Confirm/Deny buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Semantics(
                        button: true,
                        label: 'No, cancel',
                        child: OutlinedButton.icon(
                          onPressed: onDeny,
                          icon: const Icon(Icons.close),
                          label: const Text('No'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 24),
                      Semantics(
                        button: true,
                        label: 'Yes, confirm',
                        child: ElevatedButton.icon(
                          onPressed: onConfirm,
                          icon: const Icon(Icons.check),
                          label: const Text('Yes'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// LISTENING INDICATOR
// ============================================================================

class _ListeningIndicator extends StatefulWidget {
  const _ListeningIndicator();

  @override
  State<_ListeningIndicator> createState() => _ListeningIndicatorState();
}

class _ListeningIndicatorState extends State<_ListeningIndicator>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      5,
      (i) => AnimationController(
        duration: const Duration(milliseconds: 600),
        vsync: this,
      ),
    );
    _animations = _controllers.map((c) {
      return Tween<double>(begin: 0.3, end: 1.0).animate(
        CurvedAnimation(parent: c, curve: Curves.easeInOut),
      );
    }).toList();

    // Stagger animations
    for (var i = 0; i < _controllers.length; i++) {
      Future.delayed(Duration(milliseconds: i * 100), () {
        if (mounted) {
          _controllers[i].repeat(reverse: true);
        }
      });
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(5, (i) {
          return AnimatedBuilder(
            animation: _animations[i],
            builder: (context, child) {
              return Container(
                width: 8,
                height: 60 * _animations[i].value,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}

// ============================================================================
// PARTIAL TRANSCRIPT CHIP
// ============================================================================

class PartialTranscriptChip extends StatelessWidget {
  final String text;

  const PartialTranscriptChip({
    super.key,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();

    return Semantics(
      liveRegion: true,
      label: text,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(20),
        ),
        child: ExcludeSemantics(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}

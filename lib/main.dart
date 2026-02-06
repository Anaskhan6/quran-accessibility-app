/// main.dart
///
/// App Entry Point
/// Navigation with accessibility theme

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'screens/surah_list_screen.dart';
import 'screens/player_screen.dart';
import 'screens/download_screen.dart';
import 'widgets/transcript_overlay.dart';

void main() {
  runApp(const QuranAccessibilityApp());
}

// ============================================================================
// APP
// ============================================================================

class QuranAccessibilityApp extends StatelessWidget {
  const QuranAccessibilityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quran',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: const AppShell(),
    );
  }

  ThemeData _buildTheme() {
    // Accessibility-first theme
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1B5E20), // Islamic green
        brightness: Brightness.light,
      ),
      
      // Large touch targets
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.all(12),
        ),
      ),
      
      // Readable text
      textTheme: const TextTheme(
        bodyLarge: TextStyle(fontSize: 18),
        bodyMedium: TextStyle(fontSize: 16),
        titleLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
      
      // Elevated buttons
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      
      // App bar
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        toolbarHeight: 64,
      ),
      
      // FAB
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        sizeConstraints: BoxConstraints.tightFor(width: 72, height: 72),
      ),
    );
  }
}

// ============================================================================
// APP SHELL
// ============================================================================

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;
  int? _selectedSurahId;
  bool _showVoiceOverlay = false;
  bool _isListening = false;
  String _transcript = '';
  double _confidence = 0;
  bool _needsConfirmation = false;

  void _onTabChanged(int index) {
    setState(() {
      _currentIndex = index;
      _selectedSurahId = null;
    });
    
    final labels = ['Surah List', 'Downloads'];
    SemanticsService.announce(
      labels[index],
      TextDirection.ltr,
    );
  }

  void _onSurahSelected(int surahId) {
    setState(() {
      _selectedSurahId = surahId;
    });
  }

  void _onPlayerBack() {
    setState(() {
      _selectedSurahId = null;
    });
  }

  void _onVoiceActivate() {
    setState(() {
      _showVoiceOverlay = true;
      _isListening = true;
      _transcript = '';
    });
    
    // Simulate listening
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _isListening) {
        setState(() {
          _isListening = false;
          _transcript = 'Play Surah Rahman';
          _confidence = 0.85;
        });
      }
    });
  }

  void _onVoiceDismiss() {
    setState(() {
      _showVoiceOverlay = false;
      _isListening = false;
    });
  }

  void _onVoiceConfirm() {
    setState(() {
      _showVoiceOverlay = false;
      _needsConfirmation = false;
    });
    SemanticsService.announce('Playing Surah Rahman', TextDirection.ltr);
    // Would route to playback via intent router
  }

  void _onVoiceDeny() {
    setState(() {
      _needsConfirmation = false;
      _transcript = '';
    });
    SemanticsService.announce('Cancelled', TextDirection.ltr);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Main content
        Scaffold(
          body: _buildBody(),
          bottomNavigationBar: _selectedSurahId == null
              ? _buildBottomNav()
              : null,
        ),
        
        // Voice overlay
        if (_showVoiceOverlay)
          TranscriptOverlay(
            transcript: _transcript,
            confidence: _confidence,
            isListening: _isListening,
            needsConfirmation: _needsConfirmation,
            confirmationPrompt: 'Play Surah Rahman?',
            onConfirm: _onVoiceConfirm,
            onDeny: _onVoiceDeny,
            onDismiss: _onVoiceDismiss,
          ),
      ],
    );
  }

  Widget _buildBody() {
    // Player screen
    if (_selectedSurahId != null) {
      return PlayerScreen(
        surahId: _selectedSurahId!,
        surahName: 'Surah ${_selectedSurahId}',
        totalAyahs: 100,
        onBack: _onPlayerBack,
        onVoiceActivate: _onVoiceActivate,
      );
    }
    
    // Tab screens
    switch (_currentIndex) {
      case 0:
        return SurahListScreen(
          onSurahSelected: _onSurahSelected,
          onVoiceActivate: _onVoiceActivate,
        );
      case 1:
        return DownloadScreen(
          onBack: () => _onTabChanged(0),
        );
      default:
        return SurahListScreen(
          onSurahSelected: _onSurahSelected,
          onVoiceActivate: _onVoiceActivate,
        );
    }
  }

  Widget _buildBottomNav() {
    return Semantics(
      container: true,
      label: 'Navigation',
      child: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onTabChanged,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.menu_book),
            label: 'Quran',
          ),
          NavigationDestination(
            icon: Icon(Icons.download),
            label: 'Downloads',
          ),
        ],
      ),
    );
  }
}

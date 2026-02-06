/// surah_list_screen.dart
///
/// Surah List Screen
/// Accessibility-first navigation with TalkBack/VoiceOver support

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'dart:async';

// ============================================================================
// SURAH DATA (Static - real app would load from database)
// ============================================================================

class SurahInfo {
  final int id;
  final String nameArabic;
  final String nameEnglish;
  final String nameTrans;
  final int ayahCount;
  final String revelationType;
  final bool isDownloaded;

  const SurahInfo({
    required this.id,
    required this.nameArabic,
    required this.nameEnglish,
    required this.nameTrans,
    required this.ayahCount,
    required this.revelationType,
    this.isDownloaded = false,
  });

  String get accessibilityLabel => 
      'Surah $nameEnglish, $nameTrans, $ayahCount verses, $revelationType'
      '${isDownloaded ? ", Available offline" : ""}';
}

// Sample Surahs (would be loaded from database)
const List<SurahInfo> sampleSurahs = [
  SurahInfo(id: 1, nameArabic: 'الفاتحة', nameEnglish: 'Al-Fatiha', nameTrans: 'The Opening', ayahCount: 7, revelationType: 'Meccan'),
  SurahInfo(id: 2, nameArabic: 'البقرة', nameEnglish: 'Al-Baqara', nameTrans: 'The Cow', ayahCount: 286, revelationType: 'Medinan'),
  SurahInfo(id: 3, nameArabic: 'آل عمران', nameEnglish: 'Al-Imran', nameTrans: 'Family of Imran', ayahCount: 200, revelationType: 'Medinan'),
  SurahInfo(id: 18, nameArabic: 'الكهف', nameEnglish: 'Al-Kahf', nameTrans: 'The Cave', ayahCount: 110, revelationType: 'Meccan'),
  SurahInfo(id: 36, nameArabic: 'يس', nameEnglish: 'Ya-Sin', nameTrans: 'Ya Sin', ayahCount: 83, revelationType: 'Meccan'),
  SurahInfo(id: 55, nameArabic: 'الرحمن', nameEnglish: 'Ar-Rahman', nameTrans: 'The Merciful', ayahCount: 78, revelationType: 'Medinan'),
  SurahInfo(id: 67, nameArabic: 'الملك', nameEnglish: 'Al-Mulk', nameTrans: 'The Sovereignty', ayahCount: 30, revelationType: 'Meccan'),
  SurahInfo(id: 112, nameArabic: 'الإخلاص', nameEnglish: 'Al-Ikhlas', nameTrans: 'Sincerity', ayahCount: 4, revelationType: 'Meccan'),
  SurahInfo(id: 113, nameArabic: 'الفلق', nameEnglish: 'Al-Falaq', nameTrans: 'The Daybreak', ayahCount: 5, revelationType: 'Meccan'),
  SurahInfo(id: 114, nameArabic: 'الناس', nameEnglish: 'An-Nas', nameTrans: 'Mankind', ayahCount: 6, revelationType: 'Meccan'),
];

// ============================================================================
// SURAH LIST SCREEN
// ============================================================================

class SurahListScreen extends StatefulWidget {
  final void Function(int surahId)? onSurahSelected;
  final void Function()? onVoiceActivate;

  const SurahListScreen({
    super.key,
    this.onSurahSelected,
    this.onVoiceActivate,
  });

  @override
  State<SurahListScreen> createState() => _SurahListScreenState();
}

class _SurahListScreenState extends State<SurahListScreen> {
  final _scrollController = ScrollController();
  List<SurahInfo> _surahs = sampleSurahs;
  String _searchQuery = '';
  
  @override
  void initState() {
    super.initState();
    // Announce screen on load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SemanticsService.announce(
        'Surah List. ${_surahs.length} Surahs available. Swipe to navigate.',
        TextDirection.ltr,
      );
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onSurahTap(SurahInfo surah) {
    SemanticsService.announce(
      'Selected ${surah.nameEnglish}',
      TextDirection.ltr,
    );
    widget.onSurahSelected?.call(surah.id);
  }

  void _filterSurahs(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _surahs = sampleSurahs;
      } else {
        _surahs = sampleSurahs.where((s) =>
            s.nameEnglish.toLowerCase().contains(query.toLowerCase()) ||
            s.nameTrans.toLowerCase().contains(query.toLowerCase()) ||
            s.id.toString() == query
        ).toList();
      }
    });
    
    SemanticsService.announce(
      '${_surahs.length} results',
      TextDirection.ltr,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          header: true,
          child: const Text('Quran'),
        ),
        actions: [
          // Voice trigger button
          Semantics(
            button: true,
            label: 'Activate voice command',
            hint: 'Double tap to speak a command',
            child: IconButton(
              icon: const Icon(Icons.mic),
              iconSize: 28,
              onPressed: widget.onVoiceActivate,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Semantics(
            textField: true,
            label: 'Search Surahs',
            hint: 'Type Surah name or number',
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search Surah...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                ),
                onChanged: _filterSurahs,
              ),
            ),
          ),
          
          // Surah list
          Expanded(
            child: Semantics(
              label: 'Surah list',
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _surahs.length,
                itemBuilder: (context, index) => _SurahListTile(
                  surah: _surahs[index],
                  onTap: () => _onSurahTap(_surahs[index]),
                ),
              ),
            ),
          ),
        ],
      ),
      
      // Voice FAB
      floatingActionButton: Semantics(
        button: true,
        label: 'Voice command',
        hint: 'Double tap and hold to speak',
        child: FloatingActionButton.large(
          onPressed: widget.onVoiceActivate,
          child: const Icon(Icons.mic, size: 36),
        ),
      ),
    );
  }
}

// ============================================================================
// SURAH LIST TILE
// ============================================================================

class _SurahListTile extends StatelessWidget {
  final SurahInfo surah;
  final VoidCallback? onTap;

  const _SurahListTile({
    required this.surah,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: surah.accessibilityLabel,
      hint: 'Double tap to play',
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          // Minimum touch target 48x48
          constraints: const BoxConstraints(minHeight: 72),
          child: Row(
            children: [
              // Surah number
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: ExcludeSemantics(
                    child: Text(
                      '${surah.id}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                  ),
                ),
              ),
              
              const SizedBox(width: 16),
              
              // Surah info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ExcludeSemantics(
                      child: Text(
                        surah.nameEnglish,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    ExcludeSemantics(
                      child: Text(
                        '${surah.nameTrans} • ${surah.ayahCount} verses',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              // Arabic name
              ExcludeSemantics(
                child: Text(
                  surah.nameArabic,
                  style: const TextStyle(
                    fontSize: 20,
                    fontFamily: 'Amiri', // Arabic font
                  ),
                ),
              ),
              
              // Download indicator
              if (surah.isDownloaded)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                    Icons.offline_pin,
                    color: Colors.green[600],
                    size: 20,
                    semanticLabel: 'Available offline',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// database_helper.dart
///
/// SQLite database initialization and management
/// Implements V3 normalized schema with integrity triggers

import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'schema_v3.dart' as schema;

/// Database helper singleton
class DatabaseHelper {
  static DatabaseHelper? _instance;
  static Database? _database;

  DatabaseHelper._internal();

  /// Get singleton instance
  static DatabaseHelper get instance {
    _instance ??= DatabaseHelper._internal();
    return _instance!;
  }

  /// Get database instance
  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  /// Initialize database
  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'quran.db');

    return await openDatabase(
      path,
      version: schema.schemaVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: _onConfigure,
    );
  }

  /// Configure database (enable foreign keys)
  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  /// Create database schema
  Future<void> _onCreate(Database db, int version) async {
    // Execute full schema creation script
    final statements = schema.createSchemaSQL.split(';');
    for (final statement in statements) {
      final trimmed = statement.trim();
      if (trimmed.isNotEmpty) {
        await db.execute(trimmed);
      }
    }
  }

  /// Handle schema upgrades
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 3) {
      // Migration from V2 to V3 (if needed)
      await _migrateV2ToV3(db);
    }
  }

  /// V2 to V3 migration
  Future<void> _migrateV2ToV3(Database db) async {
    // Create new V3 tables
    await db.execute('''
      CREATE TABLE IF NOT EXISTS JuzMap (
        id INTEGER PRIMARY KEY,
        juz_number INTEGER NOT NULL CHECK(juz_number BETWEEN 1 AND 30),
        surah_id INTEGER NOT NULL,
        start_ayah INTEGER NOT NULL,
        end_ayah INTEGER NOT NULL,
        FOREIGN KEY (surah_id) REFERENCES Surah(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS RecitationAudio (
        id INTEGER PRIMARY KEY,
        ayah_id INTEGER NOT NULL,
        reciter_id INTEGER NOT NULL,
        audio_url TEXT,
        local_audio_path TEXT,
        duration_seconds REAL,
        audio_checksum TEXT,
        FOREIGN KEY (ayah_id) REFERENCES Ayah(id) ON DELETE CASCADE,
        FOREIGN KEY (reciter_id) REFERENCES Reciter(id) ON DELETE SET NULL,
        UNIQUE(ayah_id, reciter_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS AyahTranslation (
        id INTEGER PRIMARY KEY,
        ayah_id INTEGER NOT NULL,
        translation_id INTEGER NOT NULL,
        text_content TEXT NOT NULL,
        FOREIGN KEY (ayah_id) REFERENCES Ayah(id) ON DELETE CASCADE,
        FOREIGN KEY (translation_id) REFERENCES Translation(id) ON DELETE CASCADE,
        UNIQUE(ayah_id, translation_id)
      )
    ''');

    // Create indexes
    await db.execute('CREATE INDEX IF NOT EXISTS idx_juz_lookup ON JuzMap(juz_number)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_recitation_lookup ON RecitationAudio(ayah_id, reciter_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_translation_lookup ON AyahTranslation(ayah_id, translation_id)');
  }

  // ==========================================================================
  // SURAH OPERATIONS
  // ==========================================================================

  /// Get all Surahs
  Future<List<Map<String, dynamic>>> getAllSurahs() async {
    final db = await database;
    return await db.query('Surah', orderBy: 'id');
  }

  /// Get Surah by ID
  Future<Map<String, dynamic>?> getSurah(int id) async {
    final db = await database;
    final results = await db.query(
      'Surah',
      where: 'id = ?',
      whereArgs: [id],
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Insert Surah (returns ID)
  Future<int> insertSurah(Map<String, dynamic> surah) async {
    final db = await database;
    return await db.insert('Surah', surah);
  }

  // ==========================================================================
  // AYAH OPERATIONS
  // ==========================================================================

  /// Get Ayah by Surah and number
  Future<Map<String, dynamic>?> getAyah(int surahId, int ayahNumber) async {
    final db = await database;
    final results = await db.query(
      'Ayah',
      where: 'surah_id = ? AND ayah_number = ?',
      whereArgs: [surahId, ayahNumber],
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Get all Ayahs for a Surah
  Future<List<Map<String, dynamic>>> getAyahsBySurah(int surahId) async {
    final db = await database;
    return await db.query(
      'Ayah',
      where: 'surah_id = ?',
      whereArgs: [surahId],
      orderBy: 'ayah_number',
    );
  }

  /// Get Ayah with translation
  Future<Map<String, dynamic>?> getAyahWithTranslation(
    int surahId,
    int ayahNumber,
    int translationId,
  ) async {
    final db = await database;
    final results = await db.rawQuery('''
      SELECT 
        a.id, a.surah_id, a.ayah_number, a.text_arabic, a.text_checksum,
        at.text_content AS translation
      FROM Ayah a
      LEFT JOIN AyahTranslation at ON a.id = at.ayah_id
      WHERE a.surah_id = ? 
        AND a.ayah_number = ?
        AND (at.translation_id = ? OR at.translation_id IS NULL)
    ''', [surahId, ayahNumber, translationId]);
    return results.isNotEmpty ? results.first : null;
  }

  /// Insert Ayah (text only - normalized)
  Future<int> insertAyah(Map<String, dynamic> ayah) async {
    final db = await database;
    return await db.insert('Ayah', ayah);
  }

  // ==========================================================================
  // RECITATION AUDIO OPERATIONS
  // ==========================================================================

  /// Get audio path for Ayah
  Future<String?> getAudioPath(int surahId, int ayahNumber, int reciterId) async {
    final db = await database;
    final results = await db.rawQuery('''
      SELECT local_audio_path, audio_url
      FROM RecitationAudio ra
      JOIN Ayah a ON ra.ayah_id = a.id
      WHERE a.surah_id = ? 
        AND a.ayah_number = ?
        AND ra.reciter_id = ?
    ''', [surahId, ayahNumber, reciterId]);

    if (results.isEmpty) return null;
    
    // Prefer local path, fallback to URL
    final localPath = results.first['local_audio_path'] as String?;
    final audioUrl = results.first['audio_url'] as String?;
    return localPath ?? audioUrl;
  }

  /// Insert recitation audio
  Future<int> insertRecitationAudio(Map<String, dynamic> audio) async {
    final db = await database;
    return await db.insert('RecitationAudio', audio);
  }

  /// Update local audio path (after download)
  Future<int> updateLocalAudioPath(int audioId, String localPath) async {
    final db = await database;
    return await db.update(
      'RecitationAudio',
      {'local_audio_path': localPath},
      where: 'id = ?',
      whereArgs: [audioId],
    );
  }

  // ==========================================================================
  // USER PROGRESS OPERATIONS
  // ==========================================================================

  /// Get user progress
  Future<Map<String, dynamic>?> getUserProgress() async {
    final db = await database;
    final results = await db.query('UserProgress', where: 'id = ?', whereArgs: [1]);
    return results.isNotEmpty ? results.first : null;
  }

  /// Update user progress
  Future<int> updateUserProgress(Map<String, dynamic> progress) async {
    final db = await database;
    progress['last_updated'] = DateTime.now().toIso8601String();
    return await db.update(
      'UserProgress',
      progress,
      where: 'id = ?',
      whereArgs: [1],
    );
  }

  /// Save repeat state
  Future<void> saveRepeatState({
    required String mode,
    required int count,
    required int current,
    int? startAyah,
    int? endAyah,
  }) async {
    await updateUserProgress({
      'repeat_mode': mode,
      'repeat_count': count,
      'repeat_current': current,
      'repeat_start_ayah': startAyah,
      'repeat_end_ayah': endAyah,
    });
  }

  /// Clear repeat state
  Future<void> clearRepeatState() async {
    await updateUserProgress({
      'repeat_mode': null,
      'repeat_count': 1,
      'repeat_current': 0,
      'repeat_start_ayah': null,
      'repeat_end_ayah': null,
    });
  }

  // ==========================================================================
  // JUZ OPERATIONS
  // ==========================================================================

  /// Get Ayahs in a Juz
  Future<List<Map<String, dynamic>>> getJuzAyahs(int juzNumber) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT a.id, a.surah_id, a.ayah_number, a.text_arabic
      FROM JuzMap jm
      JOIN Ayah a ON a.surah_id = jm.surah_id
      WHERE jm.juz_number = ?
        AND a.ayah_number BETWEEN jm.start_ayah AND jm.end_ayah
      ORDER BY jm.surah_id, a.ayah_number
    ''', [juzNumber]);
  }

  // ==========================================================================
  // ERROR LOGGING
  // ==========================================================================

  /// Log error
  Future<void> logError(String errorType, String? context) async {
    final db = await database;
    await db.insert('ErrorLog', {
      'error_type': errorType,
      'context': context,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Get recent errors
  Future<List<Map<String, dynamic>>> getRecentErrors({int limit = 50}) async {
    final db = await database;
    return await db.query(
      'ErrorLog',
      orderBy: 'timestamp DESC',
      limit: limit,
    );
  }

  // ==========================================================================
  // DOWNLOADS OPERATIONS
  // ==========================================================================

  /// Check download status
  Future<bool> isDownloaded(int surahId, int reciterId) async {
    final db = await database;
    final results = await db.query(
      'Downloads',
      where: 'surah_id = ? AND reciter_id = ? AND downloaded = 1',
      whereArgs: [surahId, reciterId],
    );
    return results.isNotEmpty;
  }

  /// Mark Surah as downloaded
  Future<void> markDownloaded(
    int surahId,
    int reciterId,
    String downloadPath,
    String? checksum,
  ) async {
    final db = await database;
    await db.insert(
      'Downloads',
      {
        'surah_id': surahId,
        'reciter_id': reciterId,
        'download_path': downloadPath,
        'downloaded': 1,
        'download_date': DateTime.now().toIso8601String(),
        'zip_checksum': checksum,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ==========================================================================
  // UTILITY METHODS
  // ==========================================================================

  /// Close database
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }

  /// Delete database (for testing/reset)
  Future<void> deleteDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'quran.db');
    await databaseFactory.deleteDatabase(path);
    _database = null;
  }
}

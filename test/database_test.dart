/// database_test.dart
///
/// Unit tests for V3 database schema and operations
/// Tests data integrity triggers and query performance

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart';

// Import schema (adjust path as needed)
// import 'package:quran_app/database/schema_v3.dart' as schema;

/// V3 Schema SQL (minimal version for testing)
const _testSchemaSQL = '''
CREATE TABLE Surah (
  id INTEGER PRIMARY KEY,
  name_arabic TEXT NOT NULL,
  name_english TEXT NOT NULL,
  transliteration TEXT NOT NULL,
  total_ayah INTEGER NOT NULL,
  revelation_type TEXT CHECK(revelation_type IN ('Meccan', 'Medinan')),
  text_checksum TEXT NOT NULL
);

CREATE TABLE Ayah (
  id INTEGER PRIMARY KEY,
  surah_id INTEGER NOT NULL,
  ayah_number INTEGER NOT NULL,
  text_arabic TEXT NOT NULL,
  text_checksum TEXT NOT NULL,
  FOREIGN KEY (surah_id) REFERENCES Surah(id) ON DELETE CASCADE,
  UNIQUE(surah_id, ayah_number)
);

CREATE INDEX idx_ayah_lookup ON Ayah(surah_id, ayah_number);

-- Data integrity trigger
CREATE TRIGGER prevent_quran_modification
BEFORE UPDATE OF text_arabic ON Ayah
BEGIN
  SELECT RAISE(ABORT, 'Quran text cannot be modified');
END;

-- Ayah number validation
CREATE TRIGGER validate_ayah_number
BEFORE INSERT ON Ayah
BEGIN
  SELECT CASE
    WHEN NEW.ayah_number > (SELECT total_ayah FROM Surah WHERE id = NEW.surah_id)
    THEN RAISE(ABORT, 'Ayah number exceeds Surah total')
  END;
END;
''';

void main() {
  // Initialize FFI for desktop testing
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, version) async {
        final statements = _testSchemaSQL.split(';');
        for (final stmt in statements) {
          final trimmed = stmt.trim();
          if (trimmed.isNotEmpty) {
            await db.execute(trimmed);
          }
        }
      },
    );

    // Insert test Surah
    await db.insert('Surah', {
      'id': 1,
      'name_arabic': 'الفاتحة',
      'name_english': 'The Opening',
      'transliteration': 'Al-Fatiha',
      'total_ayah': 7,
      'revelation_type': 'Meccan',
      'text_checksum': 'sha256_hash_here',
    });
  });

  tearDown(() async {
    await db.close();
  });

  group('Database Schema Tests', () {
    test('Surah table structure is correct', () async {
      final result = await db.rawQuery(
        'PRAGMA table_info(Surah)',
      );

      final columns = result.map((r) => r['name'] as String).toSet();

      expect(columns, containsAll([
        'id',
        'name_arabic',
        'name_english',
        'transliteration',
        'total_ayah',
        'revelation_type',
        'text_checksum',
      ]));
    });

    test('Ayah table structure is correct', () async {
      final result = await db.rawQuery(
        'PRAGMA table_info(Ayah)',
      );

      final columns = result.map((r) => r['name'] as String).toSet();

      expect(columns, containsAll([
        'id',
        'surah_id',
        'ayah_number',
        'text_arabic',
        'text_checksum',
      ]));
    });

    test('Index exists on Ayah lookup', () async {
      final result = await db.rawQuery(
        'PRAGMA index_list(Ayah)',
      );

      final indexNames = result.map((r) => r['name'] as String).toList();

      expect(
        indexNames.any((name) => name.contains('ayah_lookup')),
        isTrue,
        reason: 'Expected idx_ayah_lookup index to exist',
      );
    });
  });

  group('Data Integrity Tests', () {
    test('Quran text cannot be modified', () async {
      // Insert test Ayah
      await db.insert('Ayah', {
        'surah_id': 1,
        'ayah_number': 1,
        'text_arabic': 'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
        'text_checksum': 'checksum_1',
      });

      // Attempt to modify - should throw
      expect(
        () => db.update(
          'Ayah',
          {'text_arabic': 'Modified text'},
          where: 'ayah_number = ?',
          whereArgs: [1],
        ),
        throwsA(isA<DatabaseException>().having(
          (e) => e.toString(),
          'message',
          contains('Quran text cannot be modified'),
        )),
      );
    });

    test('Ayah number cannot exceed Surah total', () async {
      // Al-Fatiha has 7 Ayahs, inserting Ayah 10 should fail
      expect(
        () => db.insert('Ayah', {
          'surah_id': 1,
          'ayah_number': 10, // Invalid: > 7
          'text_arabic': 'Test',
          'text_checksum': 'checksum',
        }),
        throwsA(isA<DatabaseException>().having(
          (e) => e.toString(),
          'message',
          contains('Ayah number exceeds Surah total'),
        )),
      );
    });

    test('Valid Ayah insertion succeeds', () async {
      final result = await db.insert('Ayah', {
        'surah_id': 1,
        'ayah_number': 7, // Valid: <= 7
        'text_arabic': 'صِرَاطَ الَّذِينَ أَنْعَمْتَ عَلَيْهِمْ',
        'text_checksum': 'checksum_7',
      });

      expect(result, greaterThan(0));
    });
  });

  group('Query Performance Tests', () {
    test('Ayah lookup by Surah and number is fast', () async {
      // Insert all 7 Ayahs of Al-Fatiha
      for (int i = 1; i <= 7; i++) {
        await db.insert('Ayah', {
          'surah_id': 1,
          'ayah_number': i,
          'text_arabic': 'Ayah $i text',
          'text_checksum': 'checksum_$i',
        });
      }

      final stopwatch = Stopwatch()..start();

      // Perform indexed lookup
      final result = await db.query(
        'Ayah',
        where: 'surah_id = ? AND ayah_number = ?',
        whereArgs: [1, 5],
      );

      stopwatch.stop();

      expect(result, hasLength(1));
      expect(result.first['ayah_number'], equals(5));

      // Performance target: <5ms for indexed lookup
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(50), // Allow more time for test environment
        reason: 'Indexed lookup should be fast',
      );
    });
  });
}

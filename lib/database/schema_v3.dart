/// schema_v3.dart
///
/// V3 Normalized Database Schema for Quran App
/// Per ER_Diagram_V3.md specification
///
/// Tables:
/// - Surah, Ayah, JuzMap, Reciter, RecitationAudio
/// - Translation, AyahTranslation, Downloads, UserProgress, ErrorLog
///
/// Includes:
/// - Data integrity triggers (prevent Quran text modification)
/// - Performance indexes on all FK columns

/// Schema version for migrations
const int schemaVersion = 3;

/// Complete SQL schema creation script
const String createSchemaSQL = '''
-- ============================================================================
-- SURAH TABLE
-- ============================================================================
CREATE TABLE Surah (
  id INTEGER PRIMARY KEY,
  name_arabic TEXT NOT NULL,
  name_english TEXT NOT NULL,
  transliteration TEXT NOT NULL,
  total_ayah INTEGER NOT NULL,
  revelation_type TEXT CHECK(revelation_type IN ('Meccan', 'Medinan')),
  text_checksum TEXT NOT NULL
);

-- ============================================================================
-- AYAH TABLE (Text Only - Normalized)
-- ============================================================================
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

-- ============================================================================
-- JUZ MAP TABLE (Enables "Play Juz 3")
-- ============================================================================
CREATE TABLE JuzMap (
  id INTEGER PRIMARY KEY,
  juz_number INTEGER NOT NULL CHECK(juz_number BETWEEN 1 AND 30),
  surah_id INTEGER NOT NULL,
  start_ayah INTEGER NOT NULL,
  end_ayah INTEGER NOT NULL,
  FOREIGN KEY (surah_id) REFERENCES Surah(id) ON DELETE CASCADE
);

CREATE INDEX idx_juz_lookup ON JuzMap(juz_number);
CREATE INDEX idx_juz_surah ON JuzMap(surah_id);

-- ============================================================================
-- RECITER TABLE
-- ============================================================================
CREATE TABLE Reciter (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  style TEXT,
  bitrate INTEGER DEFAULT 64,
  language_code TEXT DEFAULT 'ar'
);

-- ============================================================================
-- RECITATION AUDIO TABLE (Normalized - Multi-Reciter Support)
-- ============================================================================
CREATE TABLE RecitationAudio (
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
);

CREATE INDEX idx_recitation_lookup ON RecitationAudio(ayah_id, reciter_id);

-- ============================================================================
-- TRANSLATION TABLE
-- ============================================================================
CREATE TABLE Translation (
  id INTEGER PRIMARY KEY,
  language_code TEXT NOT NULL,
  translator_name TEXT NOT NULL,
  audio_available INTEGER DEFAULT 0
);

-- ============================================================================
-- AYAH TRANSLATION TABLE (Normalized - Multi-Translation Support)
-- ============================================================================
CREATE TABLE AyahTranslation (
  id INTEGER PRIMARY KEY,
  ayah_id INTEGER NOT NULL,
  translation_id INTEGER NOT NULL,
  text_content TEXT NOT NULL,
  FOREIGN KEY (ayah_id) REFERENCES Ayah(id) ON DELETE CASCADE,
  FOREIGN KEY (translation_id) REFERENCES Translation(id) ON DELETE CASCADE,
  UNIQUE(ayah_id, translation_id)
);

CREATE INDEX idx_translation_lookup ON AyahTranslation(ayah_id, translation_id);

-- ============================================================================
-- DOWNLOADS TABLE (Batch ZIP Support)
-- ============================================================================
CREATE TABLE Downloads (
  id INTEGER PRIMARY KEY,
  surah_id INTEGER NOT NULL,
  reciter_id INTEGER NOT NULL,
  translation_id INTEGER,
  download_path TEXT NOT NULL,
  downloaded INTEGER DEFAULT 0,
  file_size_bytes INTEGER,
  download_date TIMESTAMP,
  zip_checksum TEXT,
  FOREIGN KEY (surah_id) REFERENCES Surah(id) ON DELETE CASCADE,
  FOREIGN KEY (reciter_id) REFERENCES Reciter(id) ON DELETE SET NULL,
  FOREIGN KEY (translation_id) REFERENCES Translation(id) ON DELETE SET NULL,
  UNIQUE(surah_id, reciter_id, translation_id)
);

CREATE INDEX idx_downloads_status ON Downloads(surah_id, downloaded);

-- ============================================================================
-- USER PROGRESS TABLE
-- ============================================================================
CREATE TABLE UserProgress (
  id INTEGER PRIMARY KEY,
  last_surah INTEGER,
  last_ayah INTEGER,
  active_translation_id INTEGER,
  repeat_mode TEXT CHECK(repeat_mode IN ('SINGLE', 'RANGE', 'INFINITE', 'COUNT')),
  repeat_count INTEGER DEFAULT 1,
  repeat_current INTEGER DEFAULT 0,
  repeat_start_ayah INTEGER,
  repeat_end_ayah INTEGER,
  playback_speed REAL DEFAULT 1.0,
  pause_interval_seconds INTEGER DEFAULT 2,
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (last_surah) REFERENCES Surah(id),
  FOREIGN KEY (active_translation_id) REFERENCES Translation(id)
);

-- ============================================================================
-- ERROR LOG TABLE
-- ============================================================================
CREATE TABLE ErrorLog (
  id INTEGER PRIMARY KEY,
  error_type TEXT NOT NULL,
  context TEXT,
  timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_error_type ON ErrorLog(error_type);

-- ============================================================================
-- DATA INTEGRITY TRIGGERS (CRITICAL: Quran text protection)
-- ============================================================================

-- Prevent Quran text modification
CREATE TRIGGER prevent_quran_modification
BEFORE UPDATE OF text_arabic ON Ayah
BEGIN
  SELECT RAISE(ABORT, 'Quran text cannot be modified');
END;

-- Prevent translation text modification
CREATE TRIGGER prevent_translation_modification
BEFORE UPDATE OF text_content ON AyahTranslation
BEGIN
  SELECT RAISE(ABORT, 'Translation text cannot be modified');
END;

-- Validate Ayah number on insert
CREATE TRIGGER validate_ayah_number
BEFORE INSERT ON Ayah
BEGIN
  SELECT CASE
    WHEN NEW.ayah_number > (SELECT total_ayah FROM Surah WHERE id = NEW.surah_id)
    THEN RAISE(ABORT, 'Ayah number exceeds Surah total')
  END;
END;

-- Validate repeat range
CREATE TRIGGER validate_repeat_range
BEFORE UPDATE ON UserProgress
BEGIN
  SELECT CASE
    WHEN NEW.repeat_end_ayah IS NOT NULL 
      AND NEW.repeat_start_ayah IS NOT NULL
      AND NEW.repeat_end_ayah < NEW.repeat_start_ayah
    THEN RAISE(ABORT, 'Invalid repeat range: end < start')
  END;
END;

-- Validate Juz boundaries
CREATE TRIGGER validate_juz_boundaries
BEFORE INSERT ON JuzMap
BEGIN
  SELECT CASE
    WHEN NEW.end_ayah < NEW.start_ayah
    THEN RAISE(ABORT, 'Invalid Juz range: end < start')
    WHEN NEW.end_ayah > (SELECT total_ayah FROM Surah WHERE id = NEW.surah_id)
    THEN RAISE(ABORT, 'Juz end_ayah exceeds Surah total')
  END;
END;

-- Initialize default user progress
INSERT INTO UserProgress (id) VALUES (1);
''';

/// Individual table creation statements (for testing)
const Map<String, String> tableSchemas = {
  'Surah': '''
    CREATE TABLE Surah (
      id INTEGER PRIMARY KEY,
      name_arabic TEXT NOT NULL,
      name_english TEXT NOT NULL,
      transliteration TEXT NOT NULL,
      total_ayah INTEGER NOT NULL,
      revelation_type TEXT CHECK(revelation_type IN ('Meccan', 'Medinan')),
      text_checksum TEXT NOT NULL
    )
  ''',
  'Ayah': '''
    CREATE TABLE Ayah (
      id INTEGER PRIMARY KEY,
      surah_id INTEGER NOT NULL,
      ayah_number INTEGER NOT NULL,
      text_arabic TEXT NOT NULL,
      text_checksum TEXT NOT NULL,
      FOREIGN KEY (surah_id) REFERENCES Surah(id) ON DELETE CASCADE,
      UNIQUE(surah_id, ayah_number)
    )
  ''',
  'Reciter': '''
    CREATE TABLE Reciter (
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      style TEXT,
      bitrate INTEGER DEFAULT 64,
      language_code TEXT DEFAULT 'ar'
    )
  ''',
  'RecitationAudio': '''
    CREATE TABLE RecitationAudio (
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
  ''',
  'UserProgress': '''
    CREATE TABLE UserProgress (
      id INTEGER PRIMARY KEY,
      last_surah INTEGER,
      last_ayah INTEGER,
      active_translation_id INTEGER,
      repeat_mode TEXT CHECK(repeat_mode IN ('SINGLE', 'RANGE', 'INFINITE', 'COUNT')),
      repeat_count INTEGER DEFAULT 1,
      repeat_current INTEGER DEFAULT 0,
      repeat_start_ayah INTEGER,
      repeat_end_ayah INTEGER,
      playback_speed REAL DEFAULT 1.0,
      pause_interval_seconds INTEGER DEFAULT 2,
      last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (last_surah) REFERENCES Surah(id),
      FOREIGN KEY (active_translation_id) REFERENCES Translation(id)
    )
  ''',
  'ErrorLog': '''
    CREATE TABLE ErrorLog (
      id INTEGER PRIMARY KEY,
      error_type TEXT NOT NULL,
      context TEXT,
      timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  ''',
};

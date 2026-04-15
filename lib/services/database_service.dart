import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/conversation.dart';
import '../models/flashcard.dart';
import '../models/message.dart';
import '../models/user_profile.dart';
import '../models/vocabulary.dart';
import '../models/lesson.dart';

class DatabaseService {
  static Database? _db;
  static bool _ffiInitialized = false;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  static Future<Database> _initDatabase() async {
    // Only initialize FFI once per process
    if (!_ffiInitialized) {
      sqfliteFfiInit();
      _ffiInitialized = true;
    }
    final databaseFactory = databaseFactoryFfi;
    final appDir = await getApplicationSupportDirectory();
    final dbPath = p.join(appDir.path, 'zaban.db');

    final db = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: _createTables,
        onUpgrade: _upgradeTables,
        onOpen: (db) async {
          // Enable WAL mode for better concurrent read/write performance
          await db.execute('PRAGMA journal_mode=WAL');
          // Enable foreign keys
          await db.execute('PRAGMA foreign_keys=ON');
        },
      ),
    );
    return db;
  }

  static Future<void> _createTables(Database db, int version) async {
    final batch = db.batch();

    batch.execute('''
      CREATE TABLE user_profile (
        id INTEGER PRIMARY KEY DEFAULT 1,
        name TEXT,
        name_fa TEXT,
        cefr_level TEXT DEFAULT 'A2',
        native_language TEXT DEFAULT 'fa',
        learning_goal TEXT DEFAULT 'general',
        daily_goal_minutes INTEGER DEFAULT 15,
        prefer_finglish INTEGER DEFAULT 0,
        show_translations INTEGER DEFAULT 1,
        auto_play_audio INTEGER DEFAULT 1,
        hardware_tier TEXT,
        selected_model TEXT,
        ollama_host TEXT DEFAULT 'http://localhost:11434',
        backend_type TEXT DEFAULT 'ollama',
        gguf_model_path TEXT,
        gemma_model_path TEXT,
        gpu_layers INTEGER DEFAULT 999,
        context_size INTEGER DEFAULT 8192,
        hugging_face_token TEXT,
        total_conversations INTEGER DEFAULT 0,
        total_minutes INTEGER DEFAULT 0,
        current_streak INTEGER DEFAULT 0,
        longest_streak INTEGER DEFAULT 0,
        last_active_date TEXT,
        vocabulary_count INTEGER DEFAULT 0
      )
    ''');

    batch.execute('''
      CREATE TABLE conversations (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        scenario_id TEXT,
        cefr_level TEXT DEFAULT 'A2',
        created_at TEXT NOT NULL,
        summary TEXT
      )
    ''');

    batch.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        type TEXT DEFAULT 'text',
        translation TEXT,
        audio_path TEXT,
        pronunciation_score REAL,
        corrections_json TEXT,
        timestamp TEXT NOT NULL,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
      )
    ''');

    batch.execute('''
      CREATE TABLE vocabulary (
        id TEXT PRIMARY KEY,
        word TEXT NOT NULL,
        translation TEXT NOT NULL,
        phonetic TEXT,
        part_of_speech TEXT,
        example_sentence TEXT,
        example_translation TEXT,
        cefr_level TEXT DEFAULT 'A1',
        context_conversation_id TEXT,
        first_encountered TEXT NOT NULL,
        times_encountered INTEGER DEFAULT 1,
        times_reviewed INTEGER DEFAULT 0,
        times_correct INTEGER DEFAULT 0,
        is_productive INTEGER DEFAULT 0
      )
    ''');

    batch.execute('''
      CREATE TABLE flashcards (
        id TEXT PRIMARY KEY,
        vocabulary_id TEXT NOT NULL,
        front TEXT NOT NULL,
        back TEXT NOT NULL,
        context_sentence TEXT,
        context_translation TEXT,
        ease_factor REAL DEFAULT 2.5,
        interval INTEGER DEFAULT 1,
        repetitions INTEGER DEFAULT 0,
        next_review TEXT NOT NULL,
        last_review TEXT,
        FOREIGN KEY (vocabulary_id) REFERENCES vocabulary(id) ON DELETE CASCADE
      )
    ''');

    batch.execute('''
      CREATE TABLE lesson_progress (
        scenario_id TEXT PRIMARY KEY,
        completed_count INTEGER DEFAULT 0,
        best_score REAL,
        last_attempt TEXT
      )
    ''');

    // Indexes
    batch.execute('''
      CREATE INDEX idx_messages_conversation ON messages(conversation_id)
    ''');
    batch.execute('''
      CREATE INDEX idx_messages_timestamp ON messages(conversation_id, timestamp)
    ''');
    batch.execute('''
      CREATE INDEX idx_flashcards_next_review ON flashcards(next_review)
    ''');
    batch.execute('''
      CREATE INDEX idx_vocabulary_word ON vocabulary(word COLLATE NOCASE)
    ''');
    batch.execute('''
      CREATE INDEX idx_conversations_created ON conversations(created_at DESC)
    ''');

    await batch.commit(noResult: true);
  }

  static Future<void> _upgradeTables(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute("ALTER TABLE user_profile ADD COLUMN backend_type TEXT DEFAULT 'ollama'");
      await db.execute('ALTER TABLE user_profile ADD COLUMN gguf_model_path TEXT');
      await db.execute('ALTER TABLE user_profile ADD COLUMN gemma_model_path TEXT');
      await db.execute('ALTER TABLE user_profile ADD COLUMN gpu_layers INTEGER DEFAULT 999');
      await db.execute('ALTER TABLE user_profile ADD COLUMN context_size INTEGER DEFAULT 8192');
      await db.execute('ALTER TABLE user_profile ADD COLUMN hugging_face_token TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE messages ADD COLUMN corrections_json TEXT');
    }
  }

  // --- User Profile ---

  Future<UserProfile> getUserProfile() async {
    final db = await database;
    final results = await db.query('user_profile', where: 'id = 1');
    if (results.isEmpty) {
      final profile = UserProfile();
      await db.insert('user_profile', {'id': 1, ...profile.toMap()});
      return profile;
    }
    return UserProfile.fromMap(results.first);
  }

  Future<void> saveUserProfile(UserProfile profile) async {
    final db = await database;
    await db.update('user_profile', profile.toMap(), where: 'id = 1');
  }

  // --- Conversations ---

  Future<void> saveConversation(Conversation conversation) async {
    final db = await database;
    await db.insert(
      'conversations',
      conversation.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Conversation>> getConversations({int limit = 50}) async {
    final db = await database;
    final results = await db.query(
      'conversations',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return results.map((m) => Conversation.fromMap(m)).toList();
  }

  Future<Conversation?> getConversation(String id) async {
    final db = await database;
    final results = await db.query('conversations', where: 'id = ?', whereArgs: [id]);
    if (results.isEmpty) return null;
    final conv = Conversation.fromMap(results.first);
    final messages = await getMessages(id);
    conv.messages.addAll(messages);
    return conv;
  }

  Future<void> deleteConversation(String id) async {
    final db = await database;
    // Existing DBs may have been created before ON DELETE CASCADE was added
    // to the schema (SQLite doesn't support adding FK constraints via ALTER).
    // Delete child rows explicitly to work on both old and new schemas.
    await db.transaction((txn) async {
      await txn.delete('messages', where: 'conversation_id = ?', whereArgs: [id]);
      await txn.delete('conversations', where: 'id = ?', whereArgs: [id]);
    });
  }

  // --- Messages ---

  Future<void> saveMessage(String conversationId, Message message) async {
    final db = await database;
    await db.insert('messages', {
      'conversation_id': conversationId,
      ...message.toMap(),
    });
  }

  Future<List<Message>> getMessages(String conversationId) async {
    final db = await database;
    final results = await db.query(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'timestamp ASC',
    );
    return results.map((m) => Message.fromMap(m)).toList();
  }

  // --- Vocabulary ---

  Future<void> saveVocabulary(VocabularyItem item) async {
    final db = await database;
    await db.insert(
      'vocabulary',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<VocabularyItem>> getVocabulary({String? cefrLevel}) async {
    final db = await database;
    final results = await db.query(
      'vocabulary',
      where: cefrLevel != null ? 'cefr_level = ?' : null,
      whereArgs: cefrLevel != null ? [cefrLevel] : null,
      orderBy: 'first_encountered DESC',
    );
    return results.map((m) => VocabularyItem.fromMap(m)).toList();
  }

  Future<VocabularyItem?> findVocabulary(String word) async {
    final db = await database;
    final results = await db.query(
      'vocabulary',
      where: 'word = ? COLLATE NOCASE',
      whereArgs: [word],
    );
    if (results.isEmpty) return null;
    return VocabularyItem.fromMap(results.first);
  }

  // --- Flashcards ---

  Future<void> saveFlashcard(Flashcard card) async {
    final db = await database;
    await db.insert(
      'flashcards',
      card.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Flashcard>> getDueFlashcards({int limit = 20}) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final results = await db.query(
      'flashcards',
      where: 'next_review <= ?',
      whereArgs: [now],
      orderBy: 'next_review ASC',
      limit: limit,
    );
    return results.map((m) => Flashcard.fromMap(m)).toList();
  }

  Future<int> getDueFlashcardCount() async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM flashcards WHERE next_review <= ?',
      [now],
    );
    return result.first['count'] as int;
  }

  Future<List<Flashcard>> getAllFlashcards() async {
    final db = await database;
    final results = await db.query('flashcards', orderBy: 'next_review ASC');
    return results.map((m) => Flashcard.fromMap(m)).toList();
  }

  Future<Flashcard?> getFlashcardForVocabulary(String vocabularyId) async {
    final db = await database;
    final results = await db.query(
      'flashcards',
      where: 'vocabulary_id = ?',
      whereArgs: [vocabularyId],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return Flashcard.fromMap(results.first);
  }

  /// Delete a vocabulary item and any linked flashcards.
  /// Uses an explicit transaction since older DBs may not have ON DELETE CASCADE
  /// (SQLite can't retrofit FK constraints via ALTER TABLE).
  Future<void> deleteVocabulary(String vocabularyId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'flashcards',
        where: 'vocabulary_id = ?',
        whereArgs: [vocabularyId],
      );
      await txn.delete(
        'vocabulary',
        where: 'id = ?',
        whereArgs: [vocabularyId],
      );
    });
  }

  // --- Lesson Progress ---

  Future<void> saveLessonProgress(LessonProgress progress) async {
    final db = await database;
    await db.insert(
      'lesson_progress',
      progress.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<LessonProgress?> getLessonProgress(String scenarioId) async {
    final db = await database;
    final results = await db.query(
      'lesson_progress',
      where: 'scenario_id = ?',
      whereArgs: [scenarioId],
    );
    if (results.isEmpty) return null;
    return LessonProgress.fromMap(results.first);
  }

  Future<Map<String, LessonProgress>> getAllLessonProgress() async {
    final db = await database;
    final results = await db.query('lesson_progress');
    return {
      for (final r in results)
        r['scenario_id'] as String: LessonProgress.fromMap(r),
    };
  }

  // --- Stats ---

  Future<Map<String, dynamic>> getStats() async {
    final db = await database;
    final convCount = (await db.rawQuery(
      'SELECT COUNT(*) as c FROM conversations',
    )).first['c'] as int;
    final vocabCount = (await db.rawQuery(
      'SELECT COUNT(*) as c FROM vocabulary',
    )).first['c'] as int;
    final cardsDue = await getDueFlashcardCount();
    final totalCards = (await db.rawQuery(
      'SELECT COUNT(*) as c FROM flashcards',
    )).first['c'] as int;

    return {
      'conversations': convCount,
      'vocabulary': vocabCount,
      'cards_due': cardsDue,
      'total_cards': totalCards,
    };
  }

  /// Close the database connection.
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}

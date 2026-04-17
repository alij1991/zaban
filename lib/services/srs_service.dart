import '../models/cefr_level.dart';
import '../models/flashcard.dart';
import '../models/vocabulary.dart';
import 'database_service.dart';

/// Spaced Repetition System service — now powered by FSRS-6.
///
/// FSRS benefits over the old SM-2:
///   • 20–30 % fewer reviews at the same retention level
///   • No "ease hell" — difficulty uses mean reversion, not permanent penalties
///   • Personalisable target retention (default 85 %)
///
/// Session pacing:
///   srsDailyNewLimit controls how many *new* cards enter a session.
///   Due (review) cards are always included regardless of the limit.
class SRSService {
  SRSService({required this.db});

  final DatabaseService db;

  // ── Flashcard creation ────────────────────────────────────────────────────

  /// Create a flashcard from a vocabulary item.
  Future<Flashcard> createFlashcard(VocabularyItem vocab) async {
    final card = Flashcard(
      vocabularyId: vocab.id,
      front: vocab.word,
      back: vocab.phonetic != null
          ? '${vocab.translation}\n${vocab.phonetic}'
          : vocab.translation,
      contextSentence: vocab.exampleSentence,
      contextTranslation: vocab.exampleTranslation,
    );
    await db.saveFlashcard(card);
    return card;
  }

  // ── Review scheduling ─────────────────────────────────────────────────────

  /// Get cards due for review + new cards up to [newCardLimit].
  ///
  /// [maxTotal] caps memory use for users with huge backlogs. With a 20-minute
  /// session timer and ~15s per card, practical session size is ≤80 cards, so
  /// 500 is effectively "no cap" while still preventing accidental 10k-row
  /// reads on heavily-behind decks. Use [SRSStats.dueToday] for the true count.
  Future<List<Flashcard>> getDueCards({
    int newCardLimit = 5,
    int maxTotal = 500,
  }) async {
    // Due (review) cards — always fetch these first
    final dueCards = await db.getDueFlashcards(limit: maxTotal);

    // Count new cards already in the due list
    final newInDue = dueCards.where((c) => c.repetitions == 0).length;
    final extraNewNeeded = (newCardLimit - newInDue).clamp(0, newCardLimit);

    if (extraNewNeeded > 0) {
      // Fetch additional unseen new cards (next_review in the future but never reviewed)
      final allNew = await db.getNewFlashcards(limit: extraNewNeeded);
      // Avoid duplicates from the due list
      final dueIds = dueCards.map((c) => c.id).toSet();
      final extra = allNew.where((c) => !dueIds.contains(c.id)).toList();
      return [...dueCards, ...extra];
    }

    return dueCards;
  }

  /// Apply FSRS review to a card and persist.
  Future<void> reviewCard(
    Flashcard card,
    int grade, {
    double targetRetention = 0.85,
  }) async {
    card.review(grade, targetRetention: targetRetention);
    await db.saveFlashcard(card);

    // Update vocabulary review stats
    final vocab = await db.findVocabulary(card.front);
    if (vocab != null) {
      vocab.timesReviewed++;
      if (grade >= 2) vocab.timesCorrect++; // Hard/Good/Easy = correct
      await db.saveVocabulary(vocab);
    }
  }

  // ── Stats ─────────────────────────────────────────────────────────────────

  /// Get review statistics efficiently (no bulk card fetching).
  Future<SRSStats> getStats() async {
    final db_ = await DatabaseService.database;

    // Single query for card counts by state, using FSRS stability/interval
    final rows = await db_.rawQuery('''
      SELECT
        COUNT(*) AS total,
        SUM(CASE WHEN repetitions = 0 THEN 1 ELSE 0 END) AS new_cards,
        SUM(CASE WHEN repetitions > 0 AND interval <= 7  THEN 1 ELSE 0 END) AS learning,
        SUM(CASE WHEN repetitions > 0 AND interval > 7 AND interval < 21 THEN 1 ELSE 0 END) AS young,
        SUM(CASE WHEN repetitions > 0 AND interval >= 21 THEN 1 ELSE 0 END) AS mature
      FROM flashcards
    ''');

    final row = rows.first;
    final dueToday = await db.getDueFlashcardCount();

    return SRSStats(
      totalCards: row['total'] as int? ?? 0,
      dueToday: dueToday,
      newCards: row['new_cards'] as int? ?? 0,
      learning: (row['learning'] as int? ?? 0) + (row['young'] as int? ?? 0),
      mature: row['mature'] as int? ?? 0,
    );
  }

  // ── Vocabulary CRUD ───────────────────────────────────────────────────────

  /// Auto-generate a flashcard from a conversation encounter.
  Future<Flashcard?> createFromConversation({
    required String word,
    required String translation,
    required String sentenceContext,
    required String sentenceTranslation,
    String? phonetic,
    String? partOfSpeech,
  }) async {
    var vocab = await db.findVocabulary(word);
    if (vocab != null) {
      vocab.timesEncountered++;
      await db.saveVocabulary(vocab);
      return null; // Don't create duplicate cards
    }

    vocab = VocabularyItem(
      word: word,
      translation: translation,
      phonetic: phonetic,
      partOfSpeech: partOfSpeech,
      exampleSentence: sentenceContext,
      exampleTranslation: sentenceTranslation,
    );
    await db.saveVocabulary(vocab);
    return createFlashcard(vocab);
  }

  /// Add (or update) a word the user wants to study manually.
  Future<VocabularyItem> addOrUpdateWord({
    required String word,
    required String translation,
    String? phonetic,
    String? partOfSpeech,
    String? exampleSentence,
    String? exampleTranslation,
    CEFRLevel cefrLevel = CEFRLevel.a1,
  }) async {
    final existing = await db.findVocabulary(word);
    if (existing != null) {
      final updated = existing.copyWith(
        word: word,
        translation: translation,
        phonetic: phonetic,
        partOfSpeech: partOfSpeech,
        exampleSentence: exampleSentence,
        exampleTranslation: exampleTranslation,
        cefrLevel: cefrLevel,
      );
      await db.saveVocabulary(updated);
      final card = await db.getFlashcardForVocabulary(updated.id);
      if (card == null) await createFlashcard(updated);
      return updated;
    }

    final vocab = VocabularyItem(
      word: word,
      translation: translation,
      phonetic: phonetic,
      partOfSpeech: partOfSpeech,
      exampleSentence: exampleSentence,
      exampleTranslation: exampleTranslation,
      cefrLevel: cefrLevel,
    );
    await db.saveVocabulary(vocab);
    await createFlashcard(vocab);
    return vocab;
  }

  Future<void> deleteVocabulary(String vocabularyId) async {
    await db.deleteVocabulary(vocabularyId);
  }

  /// Reset a card's FSRS progress so it re-enters the learning queue.
  Future<void> resetCard(String vocabularyId) async {
    final card = await db.getFlashcardForVocabulary(vocabularyId);
    if (card == null) return;
    final reset = Flashcard(
      id: card.id,
      vocabularyId: card.vocabularyId,
      front: card.front,
      back: card.back,
      contextSentence: card.contextSentence,
      contextTranslation: card.contextTranslation,
      // Reset all FSRS state
    );
    await db.saveFlashcard(reset);
  }

  // ── 7-day forecast ────────────────────────────────────────────────────────

  /// Returns a map of date → predicted due card count for the next [days] days.
  /// Uses the stored nextReview dates (no FSRS simulation needed).
  Future<Map<DateTime, int>> getReviewForecast({int days = 7}) async {
    final db_ = await DatabaseService.database;
    final now = DateTime.now();
    final end = now.add(Duration(days: days));

    final rows = await db_.rawQuery('''
      SELECT DATE(next_review) as review_date, COUNT(*) as cnt
      FROM flashcards
      WHERE next_review > ? AND next_review <= ?
      GROUP BY DATE(next_review)
      ORDER BY review_date ASC
    ''', [now.toIso8601String(), end.toIso8601String()]);

    final result = <DateTime, int>{};
    for (final row in rows) {
      final dateStr = row['review_date'] as String;
      final date = DateTime.parse(dateStr);
      result[date] = row['cnt'] as int;
    }
    return result;
  }

  // ── Activity history (for heatmap) ────────────────────────────────────────

  /// Returns review counts per day based on last_review timestamps.
  Future<Map<DateTime, int>> getActivityHistory({int days = 365}) async {
    final db_ = await DatabaseService.database;
    final cutoff = DateTime.now().subtract(Duration(days: days));

    final rows = await db_.rawQuery('''
      SELECT DATE(last_review) as review_date, COUNT(*) as cnt
      FROM flashcards
      WHERE last_review IS NOT NULL AND last_review >= ?
      GROUP BY DATE(last_review)
      ORDER BY review_date ASC
    ''', [cutoff.toIso8601String()]);

    final result = <DateTime, int>{};
    for (final row in rows) {
      final dateStr = row['review_date'] as String;
      final date = DateTime.parse(dateStr);
      result[date] = row['cnt'] as int;
    }
    return result;
  }
}

class SRSStats {
  const SRSStats({
    required this.totalCards,
    required this.dueToday,
    required this.newCards,
    required this.learning,
    required this.mature,
  });

  final int totalCards;
  final int dueToday;
  final int newCards;
  final int learning; // learning + young combined
  final int mature;

  /// Fraction of cards that have graduated to "mature" (interval ≥ 21 days).
  ///
  /// NOTE: this is a *deck maturity* ratio, not a true retention rate —
  /// a true retention rate would be `correct_reviews / total_reviews`, which
  /// requires a per-review log. Displayed as "Mature cards: N / M" in the UI
  /// to avoid confusing users with a misleading "retention %".
  double get maturityRate =>
      totalCards > 0 ? mature / totalCards : 0.0;
}

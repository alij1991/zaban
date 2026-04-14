import '../models/flashcard.dart';
import '../models/vocabulary.dart';
import 'database_service.dart';

/// Spaced Repetition System service using SM-2 algorithm.
///
/// Research shows SRS users retain 85% of vocabulary after one year
/// versus 22% with traditional methods. Rich context cards (vocabulary
/// in dialogues) produce 67% more retention than translation pairs.
class SRSService {
  SRSService({required this.db});

  final DatabaseService db;

  /// Create a flashcard from a vocabulary item encountered in conversation.
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

  /// Get cards due for review today.
  Future<List<Flashcard>> getDueCards({int limit = 20}) async {
    return db.getDueFlashcards(limit: limit);
  }

  /// Review a card with quality rating.
  /// 0: complete blackout
  /// 1: incorrect, remembered on seeing answer
  /// 2: incorrect, answer seemed easy to recall
  /// 3: correct with serious difficulty
  /// 4: correct with some hesitation
  /// 5: perfect recall
  Future<void> reviewCard(Flashcard card, int quality) async {
    card.review(quality);
    await db.saveFlashcard(card);

    // Update vocabulary review stats
    final vocab = await db.findVocabulary(card.front);
    if (vocab != null) {
      vocab.timesReviewed++;
      if (quality >= 3) vocab.timesCorrect++;
      await db.saveVocabulary(vocab);
    }
  }

  /// Get review statistics.
  Future<SRSStats> getStats() async {
    final allCards = await db.getAllFlashcards();
    final dueCards = await db.getDueFlashcards(limit: 1000);

    int newCards = 0;
    int learning = 0;
    int mature = 0;

    for (final card in allCards) {
      if (card.repetitions == 0) {
        newCards++;
      } else if (card.interval < 21) {
        learning++;
      } else {
        mature++;
      }
    }

    return SRSStats(
      totalCards: allCards.length,
      dueToday: dueCards.length,
      newCards: newCards,
      learning: learning,
      mature: mature,
    );
  }

  /// Auto-generate flashcard from conversation encounter.
  /// Called when the tutor introduces a new word.
  Future<Flashcard?> createFromConversation({
    required String word,
    required String translation,
    required String sentenceContext,
    required String sentenceTranslation,
    String? phonetic,
    String? partOfSpeech,
  }) async {
    // Check if vocabulary item already exists
    var vocab = await db.findVocabulary(word);
    if (vocab != null) {
      vocab.timesEncountered++;
      await db.saveVocabulary(vocab);
      return null; // Don't create duplicate cards
    }

    // Create new vocabulary item
    vocab = VocabularyItem(
      word: word,
      translation: translation,
      phonetic: phonetic,
      partOfSpeech: partOfSpeech,
      exampleSentence: sentenceContext,
      exampleTranslation: sentenceTranslation,
    );
    await db.saveVocabulary(vocab);

    // Create rich context flashcard
    return createFlashcard(vocab);
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
  final int learning;
  final int mature;

  double get retentionRate =>
      totalCards > 0 ? mature / totalCards : 0.0;
}

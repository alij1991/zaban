import 'package:flutter/foundation.dart';
import '../models/cefr_level.dart';
import '../models/flashcard.dart';
import '../models/vocabulary.dart';
import '../services/srs_service.dart';

class SRSProvider extends ChangeNotifier {
  SRSProvider({required this.srsService});

  final SRSService srsService;

  /// Reverse mode: show Persian translation as the prompt and ask the learner
  /// to recall the English word (productive recall). Stronger for retention
  /// than receptive-only review.
  bool _reverseMode = false;
  bool get reverseMode => _reverseMode;
  void toggleReverseMode() {
    _reverseMode = !_reverseMode;
    notifyListeners();
  }

  List<Flashcard> _dueCards = [];
  List<Flashcard> get dueCards => _dueCards;

  int _currentIndex = 0;
  int get currentIndex => _currentIndex;

  Flashcard? get currentCard =>
      _dueCards.isNotEmpty && _currentIndex < _dueCards.length
          ? _dueCards[_currentIndex]
          : null;

  bool _showAnswer = false;
  bool get showAnswer => _showAnswer;

  SRSStats? _stats;
  SRSStats? get stats => _stats;

  int _reviewedCount = 0;
  int get reviewedCount => _reviewedCount;

  int _correctCount = 0;
  int get correctCount => _correctCount;

  bool get isSessionComplete =>
      _dueCards.isEmpty || _currentIndex >= _dueCards.length;

  Future<void> loadDueCards() async {
    _dueCards = await srsService.getDueCards();
    _currentIndex = 0;
    _reviewedCount = 0;
    _correctCount = 0;
    _showAnswer = false;
    _stats = await srsService.getStats();
    notifyListeners();
  }

  void revealAnswer() {
    _showAnswer = true;
    notifyListeners();
  }

  Future<void> rateCard(int quality) async {
    if (currentCard == null) return;

    await srsService.reviewCard(currentCard!, quality);
    _reviewedCount++;
    if (quality >= 3) _correctCount++;

    _currentIndex++;
    _showAnswer = false;
    _stats = await srsService.getStats();
    notifyListeners();
  }

  Future<void> refreshStats() async {
    _stats = await srsService.getStats();
    notifyListeners();
  }

  /// Add (or update) a word the user wants to learn. Refreshes due-card list
  /// so the new card shows up immediately.
  Future<VocabularyItem> addWord({
    required String word,
    required String translation,
    String? phonetic,
    String? partOfSpeech,
    String? exampleSentence,
    String? exampleTranslation,
    CEFRLevel cefrLevel = CEFRLevel.a1,
  }) async {
    final vocab = await srsService.addOrUpdateWord(
      word: word,
      translation: translation,
      phonetic: phonetic,
      partOfSpeech: partOfSpeech,
      exampleSentence: exampleSentence,
      exampleTranslation: exampleTranslation,
      cefrLevel: cefrLevel,
    );
    await loadDueCards();
    return vocab;
  }

  Future<void> deleteWord(String vocabularyId) async {
    await srsService.deleteVocabulary(vocabularyId);
    await loadDueCards();
  }

  Future<void> resetCard(String vocabularyId) async {
    await srsService.resetCard(vocabularyId);
    await loadDueCards();
  }
}

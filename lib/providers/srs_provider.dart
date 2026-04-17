import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/cefr_level.dart';
import '../models/flashcard.dart';
import '../models/vocabulary.dart';
import '../services/srs_service.dart';

/// Manages the active flashcard review session.
///
/// Key features:
///   • FSRS-6 scheduling (via SRSService + Flashcard.review)
///   • Session time cap: warns at 15 min, hard-stops new cards at 20 min
///   • Daily new-card limit from UserProfile.srsDailyNewLimit (default 5)
///   • Target retention from UserProfile.srsTargetRetention (default 85 %)
///   • Productive (FA→EN) / receptive (EN→FA) toggle
class SRSProvider extends ChangeNotifier {
  SRSProvider({required this.srsService});

  final SRSService srsService;

  // ── Review direction (receptive vs productive) ────────────────────────────

  bool _reverseMode = false;
  bool get reverseMode => _reverseMode;

  void toggleReverseMode() {
    _reverseMode = !_reverseMode;
    notifyListeners();
  }

  // ── Session state ─────────────────────────────────────────────────────────

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

  // ── Session settings (synced from UserProfile when loadDueCards is called) ─

  double _targetRetention = 0.85;
  double get targetRetention => _targetRetention;

  int _dailyNewLimit = 5;
  int get dailyNewLimit => _dailyNewLimit;

  // ── Session timer ─────────────────────────────────────────────────────────

  Timer? _sessionTimer;
  Duration _sessionElapsed = Duration.zero;
  Duration get sessionElapsed => _sessionElapsed;

  /// True when session has been running ≥ 15 minutes (show a rest nudge).
  bool get sessionLong => _sessionElapsed.inMinutes >= 15;

  /// True when session has been running ≥ 20 minutes (hard cap reached).
  bool get sessionCapReached => _sessionElapsed.inMinutes >= 20;

  void _startTimer() {
    _sessionTimer?.cancel();
    _sessionElapsed = Duration.zero;
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _sessionElapsed += const Duration(seconds: 1);
      notifyListeners();
    });
  }

  void _stopTimer() {
    _sessionTimer?.cancel();
    _sessionTimer = null;
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Load due cards for a new session.
  /// [targetRetention] and [dailyNewLimit] are read from UserProfile by callers
  /// and passed in so the provider doesn't need to know about SettingsProvider.
  Future<void> loadDueCards({
    double targetRetention = 0.85,
    int dailyNewLimit = 5,
  }) async {
    _targetRetention = targetRetention;
    _dailyNewLimit = dailyNewLimit;

    _dueCards = await srsService.getDueCards(newCardLimit: dailyNewLimit);
    _currentIndex = 0;
    _reviewedCount = 0;
    _correctCount = 0;
    _showAnswer = false;
    _stats = await srsService.getStats();

    _startTimer();
    notifyListeners();
  }

  void revealAnswer() {
    _showAnswer = true;
    notifyListeners();
  }

  Future<void> rateCard(int grade) async {
    if (currentCard == null) return;

    await srsService.reviewCard(
      currentCard!,
      grade,
      targetRetention: _targetRetention,
    );
    _reviewedCount++;
    if (grade >= 2) _correctCount++; // Hard/Good/Easy = correct

    _currentIndex++;
    _showAnswer = false;
    _stats = await srsService.getStats();
    notifyListeners();
  }

  Future<void> refreshStats() async {
    _stats = await srsService.getStats();
    notifyListeners();
  }

  // ── End-of-session ────────────────────────────────────────────────────────

  /// Called when the session complete screen is dismissed.
  Future<void> endSession() async {
    _stopTimer();
    await loadDueCards(
      targetRetention: _targetRetention,
      dailyNewLimit: _dailyNewLimit,
    );
  }

  // ── Vocabulary CRUD (word list tab) ───────────────────────────────────────

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
    await loadDueCards(
      targetRetention: _targetRetention,
      dailyNewLimit: _dailyNewLimit,
    );
    return vocab;
  }

  Future<void> deleteWord(String vocabularyId) async {
    await srsService.deleteVocabulary(vocabularyId);
    await loadDueCards(
      targetRetention: _targetRetention,
      dailyNewLimit: _dailyNewLimit,
    );
  }

  Future<void> resetCard(String vocabularyId) async {
    await srsService.resetCard(vocabularyId);
    await loadDueCards(
      targetRetention: _targetRetention,
      dailyNewLimit: _dailyNewLimit,
    );
  }
}

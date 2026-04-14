import 'package:flutter/foundation.dart';
import '../models/flashcard.dart';
import '../services/srs_service.dart';

class SRSProvider extends ChangeNotifier {
  SRSProvider({required this.srsService});

  final SRSService srsService;

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
}

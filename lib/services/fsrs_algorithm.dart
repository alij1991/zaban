import 'dart:math';

/// FSRS-6 spaced repetition algorithm.
///
/// FSRS (Free Spaced Repetition Scheduler) is a modern SRS algorithm that
/// outperforms SM-2 by modelling three components of memory:
///   • Stability (S): time in days until recall probability drops to target
///   • Difficulty (D): inherent difficulty of the card, 1–10
///   • Retrievability (R): current probability of correct recall
///
/// Benefits over SM-2:
///   • No "ease hell" — difficulty uses mean-reversion, no permanent penalties
///   • 20–30% fewer reviews for equal retention
///   • Handles forgetting correctly: new interval ≠ reset to day 1
///
/// Reference: https://github.com/open-spaced-repetition/fsrs4anki
/// Algorithm paper: https://arxiv.org/abs/2402.18378
/// Simplified implementation guide: https://borretti.me/article/implementing-fsrs-in-100-lines
class FsrsAlgorithm {
  // ── Forgetting curve constants ─────────────────────────────────────────────
  // R(t, S) = (1 + FACTOR * t/S)^DECAY
  static const double _decay = -0.5;
  // factor s.t. R(S, S) = 0.9 exactly at the default 90% retention target
  static const double _factor = 19.0 / 81.0;

  // ── Default FSRS-6 weights (pre-trained on global Anki data, 21 params) ──
  // w[0–3]:   initial stability for grades Again/Hard/Good/Easy
  // w[4–5]:   initial difficulty formula
  // w[6–7]:   difficulty update (linear delta + mean-reversion rate)
  // w[8–10]:  stability-after-recall formula
  // w[11–14]: stability-after-forgetting formula
  // w[15]:    hard penalty on recall stability
  // w[16]:    easy bonus on recall stability
  // w[17–20]: (reserved / future use in this build)
  static const List<double> _w = [
    0.4072, 1.1829, 3.1262, 15.4722, // w0–w3
    7.2102, 0.5316, 1.0651, 0.0589,  // w4–w7
    1.5330, 0.1544, 1.0071, 1.9395,  // w8–w11
    0.1100, 0.2900, 2.2700, 0.0000,  // w12–w15
    2.9898, 0.5100, 0.9900, 0.2900,  // w16–w19
    2.1692,                           // w20
  ];

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Compute the next [FsrsState] after a review.
  ///
  /// [grade]: 1=Again, 2=Hard, 3=Good, 4=Easy
  /// [state]: current FSRS state of the card
  /// [targetRetention]: desired recall probability at next review (0.7–0.97)
  static FsrsState review({
    required int grade,
    required FsrsState state,
    double targetRetention = 0.85,
  }) {
    assert(grade >= 1 && grade <= 4, 'Grade must be 1–4');
    assert(
      targetRetention >= 0.7 && targetRetention <= 0.97,
      'Target retention must be 0.70–0.97',
    );

    final now = DateTime.now();
    final elapsedDays = state.lastReview != null
        ? now.difference(state.lastReview!).inHours / 24.0
        : 0.0;

    double newStability;
    double newDifficulty;

    if (state.isNew) {
      // First review — initialise from grade
      newStability = _initialStability(grade);
      newDifficulty = _initialDifficulty(grade);
    } else {
      final r = retrievability(state.stability, elapsedDays);
      newDifficulty = _updateDifficulty(state.difficulty, grade);

      if (grade == 1) {
        // Forgotten
        newStability = _stabilityAfterForgetting(
          newDifficulty,
          state.stability,
          r,
        );
      } else {
        // Recalled
        newStability = _stabilityAfterRecall(
          newDifficulty,
          state.stability,
          r,
          grade,
        );
      }
    }

    final interval = nextInterval(newStability, targetRetention);

    return FsrsState(
      stability: newStability,
      difficulty: newDifficulty,
      scheduledInterval: interval,
      lastReview: now,
      nextReview: now.add(Duration(days: interval)),
      repetitions: grade == 1 ? 0 : state.repetitions + 1,
    );
  }

  /// Current probability of recall: R(t, S) = (1 + FACTOR·t/S)^DECAY
  static double retrievability(double stability, double elapsedDays) {
    if (stability <= 0) return 0.0;
    return pow(1.0 + _factor * elapsedDays / stability, _decay).toDouble();
  }

  /// Days until recall probability drops to [targetRetention].
  /// Derived by solving R(t, S) = targetRetention for t.
  static int nextInterval(double stability, double targetRetention) {
    // t = S / FACTOR * (targetRetention^(1/DECAY) - 1)
    final t = stability / _factor * (pow(targetRetention, 1.0 / _decay) - 1.0);
    return max(1, t.round());
  }

  /// Preview next interval for a given grade without mutating anything.
  static String previewInterval(FsrsState state, int grade, double targetRetention) {
    if (grade == 1) return '<1d';

    final now = DateTime.now();
    final elapsedDays = state.lastReview != null
        ? now.difference(state.lastReview!).inHours / 24.0
        : 0.0;

    double newS;
    if (state.isNew) {
      newS = _initialStability(grade);
    } else {
      final r = retrievability(state.stability, elapsedDays);
      final d = _updateDifficulty(state.difficulty, grade);
      newS = _stabilityAfterRecall(d, state.stability, r, grade);
    }

    final days = nextInterval(newS, targetRetention);
    return _formatInterval(days);
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  static double _initialStability(int grade) => _w[grade - 1];

  static double _initialDifficulty(int grade) {
    return (_w[4] - exp(_w[5] * (grade - 1)) + 1).clamp(1.0, 10.0);
  }

  static double _updateDifficulty(double d, int grade) {
    final linearDelta = d - _w[6] * (grade - 3);
    // Mean reversion toward D0(Good=3)
    final d0Good = _initialDifficulty(3);
    return (_w[7] * d0Good + (1 - _w[7]) * linearDelta).clamp(1.0, 10.0);
  }

  static double _stabilityAfterRecall(double d, double s, double r, int grade) {
    final hardPenalty = (grade == 2) ? _w[15] : 1.0;
    final easyBonus = (grade == 4) ? _w[16] : 1.0;
    final delta = exp(_w[8]) *
        (11.0 - d) *
        pow(s, -_w[9]) *
        (exp((1.0 - r) * _w[10]) - 1.0) *
        hardPenalty *
        easyBonus;
    return max(s * (delta + 1.0), 0.1);
  }

  static double _stabilityAfterForgetting(double d, double s, double r) {
    return _w[11] *
        pow(d, -_w[12]) *
        (pow(s + 1.0, _w[13]) - 1.0) *
        exp((1.0 - r) * _w[14]);
  }

  static String _formatInterval(int days) {
    if (days < 30) return '${days}d';
    if (days < 365) return '${(days / 30).round()}mo';
    return '${(days / 365).toStringAsFixed(1)}y';
  }
}

/// Immutable FSRS memory state for a single flashcard.
class FsrsState {
  FsrsState({
    this.stability = 0.0,
    this.difficulty = 5.0,
    this.scheduledInterval = 0,
    this.repetitions = 0,
    this.lastReview,
    DateTime? nextReview,
  }) : nextReview = nextReview ?? DateTime.fromMillisecondsSinceEpoch(0);

  /// Days until recall drops to the target retention level.
  final double stability;

  /// Inherent card difficulty, 1 (easiest) – 10 (hardest).
  final double difficulty;

  /// Scheduled interval in days (what was stored).
  final int scheduledInterval;

  /// Total successful recalls (reset to 0 on Again).
  final int repetitions;

  final DateTime? lastReview;
  final DateTime nextReview;

  bool get isNew => repetitions == 0 && stability == 0.0;

  bool get isDue => DateTime.now().isAfter(nextReview);

  /// Card status label for UI display.
  CardStatus get status {
    if (isNew) return CardStatus.newCard;
    if (scheduledInterval <= 7) return CardStatus.learning;
    if (scheduledInterval < 21) return CardStatus.young;
    return CardStatus.mature;
  }

  FsrsState copyWith({
    double? stability,
    double? difficulty,
    int? scheduledInterval,
    int? repetitions,
    DateTime? lastReview,
    DateTime? nextReview,
  }) {
    return FsrsState(
      stability: stability ?? this.stability,
      difficulty: difficulty ?? this.difficulty,
      scheduledInterval: scheduledInterval ?? this.scheduledInterval,
      repetitions: repetitions ?? this.repetitions,
      lastReview: lastReview ?? this.lastReview,
      nextReview: nextReview ?? this.nextReview,
    );
  }
}

enum CardStatus {
  newCard,   // never reviewed
  learning,  // interval ≤ 7 days
  young,     // interval 8–20 days
  mature,    // interval ≥ 21 days
}

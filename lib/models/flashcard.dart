import 'package:uuid/uuid.dart';
import '../services/fsrs_algorithm.dart';

/// A flashcard that uses the FSRS-6 spaced repetition algorithm.
///
/// Replaces the old SM-2 implementation. Key field mapping:
///   SM-2 easeFactor  → FSRS difficulty   (1–10, default 5.0)
///   SM-2 repetitions → repetitions       (kept; 0 = new card)
///   SM-2 interval    → scheduledInterval (days until next review)
///   new              → stability         (FSRS S — days until R = target)
///
/// The DB migration (v3 → v4) adds `stability` and `difficulty` columns.
/// Old rows default to stability=0 / difficulty=5, which causes FSRS to
/// treat them as new cards — a safe fallback.
class Flashcard {
  Flashcard({
    String? id,
    required this.vocabularyId,
    required this.front,
    required this.back,
    this.contextSentence,
    this.contextTranslation,
    this.stability = 0.0,
    this.difficulty = 5.0,
    this.scheduledInterval = 1,
    this.repetitions = 0,
    DateTime? nextReview,
    this.lastReview,
  }) : id = id ?? const Uuid().v4(),
       nextReview = nextReview ?? DateTime.now();

  final String id;
  final String vocabularyId;
  final String front; // English word / phrase
  final String back;  // Persian translation + context
  final String? contextSentence;
  final String? contextTranslation;

  // ── FSRS memory state ───────────────────────────────────────────────────
  double stability;          // days until recall drops to target retention
  double difficulty;         // 1 (easy) – 10 (hard)
  int scheduledInterval;     // days between reviews (≥ 1)
  int repetitions;           // successful recalls; 0 = new card

  DateTime nextReview;
  DateTime? lastReview;

  // ── Derived properties ─────────────────────────────────────────────────

  bool get isDue => DateTime.now().isAfter(nextReview);

  FsrsState get fsrsState => FsrsState(
    stability: stability,
    difficulty: difficulty,
    scheduledInterval: scheduledInterval,
    repetitions: repetitions,
    lastReview: lastReview,
    nextReview: nextReview,
  );

  CardStatus get status => fsrsState.status;

  // ── FSRS review ───────────────────────────────────────────────────────

  /// Apply the FSRS-6 algorithm for a given grade.
  ///
  /// [grade]: 1=Again  2=Hard  3=Good  4=Easy
  /// [targetRetention]: desired recall probability (default 85 %)
  void review(int grade, {double targetRetention = 0.85}) {
    assert(grade >= 1 && grade <= 4, 'FSRS grade must be 1–4');

    final newState = FsrsAlgorithm.review(
      grade: grade,
      state: fsrsState,
      targetRetention: targetRetention,
    );

    stability = newState.stability;
    difficulty = newState.difficulty;
    scheduledInterval = newState.scheduledInterval;
    repetitions = newState.repetitions;
    lastReview = newState.lastReview;
    nextReview = newState.nextReview;
  }

  /// Preview next interval string for a grade without mutating the card.
  /// Used to show "Good → 4d" labels on rating buttons.
  String previewInterval(int grade, {double targetRetention = 0.85}) {
    return FsrsAlgorithm.previewInterval(fsrsState, grade, targetRetention);
  }

  // ── Serialisation ──────────────────────────────────────────────────────

  Map<String, dynamic> toMap() => {
    'id': id,
    'vocabulary_id': vocabularyId,
    'front': front,
    'back': back,
    'context_sentence': contextSentence,
    'context_translation': contextTranslation,
    // FSRS fields
    'stability': stability,
    'difficulty': difficulty,
    'interval': scheduledInterval,
    'repetitions': repetitions,
    'next_review': nextReview.toIso8601String(),
    'last_review': lastReview?.toIso8601String(),
    // Legacy SM-2 field kept for DB compat (no longer used in calculations)
    'ease_factor': difficulty,
  };

  factory Flashcard.fromMap(Map<String, dynamic> map) => Flashcard(
    id: map['id'] as String,
    vocabularyId: map['vocabulary_id'] as String,
    front: map['front'] as String,
    back: map['back'] as String,
    contextSentence: map['context_sentence'] as String?,
    contextTranslation: map['context_translation'] as String?,
    // FSRS fields (columns added in migration v4; default-safe for old rows)
    stability: (map['stability'] as num?)?.toDouble() ?? 0.0,
    difficulty: (map['difficulty'] as num?)?.toDouble() ?? 5.0,
    scheduledInterval: map['interval'] as int? ?? 1,
    repetitions: map['repetitions'] as int? ?? 0,
    nextReview: DateTime.parse(map['next_review'] as String),
    lastReview: map['last_review'] != null
        ? DateTime.parse(map['last_review'] as String)
        : null,
  );
}

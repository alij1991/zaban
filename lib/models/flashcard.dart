import 'dart:math';
import 'package:uuid/uuid.dart';

/// SM-2 spaced repetition algorithm implementation.
class Flashcard {
  Flashcard({
    String? id,
    required this.vocabularyId,
    required this.front,
    required this.back,
    this.contextSentence,
    this.contextTranslation,
    this.easeFactor = 2.5,
    this.interval = 1,
    this.repetitions = 0,
    DateTime? nextReview,
    DateTime? lastReview,
  }) : id = id ?? const Uuid().v4(),
       nextReview = nextReview ?? DateTime.now(),
       lastReview = lastReview;

  final String id;
  final String vocabularyId;
  final String front; // English word or phrase
  final String back; // Persian translation + context
  final String? contextSentence;
  final String? contextTranslation;
  double easeFactor;
  int interval; // days
  int repetitions;
  DateTime nextReview;
  DateTime? lastReview;

  bool get isDue => DateTime.now().isAfter(nextReview);

  /// Apply SM-2 algorithm based on quality rating (0-5).
  /// 0-2: failed recall, 3: hard, 4: good, 5: easy
  void review(int quality) {
    assert(quality >= 0 && quality <= 5);

    if (quality >= 3) {
      // Successful recall
      if (repetitions == 0) {
        interval = 1;
      } else if (repetitions == 1) {
        interval = 6;
      } else {
        interval = (interval * easeFactor).round();
      }
      repetitions++;
    } else {
      // Failed recall — reset
      repetitions = 0;
      interval = 1;
    }

    easeFactor = max(
      1.3,
      easeFactor + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02)),
    );

    lastReview = DateTime.now();
    nextReview = DateTime.now().add(Duration(days: interval));
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'vocabulary_id': vocabularyId,
    'front': front,
    'back': back,
    'context_sentence': contextSentence,
    'context_translation': contextTranslation,
    'ease_factor': easeFactor,
    'interval': interval,
    'repetitions': repetitions,
    'next_review': nextReview.toIso8601String(),
    'last_review': lastReview?.toIso8601String(),
  };

  factory Flashcard.fromMap(Map<String, dynamic> map) => Flashcard(
    id: map['id'] as String,
    vocabularyId: map['vocabulary_id'] as String,
    front: map['front'] as String,
    back: map['back'] as String,
    contextSentence: map['context_sentence'] as String?,
    contextTranslation: map['context_translation'] as String?,
    easeFactor: (map['ease_factor'] as num?)?.toDouble() ?? 2.5,
    interval: map['interval'] as int? ?? 1,
    repetitions: map['repetitions'] as int? ?? 0,
    nextReview: DateTime.parse(map['next_review'] as String),
    lastReview: map['last_review'] != null
        ? DateTime.parse(map['last_review'] as String)
        : null,
  );
}

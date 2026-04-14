import 'package:uuid/uuid.dart';
import 'cefr_level.dart';

class VocabularyItem {
  VocabularyItem({
    String? id,
    required this.word,
    required this.translation,
    this.phonetic,
    this.partOfSpeech,
    this.exampleSentence,
    this.exampleTranslation,
    this.cefrLevel = CEFRLevel.a1,
    this.contextConversationId,
    DateTime? firstEncountered,
    this.timesEncountered = 1,
    this.timesReviewed = 0,
    this.timesCorrect = 0,
    this.isProductive = false,
  }) : id = id ?? const Uuid().v4(),
       firstEncountered = firstEncountered ?? DateTime.now();

  final String id;
  final String word;
  final String translation; // Persian translation
  final String? phonetic;
  final String? partOfSpeech;
  final String? exampleSentence;
  final String? exampleTranslation;
  final CEFRLevel cefrLevel;
  final String? contextConversationId;
  final DateTime firstEncountered;
  int timesEncountered;
  int timesReviewed;
  int timesCorrect;
  bool isProductive; // user has successfully used it in conversation

  double get accuracy =>
      timesReviewed > 0 ? timesCorrect / timesReviewed : 0.0;

  Map<String, dynamic> toMap() => {
    'id': id,
    'word': word,
    'translation': translation,
    'phonetic': phonetic,
    'part_of_speech': partOfSpeech,
    'example_sentence': exampleSentence,
    'example_translation': exampleTranslation,
    'cefr_level': cefrLevel.code,
    'context_conversation_id': contextConversationId,
    'first_encountered': firstEncountered.toIso8601String(),
    'times_encountered': timesEncountered,
    'times_reviewed': timesReviewed,
    'times_correct': timesCorrect,
    'is_productive': isProductive ? 1 : 0,
  };

  factory VocabularyItem.fromMap(Map<String, dynamic> map) => VocabularyItem(
    id: map['id'] as String,
    word: map['word'] as String,
    translation: map['translation'] as String,
    phonetic: map['phonetic'] as String?,
    partOfSpeech: map['part_of_speech'] as String?,
    exampleSentence: map['example_sentence'] as String?,
    exampleTranslation: map['example_translation'] as String?,
    cefrLevel: CEFRLevel.fromCode(map['cefr_level'] as String? ?? 'A1'),
    contextConversationId: map['context_conversation_id'] as String?,
    firstEncountered: DateTime.parse(map['first_encountered'] as String),
    timesEncountered: map['times_encountered'] as int? ?? 1,
    timesReviewed: map['times_reviewed'] as int? ?? 0,
    timesCorrect: map['times_correct'] as int? ?? 0,
    isProductive: (map['is_productive'] as int? ?? 0) == 1,
  );
}

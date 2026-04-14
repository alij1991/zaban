import 'dart:convert';
import 'package:uuid/uuid.dart';

enum MessageRole { user, assistant, system }

enum MessageType { text, voice, correction }

class Message {
  Message({
    String? id,
    required this.role,
    required this.content,
    this.type = MessageType.text,
    this.translation,
    this.audioPath,
    this.corrections,
    this.pronunciationScore,
    DateTime? timestamp,
  }) : id = id ?? const Uuid().v4(),
       timestamp = timestamp ?? DateTime.now();

  final String id;
  final MessageRole role;
  final String content;
  final MessageType type;
  final String? translation;
  final String? audioPath;
  final List<CorrectionItem>? corrections;
  final double? pronunciationScore;
  final DateTime timestamp;

  Map<String, dynamic> toMap() => {
    'id': id,
    'role': role.name,
    'content': content,
    'type': type.name,
    'translation': translation,
    'audio_path': audioPath,
    'pronunciation_score': pronunciationScore,
    'corrections_json': corrections != null
        ? jsonEncode(corrections!.map((c) => c.toMap()).toList())
        : null,
    'timestamp': timestamp.toIso8601String(),
  };

  factory Message.fromMap(Map<String, dynamic> map) {
    List<CorrectionItem>? corrections;
    final correctionsJson = map['corrections_json'] as String?;
    if (correctionsJson != null && correctionsJson.isNotEmpty) {
      try {
        final List<dynamic> parsed = jsonDecode(correctionsJson);
        corrections = parsed
            .map((c) => CorrectionItem.fromMap(c as Map<String, dynamic>))
            .toList();
      } catch (_) {
        corrections = null;
      }
    }

    return Message(
      id: map['id'] as String,
      role: MessageRole.values.byName(map['role'] as String),
      content: map['content'] as String,
      type: MessageType.values.byName(map['type'] as String? ?? 'text'),
      translation: map['translation'] as String?,
      audioPath: map['audio_path'] as String?,
      pronunciationScore: (map['pronunciation_score'] as num?)?.toDouble(),
      corrections: corrections,
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }

  /// Format for Ollama API
  Map<String, String> toLLMMessage() => {
    'role': role.name,
    'content': content,
  };
}

class CorrectionItem {
  const CorrectionItem({
    required this.original,
    required this.corrected,
    required this.explanation,
    this.explanationFa,
    this.category,
  });

  final String original;
  final String corrected;
  final String explanation;
  final String? explanationFa;
  final String? category; // grammar, vocabulary, pronunciation, word_order

  Map<String, dynamic> toMap() => {
    'original': original,
    'corrected': corrected,
    'explanation': explanation,
    'explanation_fa': explanationFa,
    'category': category,
  };

  factory CorrectionItem.fromMap(Map<String, dynamic> map) => CorrectionItem(
    original: map['original'] as String,
    corrected: map['corrected'] as String,
    explanation: map['explanation'] as String,
    explanationFa: map['explanation_fa'] as String?,
    category: map['category'] as String?,
  );
}

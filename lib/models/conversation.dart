import 'package:uuid/uuid.dart';
import 'message.dart';
import 'cefr_level.dart';

class Conversation {
  Conversation({
    String? id,
    required this.title,
    this.scenarioId,
    this.cefrLevel = CEFRLevel.a2,
    List<Message>? messages,
    DateTime? createdAt,
    this.summary,
  }) : id = id ?? const Uuid().v4(),
       messages = messages ?? [],
       createdAt = createdAt ?? DateTime.now();

  final String id;
  final String title;
  final String? scenarioId;
  final CEFRLevel cefrLevel;
  final List<Message> messages;
  final DateTime createdAt;
  final String? summary;

  int get messageCount => messages.length;
  Duration get duration {
    if (messages.length < 2) return Duration.zero;
    return messages.last.timestamp.difference(messages.first.timestamp);
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'scenario_id': scenarioId,
    'cefr_level': cefrLevel.code,
    'created_at': createdAt.toIso8601String(),
    'summary': summary,
  };

  factory Conversation.fromMap(Map<String, dynamic> map) => Conversation(
    id: map['id'] as String,
    title: map['title'] as String,
    scenarioId: map['scenario_id'] as String?,
    cefrLevel: CEFRLevel.fromCode(map['cefr_level'] as String? ?? 'A2'),
    createdAt: DateTime.parse(map['created_at'] as String),
    summary: map['summary'] as String?,
  );
}

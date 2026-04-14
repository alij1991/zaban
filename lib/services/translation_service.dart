import 'dart:async';
import '../models/message.dart';
import 'llm_service.dart';

/// Hybrid translation service.
///
/// Primary: LLM-based translation via Ollama (contextual, high quality).
/// Planned: NLLB-200 via CTranslate2 for fast UI-level lookups.
///
/// Note: NLLB-200 uses CC-BY-NC 4.0 (non-commercial only).
/// The LLM approach works with any Apache 2.0 model (Qwen3.5, Gemma 4).
class TranslationService {
  TranslationService({required this.llmService});

  LLMService llmService;

  /// Translate text using the LLM (contextual, higher quality).
  Future<String> translate({
    required String text,
    TranslationDirection direction = TranslationDirection.enToFa,
    String? context,
  }) async {
    final sourceLang = direction == TranslationDirection.enToFa
        ? 'English'
        : 'Persian (Farsi)';
    final targetLang = direction == TranslationDirection.enToFa
        ? 'Persian (Farsi)'
        : 'English';

    final prompt = StringBuffer()
      ..writeln('Translate the following from $sourceLang to $targetLang.')
      ..writeln('Provide ONLY the translation, nothing else.')
      ..writeln('Keep the tone and register of the original.');

    if (context != null) {
      prompt.writeln('Context: $context');
    }

    prompt
      ..writeln()
      ..writeln('Text to translate: $text');

    try {
      final result = await llmService.chat(
        messages: [
          Message(role: MessageRole.user, content: prompt.toString()),
        ],
        systemPrompt:
            'You are a professional $sourceLang to $targetLang translator. '
            'Provide accurate, natural translations. Output ONLY the translation.',
        temperature: 0.3,
        maxTokens: 512,
      );
      return result.trim();
    } catch (e) {
      return '[Translation unavailable: $e]';
    }
  }

  /// Quick word/phrase lookup — returns translation + basic info.
  Future<WordLookup> lookupWord(String word) async {
    final prompt = '''Look up the English word "$word" and provide:
1. Persian translation (in Persian script)
2. Finglish transliteration
3. Part of speech
4. A simple example sentence in English
5. The example translated to Persian

Format as:
Translation: ...
Finglish: ...
POS: ...
Example: ...
Example_FA: ...''';

    try {
      final result = await llmService.chat(
        messages: [Message(role: MessageRole.user, content: prompt)],
        systemPrompt:
            'You are a concise English-Persian dictionary. Always respond in the exact format requested.',
        temperature: 0.2,
        maxTokens: 256,
      );
      return WordLookup.parse(word, result);
    } catch (e) {
      return WordLookup(
        word: word,
        translation: '?',
        finglish: '?',
      );
    }
  }
}

enum TranslationDirection { enToFa, faToEn }

class WordLookup {
  const WordLookup({
    required this.word,
    required this.translation,
    required this.finglish,
    this.partOfSpeech,
    this.example,
    this.exampleFa,
  });

  final String word;
  final String translation;
  final String finglish;
  final String? partOfSpeech;
  final String? example;
  final String? exampleFa;

  factory WordLookup.parse(String word, String raw) {
    String extract(String label) {
      final regex = RegExp('$label\\s*:\\s*(.+)', caseSensitive: false);
      return regex.firstMatch(raw)?.group(1)?.trim() ?? '?';
    }

    return WordLookup(
      word: word,
      translation: extract('Translation'),
      finglish: extract('Finglish'),
      partOfSpeech: extract('POS'),
      example: extract('Example'),
      exampleFa: extract('Example_FA'),
    );
  }
}

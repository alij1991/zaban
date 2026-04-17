import 'dart:async';
import '../models/message.dart';
import '../models/cefr_level.dart';
import 'llm_backend.dart';

/// High-level LLM service that delegates inference to a [LLMBackend].
///
/// This class owns all teaching methodology:
/// - Context window management (trimming old messages to fit)
/// - CEFR-level-adaptive system prompts and vocabulary constraints
/// - Error correction prompts for Persian speakers
/// - Temperature tuning per student level
///
/// The backend handles raw inference only — it has no domain knowledge.
class LLMService {
  LLMService({required LLMBackend backend}) : _backend = backend;

  LLMBackend _backend;
  LLMBackend get backend => _backend;
  bool _isCancelled = false;

  /// Switch to a different backend at runtime.
  /// Disposes the old backend and initializes the new one.
  Future<void> switchBackend(LLMBackend newBackend) async {
    cancelGeneration();
    _backend.dispose();
    _backend = newBackend;
    await _backend.initialize();
  }

  /// Check if the backend is available and ready.
  Future<BackendStatus> checkStatus() => _backend.checkStatus();

  /// Cancel the current generation.
  void cancelGeneration() {
    _isCancelled = true;
    _backend.cancelGeneration();
  }

  /// Approximate token count (1 token ≈ 4 chars for English).
  static int _estimateTokens(String text) => (text.length / 4).ceil();

  /// Trim conversation history to fit within context window budget.
  static List<Map<String, String>> _buildContextWindow({
    required List<Message> messages,
    String? systemPrompt,
    int maxContextTokens = 8000,
  }) {
    final result = <Map<String, String>>[];
    int tokenBudget = maxContextTokens;

    if (systemPrompt != null) {
      result.add({'role': 'system', 'content': systemPrompt});
      tokenBudget -= _estimateTokens(systemPrompt);
    }

    final recentFirst = messages.reversed.toList();
    final kept = <Map<String, String>>[];
    for (final msg in recentFirst) {
      final tokens = _estimateTokens(msg.content);
      if (tokenBudget - tokens < 200) break;
      kept.add(msg.toLLMMessage());
      tokenBudget -= tokens;
    }

    result.addAll(kept.reversed);
    return result;
  }

  /// Inter-token idle timeout. If the backend produces no token for this long
  /// we assume it has hung and close the stream so the UI is unblocked.
  ///
  /// 30s is generous: the Ollama request already has a 120s connect/first-byte
  /// timeout, so this only fires if decoding genuinely stalls mid-response
  /// (OOM, GPU driver hiccup, model-load fallback, …).
  static const Duration _streamIdleTimeout = Duration(seconds: 30);

  /// Stream tokens from a chat completion, with context window management.
  ///
  /// The stream is wrapped in an idle-timeout so a hung backend can't leave
  /// the UI showing a perpetual "…" indicator.
  Stream<String> chatStream({
    required List<Message> messages,
    String? systemPrompt,
    double temperature = 0.7,
    int maxTokens = 1024,
    int? maxContextTokens,
  }) async* {
    _isCancelled = false;

    final contextLimit = maxContextTokens ?? _backend.contextWindowSize;
    final backendMessages = _buildContextWindow(
      messages: messages,
      systemPrompt: systemPrompt,
      maxContextTokens: contextLimit,
    );

    final source = _backend
        .chatStream(
          messages: backendMessages,
          temperature: temperature,
          maxTokens: maxTokens,
        )
        .timeout(
          _streamIdleTimeout,
          onTimeout: (sink) {
            sink.addError(
              TimeoutException(
                'LLM produced no tokens for ${_streamIdleTimeout.inSeconds}s — '
                'backend likely stalled.',
              ),
            );
            sink.close();
          },
        );

    await for (final token in source) {
      if (_isCancelled) break;
      yield token;
    }
  }

  /// Non-streaming chat for one-shot requests (translation, correction, etc.)
  /// Applies context window trimming just like chatStream().
  Future<String> chat({
    required List<Message> messages,
    String? systemPrompt,
    double temperature = 0.7,
    int maxTokens = 1024,
  }) async {
    final backendMessages = _buildContextWindow(
      messages: messages,
      systemPrompt: systemPrompt,
      maxContextTokens: _backend.contextWindowSize,
    );

    return _backend.chat(
      messages: backendMessages,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  /// Generate error corrections for user text.
  Future<String> getCorrections({
    required String userText,
    required CEFRLevel level,
  }) async {
    final systemPrompt = '''You are an English language tutor for Persian speakers.
Analyze the following text for errors. For each error, provide:
1. The original text
2. The corrected version
3. A brief explanation in English
4. A brief explanation in Persian (Farsi)
5. Category: grammar, vocabulary, word_order, or pronunciation

Focus on errors common for Persian speakers (L1 transfer):
- Article usage (a/an/the) — Persian has no articles
- Preposition errors — Persian uses different prepositions
- Subject-verb agreement, especially third-person -s ("she go" → "she goes")
- SOV to SVO word order transfer ("I yesterday to store went" → "I went to the store yesterday")
- Question formation without inversion ("You are happy?" → "Are you happy?")
- Tense usage — overuse of simple past where present perfect is needed
- Plural -s omission — Persian plurals work differently

The student is at ${level.code} level. Be encouraging.
Format your response as JSON array:
[{"original": "...", "corrected": "...", "explanation": "...", "explanation_fa": "...", "category": "..."}]
If no errors found, return [].''';

    return chat(
      messages: [Message(role: MessageRole.user, content: userText)],
      systemPrompt: systemPrompt,
      temperature: 0.3,
    );
  }

  /// Build a system prompt for conversation based on scenario and level.
  ///
  /// PREFIX-CACHE INVARIANT (do not break):
  /// The output of this function must be byte-identical for a given
  /// `(level, scenarioPrompt)` tuple so llama.cpp / Ollama can reuse the
  /// KV-cache across turns. Do NOT interpolate per-turn values (time of day,
  /// turn counter, `DateTime.now()`, username, etc.) into the prompt — those
  /// belong in the *first user message* or the trailing context, never in
  /// this prefix. Every byte change here invalidates the cache and re-costs
  /// the entire prompt each turn.
  static String buildConversationPrompt({
    required CEFRLevel level,
    String? scenarioPrompt,
    bool includeCorrections = true,
  }) {
    final vocabConstraint = switch (level) {
      CEFRLevel.a1 => '''
VOCABULARY CONSTRAINT (CRITICAL):
- Use ONLY the 500 most common English words
- Every content word must be from the A1 word list
- If you must use a harder word, immediately follow it with the Persian translation in parentheses
- Maximum sentence length: 8 words
- Use only: present simple, present continuous, "can", basic imperatives''',
      CEFRLevel.a2 => '''
VOCABULARY CONSTRAINT:
- Prefer high-frequency A1-A2 vocabulary
- Limit sentences to 12 words maximum
- Tenses: present simple/continuous, past simple, "going to" future
- If using a B1 word, explain it briefly or offer a simpler synonym''',
      CEFRLevel.b1 => '''
VOCABULARY GUIDANCE:
- A1-B1 vocabulary freely; introduce B2 words sparingly with context clues
- Sentence length up to 18 words
- All B1 grammar structures allowed''',
      _ => '''
VOCABULARY GUIDANCE:
- Full range of vocabulary and grammar appropriate for ${level.code}
- Use sophisticated language naturally; no need to simplify''',
    };

    final base = '''You are a friendly, patient English tutor helping a Persian speaker practice English.

STUDENT LEVEL: ${level.code} (${level.nameEn})

$vocabConstraint

CONVERSATION STYLE:
- Be warm, encouraging, and natural — like a patient friend, not a textbook
- CRITICAL: ALWAYS end EVERY response with a follow-up question to keep the conversation going. Never end on a statement.
- Ask ONE specific, open-ended question at a time (not yes/no questions when possible)
- If the student seems stuck or gives a very short reply, offer a choice between two possible answers in your question
- Questions should build on what the student just said — show you're listening
- Occasionally provide a key new vocabulary word with its Persian translation in parentheses
- Keep responses concise: ${level <= CEFRLevel.a2 ? '1-3 sentences PLUS a question' : level <= CEFRLevel.b1 ? '2-4 sentences PLUS a question' : '3-6 sentences PLUS a question'}

ERROR HANDLING (for Persian speakers):
- During conversation: Use gentle recasting to model the correct form naturally
  Example: Student says "I go yesterday" → You reply "Oh, you *went* yesterday? Where did you go?"
- Do NOT stop and lecture about grammar rules during conversation
- Track these common Persian L1 transfer errors mentally:
  * Missing articles (a/an/the) — Persian has no articles
  * Wrong prepositions — "afraid from" should be "afraid of"
  * Missing third-person -s — "she go" should be "she goes"
  * SOV word order — "I yesterday to store went" should be "I went to the store yesterday"
  * Question without inversion — "You are happy?" should be "Are you happy?"

IMPORTANT: Stay in character. Be natural and conversational, not didactic.''';

    if (scenarioPrompt != null) {
      return '$base\n\nSCENARIO:\n$scenarioPrompt';
    }
    return '''$base

SCENARIO: Free conversation practice. Let the student choose the topic.
Start by warmly greeting them and asking what they'd like to talk about today.
Suggest a few topics if they seem unsure.''';
  }

  /// Get recommended temperature for a CEFR level.
  static double temperatureForLevel(CEFRLevel level) => switch (level) {
        CEFRLevel.a1 => 0.4,
        CEFRLevel.a2 => 0.5,
        CEFRLevel.b1 => 0.6,
        CEFRLevel.b2 => 0.7,
        CEFRLevel.c1 || CEFRLevel.c2 => 0.8,
      };

  void dispose() {
    cancelGeneration();
    _backend.dispose();
  }
}

import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/message.dart';
import '../models/conversation.dart';
import '../models/cefr_level.dart';
import '../models/lesson.dart';
import '../services/llm_service.dart';
import '../services/database_service.dart';
import '../services/translation_service.dart';
import '../services/cefr_service.dart';
import '../services/srs_service.dart';

class ChatProvider extends ChangeNotifier {
  ChatProvider({
    required this.llmService,
    required this.db,
    required this.translationService,
    required this.cefrService,
    this.srsService,
  });

  LLMService llmService;
  final DatabaseService db;
  final TranslationService translationService;
  final CEFRService cefrService;
  final SRSService? srsService;

  Conversation? _currentConversation;
  Conversation? get currentConversation => _currentConversation;

  List<Message> get messages => _currentConversation?.messages ?? [];

  bool _isGenerating = false;
  bool get isGenerating => _isGenerating;

  bool _isCheckingErrors = false;
  bool get isCheckingErrors => _isCheckingErrors;

  String _currentResponse = '';
  String get currentResponse => _currentResponse;

  List<CorrectionItem> _lastCorrections = [];
  List<CorrectionItem> get lastCorrections => _lastCorrections;

  /// Cancel the current LLM generation.
  void cancelGeneration() {
    if (_isGenerating) {
      llmService.cancelGeneration();
      _isGenerating = false;
      // Save whatever was generated so far
      if (_currentResponse.isNotEmpty && _currentConversation != null) {
        final partialMsg = Message(
          role: MessageRole.assistant,
          content: '$_currentResponse [cancelled]',
        );
        _currentConversation!.messages.add(partialMsg);
        db.saveMessage(_currentConversation!.id, partialMsg);
      }
      _currentResponse = '';
      notifyListeners();
    }
  }

  /// Start a new conversation, optionally with a lesson scenario.
  Future<void> startConversation({
    required CEFRLevel level,
    Scenario? scenario,
  }) async {
    _currentConversation = Conversation(
      title: scenario?.titleEn ?? 'Free Conversation',
      scenarioId: scenario?.id,
      cefrLevel: level,
    );

    await db.saveConversation(_currentConversation!);

    // Generate opening message from the tutor
    final systemPrompt = LLMService.buildConversationPrompt(
      level: level,
      scenarioPrompt: scenario?.systemPrompt,
    );

    _isGenerating = true;
    _currentResponse = '';
    notifyListeners();

    try {
      final buffer = StringBuffer();
      await for (final token in llmService.chatStream(
        messages: [],
        systemPrompt: systemPrompt,
        temperature: LLMService.temperatureForLevel(level),
      )) {
        buffer.write(token);
        _currentResponse = _cleanResponse(buffer.toString());
        notifyListeners();
      }

      final cleaned = _cleanResponse(buffer.toString());
      if (cleaned.isNotEmpty) {
        final assistantMsg = Message(
          role: MessageRole.assistant,
          content: cleaned,
        );
        _currentConversation!.messages.add(assistantMsg);
        await db.saveMessage(_currentConversation!.id, assistantMsg);
      }
    } catch (e) {
      final errorMsg = Message(
        role: MessageRole.assistant,
        content: _getErrorMessage(e),
      );
      _currentConversation!.messages.add(errorMsg);
    }

    _isGenerating = false;
    _currentResponse = '';
    notifyListeners();
  }

  /// Send a message and get a streaming response.
  Future<void> sendMessage(String text, {CEFRLevel? level}) async {
    if (_currentConversation == null || text.trim().isEmpty) return;

    final cefrLevel = level ?? _currentConversation!.cefrLevel;

    // Add user message
    final userMsg = Message(
      role: MessageRole.user,
      content: text,
    );
    _currentConversation!.messages.add(userMsg);
    await db.saveMessage(_currentConversation!.id, userMsg);

    // Clear previous corrections
    _lastCorrections = [];
    notifyListeners();

    // Build system prompt
    final scenario = _currentConversation!.scenarioId != null
        ? LessonData.getById(_currentConversation!.scenarioId!)
        : null;
    final systemPrompt = LLMService.buildConversationPrompt(
      level: cefrLevel,
      scenarioPrompt: scenario?.systemPrompt,
    );

    // Generate response
    _isGenerating = true;
    _currentResponse = '';
    notifyListeners();

    try {
      final buffer = StringBuffer();
      await for (final token in llmService.chatStream(
        messages: _currentConversation!.messages,
        systemPrompt: systemPrompt,
        temperature: LLMService.temperatureForLevel(cefrLevel),
      )) {
        buffer.write(token);
        _currentResponse = _cleanResponse(buffer.toString());
        notifyListeners();
      }

      final cleaned = _cleanResponse(buffer.toString());
      if (cleaned.isNotEmpty) {
        final assistantMsg = Message(
          role: MessageRole.assistant,
          content: cleaned,
        );
        _currentConversation!.messages.add(assistantMsg);
        await db.saveMessage(_currentConversation!.id, assistantMsg);

        // Check Token Miss Rate for quality gate
        final tmr = cefrService.tokenMissRate(cleaned, cefrLevel);
        if (tmr > 0.2) {
          debugPrint('Warning: TMR=${tmr.toStringAsFixed(2)} — response may be above target level');
        }

        // Auto-extract vocabulary for SRS cards (runs in background)
        _extractVocabularyForSRS(cleaned, cefrLevel);
      }
    } catch (e) {
      final errorMsg = Message(
        role: MessageRole.assistant,
        content: _getErrorMessage(e),
      );
      _currentConversation!.messages.add(errorMsg);
    }

    _isGenerating = false;
    _currentResponse = '';
    notifyListeners();
  }

  /// Get error corrections for the last user message.
  Future<void> getCorrections(CEFRLevel level) async {
    if (_isCheckingErrors) return;

    final lastUserMsg = messages.lastWhere(
      (m) => m.role == MessageRole.user,
      orElse: () => Message(role: MessageRole.user, content: ''),
    );
    if (lastUserMsg.content.isEmpty) return;

    _isCheckingErrors = true;
    notifyListeners();

    try {
      final result = await llmService.getCorrections(
        userText: lastUserMsg.content,
        level: level,
      );

      // Parse JSON corrections
      final jsonStr = _extractJson(result);
      if (jsonStr.isNotEmpty) {
        final List<dynamic> corrections = jsonDecode(jsonStr);
        _lastCorrections = corrections
            .map((c) => CorrectionItem.fromMap(c as Map<String, dynamic>))
            .toList();
      } else {
        _lastCorrections = [];
      }
    } catch (e) {
      _lastCorrections = [];
      debugPrint('Correction error: $e');
    }

    _isCheckingErrors = false;
    notifyListeners();
  }

  /// Extract vocabulary words from tutor response and create SRS cards.
  /// Looks for words in parentheses (Persian translations) that the tutor
  /// naturally introduces, e.g., "Let's use the word 'delicious' (خوشمزه)".
  Future<void> _extractVocabularyForSRS(String response, CEFRLevel level) async {
    if (srsService == null) return;

    try {
      // Pattern 1: word (Persian translation) — tutor's natural vocabulary introduction
      final parenthetical = RegExp(
        r'"(\w+)"\s*\(([^\)]+)\)',
      );
      for (final match in parenthetical.allMatches(response)) {
        final word = match.group(1)!;
        final translation = match.group(2)!;
        // Only create cards for words the CEFR service considers at or above student level
        final wordLevel = cefrService.getWordLevel(word.toLowerCase());
        if (wordLevel != null && wordLevel >= level) {
          await srsService!.createFromConversation(
            word: word,
            translation: translation,
            sentenceContext: _extractSentenceContaining(response, word),
            sentenceTranslation: '',
          );
        }
      }

      // Pattern 2: bold/emphasized words *word* — tutor's recasting
      final emphasized = RegExp(r'\*(\w+)\*');
      for (final match in emphasized.allMatches(response)) {
        final word = match.group(1)!;
        final wordLevel = cefrService.getWordLevel(word.toLowerCase());
        if (wordLevel != null && wordLevel >= level) {
          // Look up translation asynchronously
          final lookup = await translationService.lookupWord(word);
          await srsService!.createFromConversation(
            word: word,
            translation: lookup.translation,
            sentenceContext: _extractSentenceContaining(response, word),
            sentenceTranslation: '',
            phonetic: lookup.finglish,
            partOfSpeech: lookup.partOfSpeech,
          );
        }
      }
    } catch (e) {
      debugPrint('Vocabulary extraction error: $e');
    }
  }

  /// Extract the sentence containing a specific word from text.
  String _extractSentenceContaining(String text, String word) {
    final sentences = text.split(RegExp(r'[.!?]+'));
    for (final sentence in sentences) {
      if (sentence.toLowerCase().contains(word.toLowerCase())) {
        return sentence.trim();
      }
    }
    return '';
  }

  /// Translate the last assistant message.
  Future<String> translateLastMessage() async {
    final lastAssistantMsg = messages.lastWhere(
      (m) => m.role == MessageRole.assistant,
      orElse: () => Message(role: MessageRole.assistant, content: ''),
    );
    if (lastAssistantMsg.content.isEmpty) return '';

    return translationService.translate(text: lastAssistantMsg.content);
  }

  /// Load an existing conversation.
  Future<void> loadConversation(String id) async {
    _currentConversation = await db.getConversation(id);
    _lastCorrections = [];
    notifyListeners();
  }

  /// Get conversation history.
  Future<List<Conversation>> getHistory({int limit = 50}) {
    return db.getConversations(limit: limit);
  }

  /// Delete a conversation from history. If it's the current one, clear it.
  Future<void> deleteConversation(String id) async {
    await db.deleteConversation(id);
    if (_currentConversation?.id == id) {
      _currentConversation = null;
      _lastCorrections = [];
    }
    notifyListeners();
  }

  void clearConversation() {
    cancelGeneration();
    _currentConversation = null;
    _lastCorrections = [];
    notifyListeners();
  }

  String _extractJson(String text) {
    // Try to find JSON array in the response
    final start = text.indexOf('[');
    final end = text.lastIndexOf(']');
    if (start != -1 && end != -1 && end > start) {
      return text.substring(start, end + 1);
    }
    return '[]';
  }

  /// Strip thinking tokens, control sequences, and whitespace from LLM output.
  /// Handles Qwen thinking blocks and other model artifacts.
  String _cleanResponse(String text) {
    var cleaned = text;
    // Strip Qwen thinking blocks: <think>...</think>
    cleaned = cleaned.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '');
    // Strip incomplete thinking blocks (still generating)
    cleaned = cleaned.replaceAll(RegExp(r'<think>[\s\S]*$'), '');
    // Strip other common control tokens
    cleaned = cleaned.replaceAll(RegExp(r'<\|im_start\|>.*?(?:\n|$)'), '');
    cleaned = cleaned.replaceAll(RegExp(r'<\|im_end\|>'), '');
    cleaned = cleaned.replaceAll(RegExp(r'<\|endoftext\|>'), '');
    return cleaned.trim();
  }

  String _getErrorMessage(Object error) {
    final msg = error.toString();
    debugPrint('LLM Error: $msg');

    if (msg.contains('Connection refused') || msg.contains('timed out')) {
      return 'Could not connect to the AI backend.\n\n'
          'If using Ollama: ollama serve\n'
          'If using Direct GGUF: check the model path in Settings.\n\n'
          '(اتصال به موتور هوش مصنوعی برقرار نشد. تنظیمات را بررسی کنید.)';
    }
    // Show the actual error for debugging — users need to know what went wrong
    return 'Error: ${msg.length > 200 ? '${msg.substring(0, 200)}...' : msg}\n\n'
        '(خطا رخ داد. لطفاً تنظیمات مدل را بررسی کنید.)';
  }
}

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'llm_backend.dart';

/// Ollama HTTP backend — communicates with Ollama at localhost:11434.
class OllamaBackend implements LLMBackend {
  OllamaBackend({
    required this.host,
    required this.model,
    this.requestTimeout = const Duration(seconds: 120),
  });

  final String host;
  final String model;
  final Duration requestTimeout;
  final _client = http.Client();
  bool _isCancelled = false;
  bool _isInitialized = false;

  @override
  String get name => 'Ollama ($model)';

  @override
  bool get isInitialized => _isInitialized;

  @override
  int get contextWindowSize => 8192; // Ollama manages this per model

  @override
  Future<void> initialize() async {
    // Ollama is stateless HTTP — no model loading needed from our side.
    // Just verify connectivity.
    _isInitialized = true;
  }

  @override
  Future<BackendStatus> checkStatus() async {
    try {
      final response = await _client
          .get(Uri.parse('$host/api/tags'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) {
        return BackendStatus(
          isReady: false,
          error: 'Ollama returned ${response.statusCode}',
        );
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final models = (data['models'] as List?)
              ?.map((m) => m['name'] as String)
              .toList() ??
          [];
      final found = models.any(
          (m) => m == model || m.startsWith(model) || model.contains(m));
      if (!found) {
        return BackendStatus(
          isReady: false,
          modelName: model,
          backendType: BackendType.ollama,
          availableModels: models,
          error: 'Model "$model" not found in Ollama.\n'
              'Available: ${models.where((m) => !m.contains("embed")).join(", ")}',
        );
      }
      return BackendStatus(
        isReady: true,
        modelName: model,
        backendType: BackendType.ollama,
        availableModels: models,
      );
    } on TimeoutException {
      return const BackendStatus(isReady: false, error: 'Connection timed out');
    } catch (e) {
      return BackendStatus(isReady: false, error: e.toString());
    }
  }

  @override
  Stream<String> chatStream({
    required List<Map<String, String>> messages,
    double temperature = 0.7,
    int maxTokens = 1024,
  }) async* {
    _isCancelled = false;

    final body = jsonEncode({
      'model': model,
      'messages': messages,
      'stream': true,
      'options': {
        'temperature': temperature,
        'num_predict': maxTokens,
      },
    });

    final request = http.Request('POST', Uri.parse('$host/api/chat'))
      ..headers['Content-Type'] = 'application/json'
      ..body = body;

    final streamedResponse =
        await _client.send(request).timeout(requestTimeout);

    if (streamedResponse.statusCode != 200) {
      final respBody = await streamedResponse.stream.bytesToString();
      throw Exception('Ollama error ${streamedResponse.statusCode}: $respBody');
    }

    await for (final chunk in streamedResponse.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (_isCancelled) break;
      if (chunk.trim().isEmpty) continue;
      try {
        final data = jsonDecode(chunk) as Map<String, dynamic>;
        final message = data['message'] as Map<String, dynamic>?;
        if (message != null) {
          final content = message['content'] as String? ?? '';
          if (content.isNotEmpty) yield content;
        }
        if (data['done'] == true) break;
      } catch (e) {
        // A malformed JSON line during streaming is unusual but recoverable:
        // Ollama occasionally emits keep-alive whitespace. Log at debug level
        // and keep reading the rest of the stream.
        debugPrint('Ollama: skipped malformed stream chunk: $e '
            '(first 120 chars: ${chunk.substring(0, chunk.length.clamp(0, 120))})');
      }
    }
  }

  @override
  Future<String> chat({
    required List<Map<String, String>> messages,
    double temperature = 0.7,
    int maxTokens = 1024,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$host/api/chat'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'model': model,
            'messages': messages,
            'stream': false,
            'options': {
              'temperature': temperature,
              'num_predict': maxTokens,
            },
          }),
        )
        .timeout(const Duration(seconds: 120));

    if (response.statusCode != 200) {
      throw Exception('Ollama error: ${response.statusCode}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['message'] as Map<String, dynamic>)['content'] as String;
  }

  @override
  void cancelGeneration() {
    _isCancelled = true;
  }

  @override
  void dispose() {
    _client.close();
  }
}

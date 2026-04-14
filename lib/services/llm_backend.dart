import 'dart:async';

/// Abstract backend for LLM inference.
///
/// Three implementations:
/// - [OllamaBackend]: Ollama HTTP API (localhost:11434)
/// - [DirectLlamaBackend]: llama_cpp_dart FFI (in-process, no server)
/// - [GemmaBackend]: flutter_gemma with MediaPipe LiteRT
abstract class LLMBackend {
  /// Initialize the backend (load model, start server, etc).
  /// May be expensive (multi-second model load into VRAM).
  Future<void> initialize();

  /// Whether [initialize] has completed successfully.
  bool get isInitialized;

  /// Maximum context window size in tokens.
  int get contextWindowSize;

  /// Check if this backend is available and ready.
  Future<BackendStatus> checkStatus();

  /// Stream tokens from a chat completion request.
  /// Messages are `[{'role': 'system|user|assistant', 'content': '...'}]`.
  Stream<String> chatStream({
    required List<Map<String, String>> messages,
    double temperature = 0.7,
    int maxTokens = 1024,
  });

  /// Non-streaming chat completion.
  Future<String> chat({
    required List<Map<String, String>> messages,
    double temperature = 0.7,
    int maxTokens = 1024,
  });

  /// Cancel any active generation.
  void cancelGeneration();

  /// Release resources (VRAM, connections, processes).
  void dispose();

  /// Human-readable name of this backend for the UI.
  String get name;
}

class BackendStatus {
  const BackendStatus({
    required this.isReady,
    this.modelName,
    this.error,
    this.backendType = BackendType.ollama,
    this.availableModels = const [],
  });

  final bool isReady;
  final String? modelName;
  final String? error;
  final BackendType backendType;
  final List<String> availableModels;
}

enum BackendType { ollama, directFfi, gemma }

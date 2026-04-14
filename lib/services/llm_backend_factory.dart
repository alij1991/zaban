import 'package:flutter_gemma/flutter_gemma.dart' show ModelType, ModelFileType;

import '../models/user_profile.dart';
import 'llm_backend.dart';
import 'llm_backend_ollama.dart';
import 'llm_backend_direct.dart';
import 'llm_backend_gemma.dart';

/// Factory for creating the appropriate LLMBackend from user configuration.
class LLMBackendFactory {
  /// Create a backend based on the user's profile settings.
  static LLMBackend createFromProfile(UserProfile profile) {
    switch (profile.backendType) {
      case BackendType.directFfi:
        if (profile.ggufModelPath == null || profile.ggufModelPath!.isEmpty) {
          return _createMissingModelBackend(
            'Direct GGUF',
            'No GGUF model file selected.\n\n'
            'Go to Settings → Direct GGUF → Browse or download a model.',
          );
        }
        return DirectLlamaBackend(
          modelPath: profile.ggufModelPath!,
          gpuLayers: profile.gpuLayers,
          contextSize: profile.contextSize,
        );

      case BackendType.gemma:
        if (profile.gemmaModelPath == null || profile.gemmaModelPath!.isEmpty) {
          return _createMissingModelBackend(
            'Gemma',
            'No Gemma model file selected.\n\n'
            'Go to Settings → Gemma → Browse or download a .litertlm model.',
          );
        }
        return GemmaBackend(
          modelPath: profile.gemmaModelPath!,
          modelType: ModelType.gemmaIt,
          fileType: ModelFileType.litertlm,
          maxTokens: profile.contextSize,
          huggingFaceToken: profile.huggingFaceToken,
        );

      case BackendType.ollama:
        return _createOllama(profile);
    }
  }

  /// Creates a backend that always returns an error — used when the user
  /// selected a backend type but hasn't configured a model file yet.
  static _MissingModelBackend _createMissingModelBackend(String name, String message) {
    return _MissingModelBackend(name: name, message: message);
  }

  static OllamaBackend _createOllama(UserProfile profile) {
    return OllamaBackend(
      host: profile.ollamaHost,
      model: profile.selectedModel ??
          profile.hardwareTier?.recommendedModel ??
          'gemma4:e4b',
    );
  }
}

/// A backend that always fails with a helpful message.
/// Used when the user selected a backend but didn't configure a model file.
class _MissingModelBackend implements LLMBackend {
  _MissingModelBackend({required this.name, required this.message});

  @override
  final String name;
  final String message;

  @override
  bool get isInitialized => false;

  @override
  int get contextWindowSize => 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<BackendStatus> checkStatus() async {
    return BackendStatus(
      isReady: false,
      error: message,
      modelName: null,
    );
  }

  @override
  Stream<String> chatStream({
    required List<Map<String, String>> messages,
    double temperature = 0.7,
    int maxTokens = 1024,
  }) async* {
    throw Exception(message);
  }

  @override
  Future<String> chat({
    required List<Map<String, String>> messages,
    double temperature = 0.7,
    int maxTokens = 1024,
  }) async {
    throw Exception(message);
  }

  @override
  void cancelGeneration() {}

  @override
  void dispose() {}
}

import 'dart:async';
import 'dart:io';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'llm_backend.dart';

/// Flutter Gemma backend — uses MediaPipe LiteRT for on-device inference.
///
/// Supports Gemma 4, Qwen, Phi, DeepSeek, Llama via flutter_gemma package.
/// On desktop (Windows), uses gRPC to a local inference server.
class GemmaBackend implements LLMBackend {
  GemmaBackend({
    required this.modelPath,
    this.modelType = ModelType.gemmaIt,
    this.fileType = ModelFileType.litertlm,
    this.maxTokens = 8192,
    this.huggingFaceToken,
    this.preferGpu = true,
  });

  final String modelPath;
  final ModelType modelType;
  final ModelFileType fileType;
  final int maxTokens;
  final String? huggingFaceToken;
  final bool preferGpu;
  bool _gpuFailed = false;

  bool _isInitialized = false;
  bool _isCancelled = false;
  bool _gemmaInitialized = false;

  @override
  String get name {
    final filename = modelPath.split(RegExp(r'[/\\]')).last;
    return 'Gemma ($filename)';
  }

  @override
  bool get isInitialized => _isInitialized;

  @override
  int get contextWindowSize => maxTokens;

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Validate model file exists
    if (!File(modelPath).existsSync()) {
      throw Exception('Gemma model file not found: $modelPath');
    }

    // Initialize flutter_gemma (once per process)
    if (!_gemmaInitialized) {
      await FlutterGemma.initialize(
        huggingFaceToken: huggingFaceToken,
      );
      _gemmaInitialized = true;
    }

    // Install model from local file.
    // CRITICAL: Normalize Windows backslashes to forward slashes.
    // flutter_gemma's _extractFilename uses path.split('/') which fails
    // on Windows backslash paths, causing "Active model is no longer installed".
    final normalizedPath = modelPath.replaceAll('\\', '/');
    await FlutterGemma.installModel(
      modelType: modelType,
      fileType: fileType,
    ).fromFile(normalizedPath).install();

    // Verify the model actually loaded — try GPU first, fallback to CPU
    final backend = (preferGpu && !_gpuFailed)
        ? PreferredBackend.gpu
        : PreferredBackend.cpu;
    try {
      await FlutterGemma.getActiveModel(
        maxTokens: 32,
        preferredBackend: backend,
      );
    } catch (e) {
      // If GPU failed, retry with CPU
      if (backend == PreferredBackend.gpu && !_gpuFailed) {
        _gpuFailed = true;
        try {
          await FlutterGemma.getActiveModel(
            maxTokens: 32,
            preferredBackend: PreferredBackend.cpu,
          );
          _isInitialized = true;
          return; // CPU fallback worked
        } catch (_) {}
      }
      _isInitialized = false;
      throw Exception(
        'Gemma model file exists but failed to load. '
        'The flutter_gemma plugin could not register the model on this platform.\n'
        'Error: $e',
      );
    }

    _isInitialized = true;
  }

  @override
  Future<BackendStatus> checkStatus() async {
    if (!File(modelPath).existsSync()) {
      return BackendStatus(
        isReady: false,
        error: 'Model file not found: $modelPath',
        backendType: BackendType.gemma,
      );
    }

    if (!_isInitialized) {
      try {
        await initialize();
      } catch (e) {
        return BackendStatus(
          isReady: false,
          error: 'Gemma init failed: $e',
          backendType: BackendType.gemma,
        );
      }
    }

    // Double-check model is actually usable (catches silent registration failures)
    try {
      await FlutterGemma.getActiveModel(
        maxTokens: 32,
        preferredBackend:
            preferGpu ? PreferredBackend.gpu : PreferredBackend.cpu,
      );
    } catch (e) {
      _isInitialized = false;
      return BackendStatus(
        isReady: false,
        error: 'Model file found but Gemma engine failed to load it: $e',
        backendType: BackendType.gemma,
      );
    }

    return BackendStatus(
      isReady: true,
      modelName: modelPath.split(RegExp(r'[/\\]')).last,
      backendType: BackendType.gemma,
    );
  }

  @override
  Stream<String> chatStream({
    required List<Map<String, String>> messages,
    double temperature = 0.7,
    int maxTokens = 1024,
  }) async* {
    if (!_isInitialized) await initialize();
    _isCancelled = false;

    // Extract system instruction from messages
    String? systemInstruction;
    final chatMessages = <Message>[];

    for (final msg in messages) {
      final role = msg['role'] ?? 'user';
      final content = msg['content'] ?? '';

      if (role == 'system') {
        systemInstruction = content;
      } else {
        chatMessages.add(Message.text(
          text: content,
          isUser: role == 'user',
        ));
      }
    }

    // Get the active model (use CPU if GPU failed during init)
    final model = await FlutterGemma.getActiveModel(
      maxTokens: maxTokens,
      preferredBackend: (preferGpu && !_gpuFailed)
          ? PreferredBackend.gpu
          : PreferredBackend.cpu,
    );

    // Create a chat session
    final chat = await model.createChat(
      temperature: temperature,
      tokenBuffer: maxTokens,
      systemInstruction: systemInstruction,
      modelType: modelType,
    );

    // Add all conversation messages
    for (final msg in chatMessages) {
      await chat.addQuery(msg);
    }

    // Stream the response
    await for (final response in chat.generateChatResponseAsync()) {
      if (_isCancelled) {
        chat.session.stopGeneration();
        break;
      }
      if (response is TextResponse) {
        yield response.token;
      }
      // ThinkingResponse is internal reasoning — skip for user output
    }
  }

  @override
  Future<String> chat({
    required List<Map<String, String>> messages,
    double temperature = 0.7,
    int maxTokens = 1024,
  }) async {
    final buffer = StringBuffer();
    await for (final token in chatStream(
      messages: messages,
      temperature: temperature,
      maxTokens: maxTokens,
    )) {
      buffer.write(token);
    }
    return buffer.toString();
  }

  @override
  void cancelGeneration() {
    _isCancelled = true;
  }

  @override
  void dispose() {
    _isInitialized = false;
  }
}

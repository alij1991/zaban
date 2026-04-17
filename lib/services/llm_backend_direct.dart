import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'llm_backend.dart';

/// Direct llama.cpp FFI backend — runs the model in-process via dart:ffi.
///
/// ~15-25% faster than Ollama, no separate server needed.
/// Uses `llama_cpp_dart` package with managed isolate for non-blocking inference.
class DirectLlamaBackend implements LLMBackend {
  DirectLlamaBackend({
    required this.modelPath,
    this.gpuLayers = 999,
    this.contextSize = 8192,
    this.chatFormat,
  });

  final String modelPath;
  final int gpuLayers;
  final int contextSize;

  /// Chat template format. Auto-detected from filename if null.
  PromptFormat? chatFormat;

  LlamaParent? _parent;
  bool _isInitialized = false;
  bool _isCancelled = false;

  @override
  String get name {
    final filename = modelPath.split(RegExp(r'[/\\]')).last;
    return 'Direct FFI ($filename)';
  }

  @override
  bool get isInitialized => _isInitialized;

  @override
  int get contextWindowSize => contextSize;

  /// Detect chat format from the model filename.
  PromptFormat _detectFormat() {
    if (chatFormat != null) return chatFormat!;
    final lower = modelPath.toLowerCase();
    if (lower.contains('gemma')) return GemmaFormat();
    // ChatML works for Qwen, Llama, Mistral, Yi, and most models
    return ChatMLFormat();
  }

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;

    // The Direct FFI backend ships only prebuilt Windows DLLs
    // (bin/windows/llama/) — see CLAUDE.md for the build-time GGML_BACKEND_DL
    // story. macOS would need a matching set of custom-built .dylib files,
    // which we don't ship yet. Surface a clean error instead of letting the
    // Windows-only DLL-loading code below crash with a cryptic symbol error.
    if (Platform.isMacOS) {
      throw Exception(
        'Direct GGUF backend is Windows-only right now.\n\n'
        'On macOS, switch to the Ollama backend: Settings → Backend → Ollama, '
        'then run `ollama pull qwen3:1.7b` (or any model of your choice).',
      );
    }

    // Validate model file exists
    if (!File(modelPath).existsSync()) {
      throw Exception('GGUF model file not found: $modelPath');
    }

    // On Windows: llama_cpp_dart's symbols are split across multiple DLLs:
    //   llama.dll → llama_* symbols
    //   ggml.dll  → ggml_backend_load_all and other ggml symbols
    //   ggml-base.dll, ggml-cpu.dll → backend implementations
    //
    // The package loads ONE library via DynamicLibrary.open() but needs
    // symbols from ALL of them. Fix: pre-load all DLLs into the process,
    // then set libraryPath=null so it uses DynamicLibrary.process() which
    // searches ALL loaded modules. Isolates share the same process address
    // space for native code, so this works across the child isolate too.
    if (Platform.isWindows) {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      if (File('$exeDir\\llama.dll').existsSync()) {
        for (final dll in [
          'ggml-base.dll',
          'ggml-cpu.dll',
          'ggml.dll',
          'llama.dll',
        ]) {
          final path = '$exeDir\\$dll';
          if (File(path).existsSync()) {
            try {
              DynamicLibrary.open(path);
            } catch (_) {}
          }
        }
        // Use process-wide symbol lookup (finds symbols in ALL loaded DLLs)
        Llama.libraryPath = null;
      }
    }

    final format = _detectFormat();

    final modelParams = ModelParams()..nGpuLayers = gpuLayers;
    final contextParams = ContextParams()
      ..nCtx = contextSize
      ..nPredict = -1;
    final samplerParams = SamplerParams()
      ..temp = 0.7
      ..topK = 40
      ..topP = 0.95
      ..minP = 0.05;

    final config = LlamaLoad(
      path: modelPath,
      modelParams: modelParams,
      contextParams: contextParams,
      samplingParams: samplerParams,
    );

    _parent = LlamaParent(config, format);

    try {
      await _parent!.init();
    } catch (e) {
      _parent = null;
      throw Exception(
        'Failed to load model. Try reducing GPU layers (currently $gpuLayers) '
        'or using a smaller model.\nError: $e',
      );
    }

    _isInitialized = true;
  }

  @override
  Future<BackendStatus> checkStatus() async {
    if (!File(modelPath).existsSync()) {
      return BackendStatus(
        isReady: false,
        error: 'GGUF file not found: $modelPath',
        backendType: BackendType.directFfi,
      );
    }

    if (!_isInitialized) {
      try {
        await initialize();
      } catch (e) {
        return BackendStatus(
          isReady: false,
          error: e.toString(),
          backendType: BackendType.directFfi,
        );
      }
    }

    return BackendStatus(
      isReady: true,
      modelName: modelPath.split(RegExp(r'[/\\]')).last,
      backendType: BackendType.directFfi,
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

    // Build the formatted prompt from messages using the chat format.
    // The LlamaParent's formatter handles ChatML/Gemma templates.
    _parent!.messages = messages.map((m) => <String, dynamic>{...m}).toList();

    // Format the full conversation into a single prompt string
    final prompt = _parent!.formatter?.formatMessages(_parent!.messages) ??
        _fallbackFormat(messages);

    // Send prompt and collect streamed tokens
    final completer = Completer<void>();
    _parent!.sendPrompt(prompt);

    // Listen for completion events to know when generation is done
    late StreamSubscription<CompletionEvent> completionSub;
    completionSub = _parent!.completions.listen((event) {
      if (!completer.isCompleted) completer.complete();
      completionSub.cancel();
    });

    // Yield tokens as they arrive
    await for (final token in _parent!.stream) {
      if (_isCancelled) {
        _parent!.stop();
        break;
      }
      yield token;

      // Check if completer was already completed (generation done)
      if (completer.isCompleted) break;
    }

    // Ensure we clean up
    if (!completer.isCompleted) {
      await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {},
      );
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

  /// Fallback message formatting if no PromptFormat is available.
  String _fallbackFormat(List<Map<String, String>> messages) {
    final buffer = StringBuffer();
    for (final msg in messages) {
      final role = msg['role'] ?? 'user';
      final content = msg['content'] ?? '';
      buffer.writeln('<|im_start|>$role');
      buffer.writeln(content);
      buffer.writeln('<|im_end|>');
    }
    buffer.writeln('<|im_start|>assistant');
    return buffer.toString();
  }

  @override
  void cancelGeneration() {
    _isCancelled = true;
    _parent?.stop();
  }

  @override
  void dispose() {
    _parent?.dispose();
    _parent = null;
    _isInitialized = false;
  }
}

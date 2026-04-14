import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

/// Speech-to-Text service with VAD-segmented streaming.
///
/// Architecture: Audio PCM stream → Silero VAD (30ms chunks) → on speech end,
/// send accumulated buffer to whisper.cpp → emit TranscriptionResult.
///
/// This avoids the "record entire file then transcribe" anti-pattern that
/// adds 5-10+ seconds of latency.
class STTService {
  STTService({
    this.modelSize = WhisperModelSize.small,
    this.language = 'en',
    this.vadThreshold = 0.5,
    this.silenceDurationMs = 600,
  });

  WhisperModelSize modelSize;
  String language;

  /// VAD probability threshold (0.0-1.0). Higher = stricter speech detection.
  double vadThreshold;

  /// Milliseconds of silence before considering speech ended.
  int silenceDurationMs;

  bool _isInitialized = false;
  bool _isListening = false;

  bool get isInitialized => _isInitialized;
  bool get isListening => _isListening;

  final _transcriptionController = StreamController<TranscriptionResult>.broadcast();
  Stream<TranscriptionResult> get transcriptionStream => _transcriptionController.stream;

  /// Emits amplitude levels (0.0-1.0) for UI visualization.
  final _amplitudeController = StreamController<double>.broadcast();
  Stream<double> get amplitudeStream => _amplitudeController.stream;

  /// Emits VAD state changes (speaking / silence).
  final _vadStateController = StreamController<bool>.broadcast();
  Stream<bool> get vadStateStream => _vadStateController.stream;

  // Internal state for VAD-segmented buffering
  final List<Uint8List> _speechBuffer = [];
  bool _isSpeaking = false;
  int _silenceFrames = 0;
  StreamSubscription<Uint8List>? _audioSubscription;

  /// Lookback buffer: keeps last ~300ms of audio so we don't lose
  /// the onset of speech before VAD confidence rises above threshold.
  /// At 16kHz mono 16-bit, 30ms = 960 bytes. 10 chunks ≈ 300ms.
  static const _lookbackSize = 10;
  final _lookbackBuffer = <Uint8List>[];

  /// Initialize the STT engine — loads whisper.cpp model.
  Future<void> initialize() async {
    if (_isInitialized) return;

    // TODO: Initialize whisper.cpp via FFI
    // _whisper = WhisperGgml();
    // await _whisper.initialize(model: modelSize.fileName);
    //
    // TODO: Initialize Silero VAD
    // _vad = SileroVad();
    // await _vad.initialize();

    _isInitialized = true;
  }

  /// Start listening with VAD-segmented streaming.
  ///
  /// Instead of recording a file, this:
  /// 1. Opens a PCM audio stream (16kHz, mono, 16-bit)
  /// 2. Feeds 30ms chunks to Silero VAD
  /// 3. Buffers audio while speech is detected
  /// 4. On speech end (silence > [silenceDurationMs]), sends buffer to whisper
  /// 5. Emits TranscriptionResult via [transcriptionStream]
  Future<void> startListening({Stream<Uint8List>? audioStream}) async {
    if (!_isInitialized) await initialize();
    if (_isListening) return;

    _isListening = true;
    _speechBuffer.clear();
    _lookbackBuffer.clear();
    _isSpeaking = false;
    _silenceFrames = 0;

    // In production, audioStream comes from AudioService.startStream()
    if (audioStream != null) {
      _audioSubscription = audioStream.listen(_processAudioChunk);
    }

    // TODO: Production implementation
    // final stream = await _recorder.startStream(
    //   RecordConfig(
    //     encoder: AudioEncoder.pcm16bits,
    //     sampleRate: 16000,
    //     numChannels: 1,
    //   ),
    // );
    // _audioSubscription = stream.listen(_processAudioChunk);
  }

  /// Process a single audio chunk through the VAD pipeline.
  void _processAudioChunk(Uint8List chunk) {
    // Calculate amplitude for UI visualization
    _amplitudeController.add(_calculateAmplitude(chunk));

    // TODO: Run Silero VAD on this chunk
    // final speechProb = await _vad.process(chunk);
    // For now, simulate — in production replace with actual VAD:
    final speechProb = _calculateAmplitude(chunk) > 0.1 ? 0.8 : 0.1;

    final isSpeechFrame = speechProb >= vadThreshold;

    if (isSpeechFrame) {
      if (!_isSpeaking) {
        _isSpeaking = true;
        _vadStateController.add(true);
        _speechBuffer.clear();
        // Prepend lookback buffer to capture speech onset
        _speechBuffer.addAll(_lookbackBuffer);
        _lookbackBuffer.clear();
      }
      _speechBuffer.add(chunk);
      _silenceFrames = 0;
    } else if (!_isSpeaking) {
      // Not speaking — maintain rolling lookback buffer
      _lookbackBuffer.add(chunk);
      if (_lookbackBuffer.length > _lookbackSize) {
        _lookbackBuffer.removeAt(0);
      }
    } else {
      // Still buffer silence frames (they may be mid-sentence pauses)
      _speechBuffer.add(chunk);
      _silenceFrames++;

      // 30ms per frame → silenceDurationMs / 30 = frames needed
      final silenceThreshold = silenceDurationMs ~/ 30;
      if (_silenceFrames >= silenceThreshold) {
        // Speech ended — transcribe the buffer
        _isSpeaking = false;
        _vadStateController.add(false);
        _transcribeBuffer();
      }
    }
  }

  /// Send accumulated speech buffer to whisper.cpp for transcription.
  Future<void> _transcribeBuffer() async {
    if (_speechBuffer.isEmpty) return;

    // Concatenate all buffered chunks
    final totalLength = _speechBuffer.fold<int>(0, (sum, c) => sum + c.length);
    final combined = Uint8List(totalLength);
    var offset = 0;
    for (final chunk in _speechBuffer) {
      combined.setAll(offset, chunk);
      offset += chunk.length;
    }
    _speechBuffer.clear();

    // TODO: Send to whisper.cpp for transcription
    // final result = await _whisper.transcribeBuffer(
    //   combined,
    //   sampleRate: 16000,
    //   wordTimestamps: true,
    //   language: language,
    // );
    // _transcriptionController.add(result);

    // Placeholder — emit empty result
    _transcriptionController.add(TranscriptionResult(
      text: '',
      words: [],
      language: language,
      duration: Duration(milliseconds: combined.length ~/ 32), // 16kHz mono 16-bit
    ));
  }

  /// Stop listening and transcribe any remaining buffered audio.
  Future<TranscriptionResult?> stopListening() async {
    if (!_isListening) return null;

    _isListening = false;
    await _audioSubscription?.cancel();
    _audioSubscription = null;

    // Transcribe remaining buffer if user was still speaking
    if (_speechBuffer.isNotEmpty) {
      await _transcribeBuffer();
    }

    _vadStateController.add(false);
    return null;
  }

  /// Transcribe a complete audio file (for pronunciation assessment).
  /// This is the only place where batch processing is appropriate.
  Future<TranscriptionResult> transcribeFile(String audioPath) async {
    if (!_isInitialized) await initialize();

    // TODO: whisper.cpp file transcription with word-level timestamps
    // final result = await _whisper.transcribe(
    //   audioPath,
    //   wordTimestamps: true,
    //   language: language,
    // );
    return TranscriptionResult(
      text: '',
      words: [],
      language: language,
      duration: Duration.zero,
    );
  }

  /// Calculate RMS (Root Mean Square) amplitude from PCM16 audio chunk.
  /// Returns 0.0-1.0 normalized amplitude.
  double _calculateAmplitude(Uint8List chunk) {
    if (chunk.length < 2) return 0;

    final samples = chunk.buffer.asInt16List();
    var sumSquares = 0.0;
    for (final sample in samples) {
      sumSquares += sample * sample;
    }
    // RMS = sqrt(mean of squares), normalized by max int16 value
    final rms = math.sqrt(sumSquares / samples.length) / 32767;
    return rms.clamp(0.0, 1.0);
  }

  void dispose() {
    _audioSubscription?.cancel();
    _transcriptionController.close();
    _amplitudeController.close();
    _vadStateController.close();
  }
}

class TranscriptionResult {
  const TranscriptionResult({
    required this.text,
    required this.words,
    required this.language,
    required this.duration,
  });

  final String text;
  final List<WordTimestamp> words;
  final String language;
  final Duration duration;
}

class WordTimestamp {
  const WordTimestamp({
    required this.word,
    required this.start,
    required this.end,
    this.confidence = 1.0,
  });

  final String word;
  final double start; // seconds
  final double end;
  final double confidence;
}

enum WhisperModelSize {
  tiny('ggml-tiny.bin', 75),
  base('ggml-base.bin', 142),
  small('ggml-small.bin', 466),
  medium('ggml-medium.bin', 1500),
  turbo('ggml-large-v3-turbo.bin', 1600);

  const WhisperModelSize(this.fileName, this.sizeMb);
  final String fileName;
  final int sizeMb;
}

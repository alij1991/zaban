import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Audio recording service using the `record` package.
///
/// Supports two modes:
/// 1. **File-based**: Records to WAV for transcription or pronunciation assessment
/// 2. **Streaming**: Returns `Stream<Uint8List>` of PCM data for real-time STT
class AudioService {
  AudioRecorder? _recorder;
  bool _isRecording = false;
  bool _isStreaming = false;
  String? _currentRecordingPath;
  String _recordingsDir = '';
  bool _initialized = false;

  bool get isRecording => _isRecording;
  bool get isStreaming => _isStreaming;
  String? get currentRecordingPath => _currentRecordingPath;

  final _recordingStateController = StreamController<bool>.broadcast();
  Stream<bool> get recordingState => _recordingStateController.stream;

  Future<void> initialize() async {
    if (_initialized) return;
    final appDir = await getApplicationSupportDirectory();
    _recordingsDir = p.join(appDir.path, 'recordings');
    await Directory(_recordingsDir).create(recursive: true);
    _recorder = AudioRecorder();
    _initialized = true;
  }

  /// Check microphone permission.
  Future<bool> hasPermission() async {
    if (_recorder == null) await initialize();
    return _recorder!.hasPermission();
  }

  /// Start recording to a WAV file. Returns the file path.
  Future<String> startRecording() async {
    if (_isRecording) return _currentRecordingPath!;
    if (_recorder == null) await initialize();

    final filename = 'rec_${DateTime.now().millisecondsSinceEpoch}.wav';
    _currentRecordingPath = p.join(_recordingsDir, filename);

    await _recorder!.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 256000,
      ),
      path: _currentRecordingPath!,
    );

    _isRecording = true;
    _recordingStateController.add(true);
    return _currentRecordingPath!;
  }

  /// Stop recording and return the file path.
  Future<String?> stopRecording() async {
    if (!_isRecording || _isStreaming) return null;

    final path = await _recorder!.stop();
    _isRecording = false;
    _recordingStateController.add(false);
    return path ?? _currentRecordingPath;
  }

  /// Start streaming PCM audio for real-time STT.
  Future<Stream<Uint8List>> startStream() async {
    if (_recorder == null) await initialize();

    final stream = await _recorder!.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );

    _isStreaming = true;
    _isRecording = true;
    _recordingStateController.add(true);
    return stream;
  }

  /// Stop the PCM audio stream.
  Future<void> stopStream() async {
    if (!_isStreaming) return;
    await _recorder!.stop();
    _isStreaming = false;
    _isRecording = false;
    _recordingStateController.add(false);
  }

  void dispose() {
    _recorder?.dispose();
    _recordingStateController.close();
  }
}

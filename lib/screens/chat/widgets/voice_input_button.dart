import 'dart:async';
import 'package:flutter/material.dart';

import '../../../services/audio_service.dart';
import '../../../services/whisper_transcription_service.dart';

/// Voice input button with recording state, timer, and transcription.
///
/// States: idle → recording → transcribing → done
/// Tap to start recording, tap again to stop and transcribe.
class VoiceInputButton extends StatefulWidget {
  const VoiceInputButton({
    super.key,
    required this.audioService,
    required this.whisperService,
    required this.onTranscribed,
    this.enabled = true,
  });

  final AudioService audioService;
  final WhisperTranscriptionService whisperService;
  final void Function(String text) onTranscribed;
  final bool enabled;

  @override
  State<VoiceInputButton> createState() => _VoiceInputButtonState();
}

enum _VoiceState { idle, recording, transcribing }

class _VoiceInputButtonState extends State<VoiceInputButton>
    with SingleTickerProviderStateMixin {
  _VoiceState _state = _VoiceState.idle;
  Duration _elapsed = Duration.zero;
  Timer? _timer;
  late AnimationController _pulseController;
  bool _whisperAvailable = false;
  bool _checkedWhisper = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _checkWhisper() async {
    if (_checkedWhisper) return;
    _whisperAvailable = await widget.whisperService.isAvailable();
    _checkedWhisper = true;
  }

  Future<void> _startRecording() async {
    await _checkWhisper();

    final hasPermission = await widget.audioService.hasPermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone permission denied (دسترسی میکروفون رد شد)'),
          ),
        );
      }
      return;
    }

    try {
      await widget.audioService.startRecording();
      setState(() {
        _state = _VoiceState.recording;
        _elapsed = Duration.zero;
      });

      _pulseController.repeat(reverse: true);
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _elapsed += const Duration(seconds: 1));
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Recording failed: $e')),
        );
      }
    }
  }

  Future<void> _stopAndTranscribe() async {
    _timer?.cancel();
    _pulseController.stop();
    _pulseController.reset();

    final path = await widget.audioService.stopRecording();
    if (path == null) {
      setState(() => _state = _VoiceState.idle);
      return;
    }

    // Don't transcribe very short recordings (< 0.5 seconds)
    if (_elapsed.inMilliseconds < 500) {
      setState(() => _state = _VoiceState.idle);
      return;
    }

    setState(() => _state = _VoiceState.transcribing);

    if (!_whisperAvailable) {
      // No Whisper server — show setup instructions
      setState(() => _state = _VoiceState.idle);
      if (mounted) {
        _showWhisperSetupDialog();
      }
      return;
    }

    try {
      final text = await widget.whisperService
          .transcribeFile(path)
          .timeout(const Duration(seconds: 30));
      if (text != null && text.isNotEmpty) {
        widget.onTranscribed(text);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not transcribe audio. Try speaking louder.'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Transcription error: $e')),
        );
      }
    }

    setState(() => _state = _VoiceState.idle);
  }

  void _cancel() {
    _timer?.cancel();
    _pulseController.stop();
    _pulseController.reset();
    widget.audioService.stopRecording();
    setState(() => _state = _VoiceState.idle);
  }

  void _showWhisperSetupDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Speech-to-Text Setup'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('To enable voice input, start a local Whisper server:'),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const SelectableText(
                'pip install faster-whisper-server\nfaster-whisper-server',
                style: TextStyle(
                  fontFamily: 'Consolas',
                  color: Colors.greenAccent,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Directionality(
              textDirection: TextDirection.rtl,
              child: Text(
                'برای فعال‌سازی ورودی صوتی، یک سرور Whisper محلی راه‌اندازی کنید.',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String get _timerText {
    final m = _elapsed.inMinutes.toString().padLeft(2, '0');
    final s = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return switch (_state) {
      _VoiceState.idle => IconButton(
          icon: const Icon(Icons.mic_outlined),
          onPressed: widget.enabled ? _startRecording : null,
          tooltip: 'Voice input (ورودی صوتی)',
        ),
      _VoiceState.recording => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: _cancel,
              tooltip: 'Cancel',
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
            ),
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Color.lerp(
                    Colors.red.withAlpha(40),
                    Colors.red.withAlpha(80),
                    _pulseController.value,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.mic, color: Colors.red, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      _timerText,
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        fontFamily: 'Consolas',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.stop, color: Colors.white, size: 16),
              ),
              onPressed: _stopAndTranscribe,
              tooltip: 'Stop & transcribe (توقف و رونویسی)',
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      _VoiceState.transcribing => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Text(
                'Transcribing...',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
    };
  }
}

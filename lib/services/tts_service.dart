import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Text-to-Speech service that calls a local Kokoro or Piper HTTP server.
///
/// Compatible with:
/// - Kokoro server: `python -m kokoro.serve --port 8880`
/// - Piper server: `piper --server --port 8880`
/// - Any server accepting POST with text and returning audio bytes
class TTSService {
  TTSService({
    this.host = 'http://localhost:8880',
    this.voice = 'af_heart',
    this.engine = TTSEngine.kokoro,
  });

  String host;
  String voice;
  TTSEngine engine;
  String _audioDir = '';
  bool _initialized = false;
  final _client = http.Client();

  bool get isInitialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) return;
    final appDir = await getApplicationSupportDirectory();
    _audioDir = p.join(appDir.path, 'tts_cache');
    await Directory(_audioDir).create(recursive: true);
    _initialized = true;
  }

  /// Check if the TTS server is available.
  Future<bool> isAvailable() async {
    try {
      final response = await _client
          .get(Uri.parse(host))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200 || response.statusCode == 404;
    } catch (_) {
      return false;
    }
  }

  /// Synthesize text to a WAV/MP3 file. Returns the local file path.
  Future<String?> synthesize(String text) async {
    if (!_initialized) await initialize();
    if (text.trim().isEmpty) return null;

    final filename = '${DateTime.now().millisecondsSinceEpoch}.wav';
    final outputPath = p.join(_audioDir, filename);

    try {
      // Try Kokoro-style API first
      final response = await _client.post(
        Uri.parse('$host/v1/audio/speech'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'input': text,
          'voice': voice,
          'model': 'kokoro',
          'response_format': 'wav',
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 && response.bodyBytes.length > 100) {
        await File(outputPath).writeAsBytes(response.bodyBytes);
        return outputPath;
      }
    } catch (_) {}

    // Fallback: try simple POST with form data
    try {
      final response = await _client.post(
        Uri.parse('$host/synthesize'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': text, 'voice': voice}),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 && response.bodyBytes.length > 100) {
        await File(outputPath).writeAsBytes(response.bodyBytes);
        return outputPath;
      }
    } catch (_) {}

    return null;
  }

  /// Stream synthesis: accumulate tokens until sentence boundary,
  /// then immediately synthesize while LLM continues generating.
  Stream<String> synthesizeStreaming(Stream<String> tokenStream) async* {
    final buffer = StringBuffer();

    await for (final token in tokenStream) {
      buffer.write(token);
      final text = buffer.toString();

      final sentence = _extractCompleteSentence(text);
      if (sentence != null) {
        final audioPath = await synthesize(sentence);
        if (audioPath != null) yield audioPath;
        final remaining = text.substring(
          text.indexOf(sentence) + sentence.length,
        );
        buffer
          ..clear()
          ..write(remaining.trimLeft());
      }
    }

    final remaining = buffer.toString().trim();
    if (remaining.isNotEmpty) {
      final audioPath = await synthesize(remaining);
      if (audioPath != null) yield audioPath;
    }
  }

  String? _extractCompleteSentence(String text) {
    if (text.isEmpty) return null;

    const abbreviations = {
      'dr.', 'mr.', 'mrs.', 'ms.', 'prof.', 'sr.', 'jr.',
      'vs.', 'etc.', 'e.g.', 'i.e.', 'u.s.', 'u.k.',
    };

    final newlineIdx = text.indexOf('\n');
    if (newlineIdx > 0) return text.substring(0, newlineIdx).trim();

    final pattern = RegExp(r'[.!?](?:\s|$)');
    final match = pattern.firstMatch(text);
    if (match == null) return null;

    final candidate = text.substring(0, match.end).trim();
    final lower = candidate.toLowerCase();
    for (final abbr in abbreviations) {
      if (lower.endsWith(abbr)) return null;
    }
    if (candidate.length < 5) return null;

    return candidate;
  }

  /// Clean up old TTS cache files older than 1 hour.
  Future<void> cleanCache() async {
    if (_audioDir.isEmpty) return;
    final dir = Directory(_audioDir);
    if (!await dir.exists()) return;
    final cutoff = DateTime.now().subtract(const Duration(hours: 1));
    await for (final entity in dir.list()) {
      if (entity is File) {
        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoff)) {
          await entity.delete();
        }
      }
    }
  }

  void dispose() {
    _client.close();
  }
}

enum TTSEngine {
  kokoro('Kokoro', 'MOS 4.2, 82M params'),
  piper('Piper', 'Ultra-fast ONNX, MOS 3.5');

  const TTSEngine(this.label, this.description);
  final String label;
  final String description;
}

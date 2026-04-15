import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
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

  /// Synthesize text to a WAV file. Returns the local file path once the
  /// response has been fully written. Uses chunked HTTP streaming under the
  /// hood so the server starts sending bytes as soon as the first audio chunk
  /// is synthesized. Hits an on-disk cache first so replays (tapping the
  /// speaker icon twice on the same message) skip synthesis entirely.
  Future<String?> synthesize(String text) async {
    if (!_initialized) await initialize();
    if (text.trim().isEmpty) return null;

    // Cache lookup — replaying the same sentence costs a stat() call.
    final cacheKey = sha1.convert(utf8.encode('$voice|$text')).toString();
    final cachedPath = p.join(_audioDir, 'cache_$cacheKey.wav');
    final cached = File(cachedPath);
    if (await cached.exists()) {
      final len = await cached.length();
      if (len > 100) return cachedPath;
    }

    final outputPath = cachedPath;

    // Primary: Kokoro streaming endpoint.
    try {
      final path = await _streamSynthToFile(
        Uri.parse('$host/v1/audio/speech'),
        jsonEncode({
          'input': text,
          'voice': voice,
          'model': 'kokoro',
          'response_format': 'wav',
          'stream': true,
        }),
        outputPath,
      );
      if (path != null) return path;
    } catch (_) {}

    // Fallback: buffered endpoint.
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

  /// POST with streaming body parse: writes chunks to [outputPath] as they
  /// arrive, returns the path once the stream closes cleanly. Lets the server
  /// flush first audio bytes the instant the first Kokoro chunk is ready.
  Future<String?> _streamSynthToFile(Uri uri, String jsonBody, String outputPath) async {
    final req = http.Request('POST', uri)
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonBody;

    final streamed = await _client.send(req).timeout(const Duration(seconds: 15));
    if (streamed.statusCode != 200) return null;

    final file = File(outputPath);
    final sink = file.openWrite();
    var total = 0;
    try {
      await for (final chunk in streamed.stream) {
        sink.add(chunk);
        total += chunk.length;
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (total < 100) {
      // Corrupted / empty response.
      try { await file.delete(); } catch (_) {}
      return null;
    }
    return outputPath;
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

  /// Clean up stale TTS cache files. `cache_*.wav` entries are content-hashed
  /// and kept for 7 days — they never stale (same text + voice = same bytes).
  /// Anything else (legacy timestamp-named files) is cleared after 1 hour.
  Future<void> cleanCache() async {
    if (_audioDir.isEmpty) return;
    final dir = Directory(_audioDir);
    if (!await dir.exists()) return;
    final now = DateTime.now();
    final cacheCutoff = now.subtract(const Duration(days: 7));
    final legacyCutoff = now.subtract(const Duration(hours: 1));
    await for (final entity in dir.list()) {
      if (entity is File) {
        final name = p.basename(entity.path);
        final stat = await entity.stat();
        final cutoff = name.startsWith('cache_') ? cacheCutoff : legacyCutoff;
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

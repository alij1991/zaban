import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Transcription service that calls a local Whisper HTTP server.
///
/// Compatible with:
/// - Our custom whisper_server.py (scripts/whisper_server.py)
/// - Any OpenAI-compatible /v1/audio/transcriptions endpoint
/// - whisper.cpp server (/inference endpoint)
class WhisperTranscriptionService {
  WhisperTranscriptionService({
    this.whisperHost = 'http://localhost:8000',
    this.language = 'en',
  });

  String whisperHost;
  String language;
  final _client = http.Client();

  /// Check if the Whisper server is available.
  Future<bool> isAvailable() async {
    try {
      final response = await _client
          .get(Uri.parse(whisperHost))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Whisper server check failed: $e');
      return false;
    }
  }

  /// Transcribe a WAV audio file. Returns the transcribed text.
  Future<String?> transcribeFile(String audioPath) async {
    final file = File(audioPath);
    if (!await file.exists()) {
      debugPrint('Whisper: audio file not found: $audioPath');
      return null;
    }

    final fileSize = await file.length();
    debugPrint('Whisper: transcribing $audioPath (${fileSize} bytes)');

    if (fileSize < 1000) {
      debugPrint('Whisper: file too small ($fileSize bytes), skipping');
      return null;
    }

    // Try OpenAI-compatible endpoint
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$whisperHost/v1/audio/transcriptions'),
      );
      request.fields['language'] = language;
      request.fields['response_format'] = 'json';
      request.files.add(
        await http.MultipartFile.fromPath('file', audioPath),
      );

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
      );
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint('Whisper: response ${response.statusCode}: ${response.body.substring(0, response.body.length.clamp(0, 200))}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text = (data['text'] as String?)?.trim();
        return (text != null && text.isNotEmpty) ? text : null;
      }
    } catch (e) {
      debugPrint('Whisper: OpenAI endpoint failed: $e');
    }

    // Fallback: try whisper.cpp /inference endpoint
    try {
      final bytes = await file.readAsBytes();
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$whisperHost/inference'),
      );
      request.fields['language'] = language;
      request.fields['response_format'] = 'json';
      request.files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: 'audio.wav'),
      );

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
      );
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint('Whisper fallback: ${response.statusCode}: ${response.body.substring(0, response.body.length.clamp(0, 200))}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text = (data['text'] as String?)?.trim();
        return (text != null && text.isNotEmpty) ? text : null;
      }
    } catch (e) {
      debugPrint('Whisper: fallback endpoint also failed: $e');
    }

    return null;
  }

  void dispose() {
    _client.close();
  }
}

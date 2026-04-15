import 'dart:async';
import 'dart:collection';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'tts_service.dart';

/// Streams text from an LLM, chunks it at sentence boundaries, pipelines
/// TTS synthesis for each sentence, and plays them back in order without gaps.
///
/// The point is time-to-first-audio: don't wait for the whole LLM response —
/// hand the first sentence to the TTS server the moment its punctuation
/// arrives, and start playing while later sentences are still being generated.
class SentenceTtsPlayer {
  SentenceTtsPlayer({required this.tts});

  final TTSService tts;
  final AudioPlayer _player = AudioPlayer();

  /// FIFO of pending audio file paths ready to play.
  final Queue<String> _audioQueue = Queue<String>();

  /// Text accumulated so far in the current utterance (reset on flush/cancel).
  final StringBuffer _textBuffer = StringBuffer();

  /// Where in [_textBuffer] we last emitted a sentence from.
  int _lastEmittedOffset = 0;

  /// Active synthesis jobs (so we can ignore their results after cancel).
  int _synthGeneration = 0;

  bool _isPlaying = false;
  bool _disposed = false;

  static const _abbreviations = {
    'dr.', 'mr.', 'mrs.', 'ms.', 'prof.', 'sr.', 'jr.',
    'vs.', 'etc.', 'e.g.', 'i.e.', 'u.s.', 'u.k.',
  };

  /// Call for each incremental update to the streaming response.
  /// Pass the FULL response-so-far, not just the delta.
  void acceptText(String fullText) {
    if (_disposed) return;
    _textBuffer
      ..clear()
      ..write(fullText);
    _drainCompleteSentences();
  }

  /// Call when the LLM is done. Flushes any trailing text (no terminator).
  void finalize() {
    if (_disposed) return;
    final remaining = _textBuffer.toString().substring(_lastEmittedOffset).trim();
    if (remaining.isNotEmpty) {
      _lastEmittedOffset = _textBuffer.length;
      _synthesizeAndQueue(remaining, _synthGeneration);
    }
  }

  /// Abort current playback and forget all pending audio/text.
  Future<void> cancel() async {
    _synthGeneration++;
    _audioQueue.clear();
    _textBuffer.clear();
    _lastEmittedOffset = 0;
    _isPlaying = false;
    try {
      await _player.stop();
    } catch (_) {}
  }

  void _drainCompleteSentences() {
    final text = _textBuffer.toString();
    while (_lastEmittedOffset < text.length) {
      final slice = text.substring(_lastEmittedOffset);
      final sentence = _extractCompleteSentence(slice);
      if (sentence == null) break;
      _lastEmittedOffset += sentence.length;
      // Skip any leading whitespace so the next extraction starts cleanly.
      while (_lastEmittedOffset < text.length &&
          (text[_lastEmittedOffset] == ' ' || text[_lastEmittedOffset] == '\n')) {
        _lastEmittedOffset++;
      }
      final trimmed = sentence.trim();
      if (trimmed.isEmpty) continue;
      _synthesizeAndQueue(trimmed, _synthGeneration);
    }
  }

  String? _extractCompleteSentence(String text) => extractCompleteSentence(text);

  /// Returns the prefix of [text] up to (and including) the first real
  /// sentence terminator, or null if no complete sentence yet.
  /// Skips past abbreviations ("Dr.", "e.g.") to find the next real terminator.
  /// Exposed as a top-level helper for unit testing.
  @visibleForTesting
  static String? extractCompleteSentence(String text) {
    if (text.isEmpty) return null;

    // Newlines end sentences too (lists, dialog turns).
    final newlineIdx = text.indexOf('\n');
    if (newlineIdx > 0) return text.substring(0, newlineIdx);

    // Match terminal punctuation optionally followed by closing quotes/parens,
    // then whitespace or end-of-string. Handles cases like `"Hello!" she said.`
    // and `(great idea.)` where the closing char would otherwise block firing
    // until the next space arrives.
    final pattern = RegExp('[.!?]+["\\\')\u201D\u2019\u00BB]*(?:\\s|\$)');
    var searchFrom = 0;
    while (searchFrom < text.length) {
      final match = pattern.firstMatch(text.substring(searchFrom));
      if (match == null) return null;
      final absEnd = searchFrom + match.end;
      final candidate = text.substring(0, absEnd);
      final lower = candidate.trimRight().toLowerCase();
      var isAbbrev = false;
      for (final abbr in _abbreviations) {
        if (lower.endsWith(abbr)) {
          isAbbrev = true;
          break;
        }
      }
      if (isAbbrev) {
        // Advance past this terminator and look for the next one.
        searchFrom = absEnd;
        continue;
      }
      // Require a minimum length so we don't hand ". . ." to TTS.
      if (candidate.trim().length < 3) {
        searchFrom = absEnd;
        continue;
      }
      return candidate;
    }
    return null;
  }

  /// Synthesize in the background; when done, append to the queue if still
  /// current, and kick the player if idle.
  Future<void> _synthesizeAndQueue(String sentence, int generation) async {
    try {
      final path = await tts.synthesize(sentence);
      if (_disposed || generation != _synthGeneration) return;
      if (path == null) return;
      _audioQueue.add(path);
      _pumpQueue();
    } catch (e) {
      debugPrint('TTS synth error: $e');
    }
  }

  Future<void> _pumpQueue() async {
    if (_isPlaying || _audioQueue.isEmpty || _disposed) return;
    _isPlaying = true;
    final generation = _synthGeneration;

    while (_audioQueue.isNotEmpty && !_disposed && generation == _synthGeneration) {
      final path = _audioQueue.removeFirst();
      try {
        await _player.play(DeviceFileSource(path));
        // Wait for this file to finish before starting the next.
        await _player.onPlayerComplete.first;
      } catch (e) {
        debugPrint('Audio playback error: $e');
      }
    }
    _isPlaying = false;
  }

  Future<void> dispose() async {
    _disposed = true;
    _synthGeneration++;
    _audioQueue.clear();
    try {
      await _player.stop();
      await _player.dispose();
    } catch (_) {}
  }
}

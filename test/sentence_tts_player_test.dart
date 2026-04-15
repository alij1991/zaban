import 'package:flutter_test/flutter_test.dart';
import 'package:zaban/services/sentence_tts_player.dart';

void main() {
  group('extractCompleteSentence', () {
    // Simulates the streaming extraction loop: keep feeding text, pull off
    // complete sentences as they arrive. Mirrors what SentenceTtsPlayer does
    // internally in _drainCompleteSentences().
    List<String> drain(List<String> streamingFrames) {
      final out = <String>[];
      var offset = 0;
      var full = '';
      for (final frame in streamingFrames) {
        full = frame;
        while (offset < full.length) {
          final slice = full.substring(offset);
          final s = SentenceTtsPlayer.extractCompleteSentence(slice);
          if (s == null) break;
          offset += s.length;
          while (offset < full.length &&
              (full[offset] == ' ' || full[offset] == '\n')) {
            offset++;
          }
          final trimmed = s.trim();
          if (trimmed.isNotEmpty) out.add(trimmed);
        }
      }
      return out;
    }

    test('returns null for empty / incomplete input', () {
      expect(SentenceTtsPlayer.extractCompleteSentence(''), isNull);
      expect(SentenceTtsPlayer.extractCompleteSentence('Hello there'), isNull);
      expect(SentenceTtsPlayer.extractCompleteSentence('Hi'), isNull);
    });

    test('single sentence with period', () {
      expect(
        SentenceTtsPlayer.extractCompleteSentence('Hello there. '),
        'Hello there. ',
      );
    });

    test('question mark and exclamation also terminate', () {
      expect(
        SentenceTtsPlayer.extractCompleteSentence('How are you? '),
        'How are you? ',
      );
      expect(
        SentenceTtsPlayer.extractCompleteSentence('Great! '),
        'Great! ',
      );
    });

    test('does NOT split on abbreviations', () {
      // "Dr." should not end a sentence
      expect(
        SentenceTtsPlayer.extractCompleteSentence('Hello Dr. '),
        isNull,
      );
      expect(
        SentenceTtsPlayer.extractCompleteSentence('e.g. '),
        isNull,
      );
      expect(
        SentenceTtsPlayer.extractCompleteSentence('Mr. '),
        isNull,
      );
    });

    test('newline ends a sentence even without punctuation', () {
      expect(
        SentenceTtsPlayer.extractCompleteSentence('First line\nSecond'),
        'First line',
      );
    });

    test('streaming: progressive frames yield sentences as they complete', () {
      final frames = <String>[
        'Hello',
        'Hello there',
        'Hello there.',
        'Hello there. ',
        'Hello there. How',
        'Hello there. How are',
        'Hello there. How are you?',
        'Hello there. How are you? ',
        'Hello there. How are you? Great.',
      ];
      final sentences = drain(frames);
      // All three fire: first two on whitespace, last one on end-of-string.
      expect(sentences, ['Hello there.', 'How are you?', 'Great.']);
    });

    test('streaming: final sentence with no trailing space fires at EOS', () {
      final sentences = drain(['The cat sat. The dog ran.']);
      expect(sentences, ['The cat sat.', 'The dog ran.']);
    });

    test('streaming: abbreviation mid-sentence is not a split', () {
      final sentences = drain([
        'Hello Dr. Smith. How are you today?',
      ]);
      // Should see two sentences, not three
      expect(sentences, ['Hello Dr. Smith.', 'How are you today?']);
    });

    test('closing quote/paren after punctuation fires without trailing space', () {
      // LLM emits `"Hello!"` — we used to block until the next space because
      // `"` isn't whitespace. Now the pattern accepts closing quotes/parens.
      expect(
        SentenceTtsPlayer.extractCompleteSentence('"Hello!"'),
        '"Hello!"',
      );
      expect(
        SentenceTtsPlayer.extractCompleteSentence('(great idea.)'),
        '(great idea.)',
      );
      expect(
        SentenceTtsPlayer.extractCompleteSentence('\u201CHello!\u201D'),
        '\u201CHello!\u201D',
      );
    });

    test('streaming: multiple punctuation marks collapse', () {
      final sentences = drain(['Wow!!! Amazing...']);
      expect(sentences.length, 2);
      expect(sentences[0], startsWith('Wow'));
      expect(sentences[1], startsWith('Amazing'));
    });

    test('streaming: realistic tutor response chunked across frames', () {
      // Simulate an LLM streaming "Hello! How are you today? Tell me..."
      final frames = <String>[
        'He', 'Hel', 'Hell', 'Hello',
        'Hello!',
        'Hello! ',
        'Hello! How', 'Hello! How are', 'Hello! How are you',
        'Hello! How are you today?',
        'Hello! How are you today? ',
        'Hello! How are you today? Tell',
        'Hello! How are you today? Tell me',
        'Hello! How are you today? Tell me something',
        'Hello! How are you today? Tell me something interesting.',
      ];
      final sentences = drain(frames);
      expect(sentences, [
        'Hello!',
        'How are you today?',
        'Tell me something interesting.',
      ]);
    });
  });
}

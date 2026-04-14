import 'package:flutter_test/flutter_test.dart';
import 'package:zaban/models/cefr_level.dart';
import 'package:zaban/models/flashcard.dart';
import 'package:zaban/services/cefr_service.dart';
import 'package:zaban/utils/persian_utils.dart';

void main() {
  group('CEFRLevel', () {
    test('fromCode returns correct level', () {
      expect(CEFRLevel.fromCode('B1'), CEFRLevel.b1);
      expect(CEFRLevel.fromCode('C2'), CEFRLevel.c2);
      expect(CEFRLevel.fromCode('invalid'), CEFRLevel.a1);
    });

    test('comparison operators work', () {
      expect(CEFRLevel.b1 > CEFRLevel.a2, isTrue);
      expect(CEFRLevel.a1 < CEFRLevel.c1, isTrue);
    });
  });

  group('Flashcard SM-2', () {
    test('successful review increases interval', () {
      final card = Flashcard(
        vocabularyId: 'test',
        front: 'hello',
        back: 'سلام',
      );

      card.review(4); // Good
      expect(card.repetitions, 1);
      expect(card.interval, 1);

      card.review(4); // Good again
      expect(card.repetitions, 2);
      expect(card.interval, 6);
    });

    test('failed review resets', () {
      final card = Flashcard(
        vocabularyId: 'test',
        front: 'hello',
        back: 'سلام',
        repetitions: 3,
        interval: 15,
      );

      card.review(1); // Failed
      expect(card.repetitions, 0);
      expect(card.interval, 1);
    });
  });

  group('Persian Utils', () {
    test('containsPersian detects Persian text', () {
      expect(containsPersian('سلام'), isTrue);
      expect(containsPersian('hello'), isFalse);
      expect(containsPersian('hello سلام'), isTrue);
    });

    test('isLikelyFinglish detects Finglish', () {
      expect(isLikelyFinglish('salam chetori'), isTrue);
      expect(isLikelyFinglish('hello how are you'), isFalse);
      expect(isLikelyFinglish('سلام'), isFalse);
    });

    test('persianToWesternNumerals converts correctly', () {
      expect(persianToWesternNumerals('۱۲۳'), '123');
      expect(persianToWesternNumerals('٤٥٦'), '456');
    });
  });

  group('CEFRService', () {
    final service = CEFRService();

    test('assessText returns a level', () {
      final result = service.assessText('I like to eat food and drink water');
      expect(result.level, isNotNull);
      expect(result.confidence, greaterThan(0));
    });

    test('tokenMissRate detects above-level words', () {
      final tmr = service.tokenMissRate(
        'The unprecedented juxtaposition of paradigms',
        CEFRLevel.a1,
      );
      expect(tmr, greaterThan(0));
    });
  });
}

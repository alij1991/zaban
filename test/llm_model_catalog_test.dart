import 'package:flutter_test/flutter_test.dart';
import 'package:zaban/models/llm_model_catalog.dart';

void main() {
  group('LlmModelCatalog.pickForRam', () {
    test('picks Qwen3-4B on 8 GB or more (the headline case)', () {
      expect(LlmModelCatalog.pickForRam(8).ollamaTag, 'qwen3:4b');
      expect(LlmModelCatalog.pickForRam(12).ollamaTag, 'qwen3:4b');
      expect(LlmModelCatalog.pickForRam(32).ollamaTag, 'qwen3:4b');
    });

    test('falls back to Qwen3-1.7B on 4–7 GB machines', () {
      expect(LlmModelCatalog.pickForRam(4).ollamaTag, 'qwen3:1.7b');
      expect(LlmModelCatalog.pickForRam(6).ollamaTag, 'qwen3:1.7b');
      expect(LlmModelCatalog.pickForRam(7.9).ollamaTag, 'qwen3:1.7b');
    });

    test('falls back to Gemma 3 1B on 2–3.9 GB machines', () {
      expect(LlmModelCatalog.pickForRam(2).ollamaTag, 'gemma3:1b');
      expect(LlmModelCatalog.pickForRam(3.5).ollamaTag, 'gemma3:1b');
    });

    test('sub-2 GB / unknown RAM uses the smallest candidate (never nothing)',
        () {
      expect(LlmModelCatalog.pickForRam(1).ollamaTag, 'gemma3:1b');
      expect(LlmModelCatalog.pickForRam(null).ollamaTag, 'gemma3:1b');
      expect(LlmModelCatalog.pickForRam(0).ollamaTag, 'gemma3:1b');
    });

    test('catalog is ordered largest → smallest (invariant for pickForRam)',
        () {
      final ramThresholds =
          LlmModelCatalog.candidates.map((c) => c.minRamGb).toList();
      final sorted = [...ramThresholds]..sort((a, b) => b.compareTo(a));
      expect(ramThresholds, sorted,
          reason:
              'Candidates must be ordered largest-to-smallest; the picker '
              'returns the first match and relies on this invariant.');
    });
  });
}

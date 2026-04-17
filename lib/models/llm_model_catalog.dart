/// Catalog of CPU-friendly Ollama model tags, ordered largest → smallest, each
/// with a minimum *total system RAM* requirement for comfortable use.
///
/// The thresholds include headroom for:
///   • Windows itself (~1.5 GB)
///   • The Flutter app + sqflite + provider overhead (~200 MB)
///   • Moonshine STT + Kokoro TTS sidecars (~1 GB combined)
///   • Ollama runtime (~300 MB) and KV cache (~500 MB–1 GB at 8k context)
///
/// So "Qwen3-4B needs 8 GB" really means: on an 8 GB Windows machine running
/// the full stack, there's still ~3 GB free for the LLM weights + KV cache of
/// a ~2.5 GB Q4 model. Tight but workable. Users on 10–12 GB will be happy.
///
/// The goal of this catalog is to answer ONE question cleanly:
///   "Given N GB of total RAM, which is the best model I should default to?"
///
/// The picker walks the list top-down and returns the first entry whose
/// [minRamGb] is ≤ the user's total RAM. If no RAM reading is available, we
/// conservatively default to the smallest entry.
class LlmModelCatalog {
  LlmModelCatalog._();

  /// Ordered best → smallest. Don't reorder without updating [pickForRam].
  static const List<LlmModelCandidate> candidates = [
    LlmModelCandidate(
      ollamaTag: 'qwen3:4b',
      minRamGb: 8,
      displayName: 'Qwen3-4B',
      description:
          'Bilingual (incl. Persian), strong instruction-following, '
          '~2.5 GB Q4 weights. Recommended when RAM allows.',
    ),
    LlmModelCandidate(
      ollamaTag: 'qwen3:1.7b',
      minRamGb: 4,
      displayName: 'Qwen3-1.7B',
      description:
          'Lighter Qwen3 variant, still bilingual. '
          '~1 GB Q4 weights — fits comfortably on 4–6 GB machines.',
    ),
    LlmModelCandidate(
      ollamaTag: 'gemma3:1b',
      minRamGb: 2,
      displayName: 'Gemma 3 1B',
      description:
          'Minimum viable tutor on 2–4 GB machines. '
          'English-leaning; Persian support is limited.',
    ),
  ];

  /// Pick the biggest candidate whose [minRamGb] fits in [totalRamGb].
  ///
  /// If [totalRamGb] is null (detection failed), picks the smallest candidate
  /// so we never recommend something that blows up on load. A user with real
  /// RAM they can spare can always manually upgrade from Settings.
  static LlmModelCandidate pickForRam(double? totalRamGb) {
    if (totalRamGb == null) return candidates.last;
    for (final c in candidates) {
      if (totalRamGb >= c.minRamGb) return c;
    }
    return candidates.last;
  }
}

/// One entry in [LlmModelCatalog.candidates].
class LlmModelCandidate {
  const LlmModelCandidate({
    required this.ollamaTag,
    required this.minRamGb,
    required this.displayName,
    required this.description,
  });

  /// Tag pullable via `ollama pull <tag>`. Stored verbatim in
  /// [UserProfile.selectedModel] and passed to [OllamaBackend.model].
  final String ollamaTag;

  /// Minimum total system RAM (GB) needed to comfortably run this model on
  /// a machine also hosting Windows, the Flutter app, and the STT/TTS sidecars.
  /// See the file header for the accounting.
  final double minRamGb;

  /// Short human-readable name shown in UI hints.
  final String displayName;

  /// One-sentence pitch for UI tooltips / help dialogs.
  final String description;
}

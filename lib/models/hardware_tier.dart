enum HardwareTier {
  // NOTE: `recommendedModel` is the VRAM-tier *ceiling* (what could run
  // comfortably if nothing else competed for memory). The real default is
  // chosen by `LlmModelCatalog.pickForRam(totalRamGb)` in SettingsProvider —
  // that picker is what you want to touch when "change the default model"
  // comes up. These tier strings only matter if RAM detection fails.
  high(
    label: '16 GB+ VRAM',
    recommendedModel: 'qwen3:8b',
    vramRequired: 15,
    description: 'Qwen3-8B — strong reasoning, bilingual',
  ),
  medium(
    label: '8 GB VRAM',
    recommendedModel: 'qwen3:4b',
    vramRequired: 7,
    description: 'Qwen3-4B — best sub-8B bilingual model',
  ),
  low(
    label: '4–6 GB VRAM',
    recommendedModel: 'qwen3:4b',
    vramRequired: 4,
    description: 'Qwen3-4B — fits in 6 GB VRAM with Q4 quant',
  ),
  minimal(
    label: '2 GB VRAM',
    recommendedModel: 'qwen3:1.7b',
    vramRequired: 1.5,
    description: 'Qwen3-1.7B — ultralight, still bilingual',
  ),
  cpuOnly(
    label: 'CPU Only',
    recommendedModel: 'qwen3:1.7b',
    vramRequired: 0,
    description: 'Qwen3-1.7B on CPU — 5-15 t/s; upgrades to Qwen3-4B on 8+ GB RAM',
  );

  const HardwareTier({
    required this.label,
    required this.recommendedModel,
    required this.vramRequired,
    required this.description,
  });

  final String label;
  final String recommendedModel;
  final double vramRequired;
  final String description;

  /// Kept for backward compat. With the Qwen3 switch, no tier ships with
  /// a native-audio LLM, so this always returns false. A future Gemma 4 /
  /// Qwen3-Omni swap could flip this back on for specific tiers.
  bool get hasNativeASR => false;

  String get sttRecommendation {
    // Moonshine v2 is English-only, ~100ms CPU latency, 6.65% LibriSpeech WER
    // — comfortably beats Whisper small (~1-2s CPU) for our use case. Falls
    // back to faster-whisper if moonshine-onnx isn't installed.
    if (this == HardwareTier.cpuOnly) return 'Moonshine base (CPU ONNX)';
    return 'Moonshine base (CPU ONNX) + faster-whisper fallback';
  }

  String get ttsRecommendation {
    if (this == HardwareTier.minimal || this == HardwareTier.cpuOnly) {
      return 'Piper (CPU ONNX)';
    }
    return 'Kokoro (CPU)';
  }

  static HardwareTier fromVram(double vramGb) {
    if (vramGb >= 15) return HardwareTier.high;
    if (vramGb >= 7) return HardwareTier.medium;
    if (vramGb >= 4) return HardwareTier.low;
    if (vramGb >= 1.5) return HardwareTier.minimal;
    return HardwareTier.cpuOnly;
  }
}

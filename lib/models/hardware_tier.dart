enum HardwareTier {
  high(
    label: '16 GB+ VRAM',
    recommendedModel: 'gemma4:26b-a4b',
    vramRequired: 15,
    description: 'Gemma 4 26B-A4B MoE — best quality, ~150 t/s',
  ),
  medium(
    label: '8 GB VRAM',
    recommendedModel: 'hf.co/unsloth/Qwen3.5-9B-GGUF:Q4_K_M',
    vramRequired: 7,
    description: 'Qwen3.5-9B — best sub-10B model, 201 languages',
  ),
  low(
    label: '4–6 GB VRAM',
    recommendedModel: 'gemma4:e4b',
    vramRequired: 4,
    description: 'Gemma 4 E4B — includes built-in ASR',
  ),
  minimal(
    label: '2 GB VRAM',
    recommendedModel: 'gemma4:e2b',
    vramRequired: 1.5,
    description: 'Gemma 4 E2B — ultralight with ASR',
  ),
  cpuOnly(
    label: 'CPU Only',
    recommendedModel: 'hf.co/unsloth/Qwen3.5-4B-GGUF:Q4_K_M',
    vramRequired: 0,
    description: 'Qwen3.5-4B on CPU — 5-15 t/s',
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

  bool get hasNativeASR =>
      this == HardwareTier.low || this == HardwareTier.minimal;

  String get sttRecommendation {
    if (hasNativeASR) return 'Built-in (Gemma 4 native audio)';
    if (this == HardwareTier.cpuOnly) return 'whisper.cpp small (CPU)';
    return 'faster-whisper turbo INT8';
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

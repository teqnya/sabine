/// Runtime-agnostic interface to an on-device language model.
///
/// Implementations: llama.cpp via FFI (spike). Later possibly Apple
/// Foundation Models or Gemini Nano on supported devices. Implementations
/// must never send prompts or outputs off the device (CLAUDE.md §2).
abstract interface class LocalLlm {
  /// Loads a model file from local storage. Must be called before [generate].
  Future<ModelInfo> load(LlmLoadConfig config);

  /// Runs one completion. When [request.jsonSchema] is set, decoding must be
  /// constrained to that schema (e.g. llama.cpp grammar).
  Future<LlmResult> generate(LlmRequest request);

  /// Frees the model and context memory.
  Future<void> unload();
}

class LlmLoadConfig {
  const LlmLoadConfig({
    required this.modelPath,
    this.contextSize = 2048,
    this.gpuLayers = 99,
    this.threads = 4,
  });

  final String modelPath;

  /// Keep small: the spike processes one message at a time (CLAUDE.md §6).
  final int contextSize;

  /// Layers offloaded to Metal; 0 forces CPU.
  final int gpuLayers;
  final int threads;
}

class ModelInfo {
  const ModelInfo({
    required this.name,
    required this.fileSizeBytes,
    required this.loadTime,
  });

  final String name;
  final int fileSizeBytes;
  final Duration loadTime;
}

class LlmRequest {
  const LlmRequest({
    required this.prompt,
    this.jsonSchema,
    this.maxTokens = 256,
    this.temperature = 0.0,
  });

  final String prompt;
  final Map<String, dynamic>? jsonSchema;
  final int maxTokens;
  final double temperature;
}

class LlmResult {
  const LlmResult({
    required this.text,
    required this.promptTokens,
    required this.generatedTokens,
    required this.promptEvalTime,
    required this.generationTime,
    this.peakMemoryBytes,
  });

  final String text;
  final int promptTokens;
  final int generatedTokens;
  final Duration promptEvalTime;
  final Duration generationTime;

  /// Process resident memory high-water mark, if the platform reports it.
  final int? peakMemoryBytes;

  double get generationTokensPerSecond => generationTime == Duration.zero
      ? 0
      : generatedTokens / (generationTime.inMicroseconds / 1e6);

  Duration get totalTime => promptEvalTime + generationTime;
}

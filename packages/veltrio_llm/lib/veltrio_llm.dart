/// Synchronous Dart API over llama.cpp. Calls block; run them off the UI
/// isolate (CLAUDE.md §6).
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';

import 'src/bindings.dart';

const _errLen = 512;

class LlamaException implements Exception {
  LlamaException(this.message);

  final String message;

  @override
  String toString() => 'LlamaException: $message';
}

class GenerationResult {
  const GenerationResult({
    required this.text,
    required this.promptTokens,
    required this.generatedTokens,
    required this.promptMs,
    required this.generationMs,
    required this.sampleMs,
    required this.footprintBytes,
    required this.peakFootprintBytes,
  });

  final String text;
  final int promptTokens;
  final int generatedTokens;
  final double promptMs;
  final double generationMs;

  /// Part of [generationMs] spent choosing tokens (incl. grammar checks).
  final double sampleMs;

  /// -1 when the OS does not report it.
  final int footprintBytes;
  final int peakFootprintBytes;
}

class LlamaModel {
  LlamaModel._(this._handle);

  Pointer<Void> _handle;

  /// Whether the native library is bundled for this platform.
  static bool get isAvailable {
    try {
      vlMemoryFootprint();
      return true;
    } on ArgumentError {
      return false;
    }
  }

  /// Current process memory footprint in bytes, or -1.
  static int memoryFootprint() => vlMemoryFootprint();

  /// Bytes left before iOS kills the app for memory, or null if unknown.
  static int? memoryLimitRemaining() {
    final v = vlMemoryLimitRemaining();
    return v < 0 ? null : v;
  }

  static void setLogging(bool enabled) => vlSetLogging(enabled ? 1 : 0);

  /// Compute devices llama.cpp found, e.g. "MTL0, CPU".
  static String backendInfo() => using((arena) {
    final buf = arena<Uint8>(256).cast<Utf8>();
    vlBackendInfo(buf, 256);
    return buf.toDartString();
  });

  static LlamaModel load(
    String path, {
    int contextSize = 2048,
    int gpuLayers = 99,
    int threads = 4,
  }) {
    return using((arena) {
      final err = arena<Uint8>(_errLen).cast<Utf8>();
      final handle = vlLoad(
        path.toNativeUtf8(allocator: arena),
        contextSize,
        gpuLayers,
        threads,
        err,
        _errLen,
      );
      if (handle == nullptr) throw LlamaException(err.toDartString());
      return LlamaModel._(handle);
    });
  }

  GenerationResult generate({
    String? system,
    required String user,
    String? grammar,
    int maxTokens = 256,
    double temperature = 0,
    int seed = 0,
  }) {
    if (_handle == nullptr) throw LlamaException('model disposed');
    return using((arena) {
      final outLen = math.max(4096, maxTokens * 64);
      final out = arena<Uint8>(outLen).cast<Utf8>();
      final err = arena<Uint8>(_errLen).cast<Utf8>();
      final stats = arena<VlStats>();
      final n = vlGenerate(
        _handle,
        system == null ? nullptr : system.toNativeUtf8(allocator: arena),
        user.toNativeUtf8(allocator: arena),
        grammar == null ? nullptr : grammar.toNativeUtf8(allocator: arena),
        maxTokens,
        temperature,
        seed,
        out,
        outLen,
        stats,
        err,
        _errLen,
      );
      if (n < 0) throw LlamaException(err.toDartString());
      final s = stats.ref;
      return GenerationResult(
        // A max-token cut can split a multi-byte character; never throw on it.
        text: utf8.decode(
          out.cast<Uint8>().asTypedList(n),
          allowMalformed: true,
        ),
        promptTokens: s.promptTokens,
        generatedTokens: s.generatedTokens,
        promptMs: s.promptMs,
        generationMs: s.generationMs,
        sampleMs: s.sampleMs,
        footprintBytes: s.footprintBytes,
        peakFootprintBytes: s.peakFootprintBytes,
      );
    });
  }

  void dispose() {
    if (_handle == nullptr) return;
    vlFree(_handle);
    _handle = nullptr;
  }
}

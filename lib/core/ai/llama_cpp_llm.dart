import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:veltrio_llm/veltrio_llm.dart';

import 'local_llm.dart';

/// [LocalLlm] backed by llama.cpp. All native calls run on one worker isolate
/// that owns the model, so the UI isolate never blocks (CLAUDE.md §6).
class LlamaCppLlm implements LocalLlm {
  Isolate? _isolate;
  SendPort? _commands;

  static bool get isAvailable => LlamaModel.isAvailable;

  @override
  Future<ModelInfo> load(LlmLoadConfig config) async {
    await _ensureWorker();
    final reply = await _call((
      'load',
      {
        'path': config.modelPath,
        'contextSize': config.contextSize,
        'gpuLayers': config.gpuLayers,
        'threads': config.threads,
      },
    )) as Map;
    return ModelInfo(
      name: reply['name'] as String,
      fileSizeBytes: reply['size'] as int,
      loadTime: Duration(microseconds: reply['loadUs'] as int),
    );
  }

  @override
  Future<LlmResult> generate(LlmRequest request) async {
    final r = await _call((
      'generate',
      {
        'system': request.system,
        'prompt': request.prompt,
        'grammar': request.grammar,
        'maxTokens': request.maxTokens,
        'temperature': request.temperature,
      },
    )) as Map;
    return LlmResult(
      text: r['text'] as String,
      promptTokens: r['promptTokens'] as int,
      generatedTokens: r['generatedTokens'] as int,
      promptEvalTime: _ms(r['promptMs'] as double),
      generationTime: _ms(r['generationMs'] as double),
      samplingTime: _ms(r['sampleMs'] as double),
      footprintBytes: _nonNegative(r['footprint'] as int),
      peakMemoryBytes: _nonNegative(r['peak'] as int),
    );
  }

  @override
  Future<void> unload() async {
    if (_commands == null) return;
    await _call(('unload', const {}));
  }

  /// Unloads the model and stops the worker isolate.
  Future<void> dispose() async {
    await unload();
    _isolate?.kill();
    _isolate = null;
    _commands = null;
  }

  Future<void> _ensureWorker() async {
    if (_commands != null) return;
    final ready = ReceivePort();
    _isolate = await Isolate.spawn(_worker, ready.sendPort);
    _commands = await ready.first as SendPort;
  }

  Future<Object?> _call((String, Map<String, Object?>) command) async {
    final commands = _commands;
    if (commands == null) throw LlmException('no model loaded');
    final reply = ReceivePort();
    commands.send((command.$1, command.$2, reply.sendPort));
    final (ok, value) = await reply.first as (bool, Object?);
    if (!ok) throw LlmException(value as String);
    return value;
  }

  static Duration _ms(double ms) => Duration(microseconds: (ms * 1000).round());
  static int? _nonNegative(int v) => v < 0 ? null : v;
}

void _worker(SendPort ready) {
  final commands = ReceivePort();
  ready.send(commands.sendPort);
  LlamaModel? model;

  commands.listen((message) {
    final (op, args, reply) =
        message as (String, Map<String, Object?>, SendPort);
    try {
      switch (op) {
        case 'load':
          model?.dispose();
          final path = args['path'] as String;
          final sw = Stopwatch()..start();
          model = LlamaModel.load(
            path,
            contextSize: args['contextSize'] as int,
            gpuLayers: args['gpuLayers'] as int,
            threads: args['threads'] as int,
          );
          reply.send((
            true,
            {
              'name': path.split(Platform.pathSeparator).last,
              'size': File(path).lengthSync(),
              'loadUs': sw.elapsedMicroseconds,
            },
          ));
        case 'generate':
          final m = model;
          if (m == null) throw LlamaException('no model loaded');
          final r = m.generate(
            system: args['system'] as String?,
            user: args['prompt'] as String,
            grammar: args['grammar'] as String?,
            maxTokens: args['maxTokens'] as int,
            temperature: args['temperature'] as double,
          );
          reply.send((
            true,
            {
              'text': r.text,
              'promptTokens': r.promptTokens,
              'generatedTokens': r.generatedTokens,
              'promptMs': r.promptMs,
              'generationMs': r.generationMs,
              'sampleMs': r.sampleMs,
              'footprint': r.footprintBytes,
              'peak': r.peakFootprintBytes,
            },
          ));
        case 'unload':
          model?.dispose();
          model = null;
          reply.send((true, null));
        default:
          reply.send((false, 'unknown op $op'));
      }
    } on LlamaException catch (e) {
      reply.send((false, e.message));
    } catch (e) {
      reply.send((false, e.toString()));
    }
  });
}

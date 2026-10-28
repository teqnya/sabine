import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:veltrio_llm/veltrio_llm.dart' show LlamaModel;

import '../../core/ai/llama_cpp_llm.dart';
import '../../core/ai/local_llm.dart';
import 'test_dataset.dart';
import 'triage_runner.dart';

/// Phase 0 spike screen: load a GGUF model side-loaded into the app's
/// Documents folder, run triage on one or all test messages, and show raw
/// output, parse result, speed and memory. Nothing leaves the device.
class SpikeScreen extends StatefulWidget {
  const SpikeScreen({super.key});

  @override
  State<SpikeScreen> createState() => _SpikeScreenState();
}

class _SpikeScreenState extends State<SpikeScreen> {
  final _llm = LlamaCppLlm();

  TestDataset? _dataset;
  TriagePrompt? _prompt;
  List<File> _models = const [];
  File? _selectedModel;
  ModelInfo? _loaded;
  String? _selectedMessageId;

  bool _busy = false;
  bool _cancel = false;
  String? _status;
  String? _error;
  TriageRun? _lastRun;
  BatchReport? _report;
  (int, int)? _progress;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _llm.dispose();
    super.dispose();
  }

  static String get _documentsDir =>
      '${Platform.environment['HOME'] ?? ''}/Documents';

  Future<void> _init() async {
    try {
      final results = await Future.wait([
        rootBundle.loadString('spike/testdata/messages.json'),
        rootBundle.loadString('spike/testdata/labels.json'),
        rootBundle.loadString('lib/core/ai/prompts/triage.v1.txt'),
        rootBundle.loadString('lib/core/ai/schemas/triage.v1.gbnf'),
      ]);
      final ds = TestDataset.parse(results[0], results[1]);
      setState(() {
        _dataset = ds;
        _prompt = TriagePrompt(template: results[2], grammar: results[3]);
        _selectedMessageId = ds.messages.first.id;
      });
    } catch (e) {
      setState(() => _error = 'Failed to load test data: $e');
    }
    _scanModels();
    await _autorun();
  }

  /// Spike-only: when launched with `VELTRIO_AUTORUN=model.gguf`, loads
  /// that model, runs the batch and prints results to the console so runs can
  /// be repeated and captured from the Mac. Prints ids, labels and metrics for
  /// the synthetic test set only.
  Future<void> _autorun() async {
    final name = Platform.environment['VELTRIO_AUTORUN'];
    if (name == null || _dataset == null) return;
    final match = _models.where((f) => f.uri.pathSegments.last == name);
    if (match.isEmpty) {
      _log('ERROR model $name not found in Documents');
      return;
    }
    setState(() => _selectedModel = match.first);
    await _load();
    final loaded = _loaded;
    if (loaded == null) {
      _log('ERROR load failed: $_error');
      return;
    }
    _log(
      'LOADED ${loaded.name} in ${_secs(loaded.loadTime)}; '
      'footprint ${_mb(LlamaModel.memoryFootprint())}',
    );
    await _runAll();
    final report = _report;
    if (report == null) {
      _log('ERROR batch failed: $_error');
      return;
    }
    for (final r in report.runs) {
      final s = r.stats;
      _log(
        'RUN ${r.message.id} ${r.message.language} '
        'expected=${r.label.category.wire} got=${r.result?.category.wire ?? 'error'} '
        '${s == null ? '' : 'prompt=${s.promptTokens}tok/${s.promptEvalTime.inMilliseconds}ms '
                  'gen=${s.generatedTokens}tok/${s.generationTime.inMilliseconds}ms '
                  '${s.generationTokensPerSecond.toStringAsFixed(1)}tok/s '
                  'peak=${s.peakMemoryBytes == null ? '?' : _mb(s.peakMemoryBytes!)}'}'
        '${r.truncated ? ' truncated' : ''}'
        '${r.error == null ? '' : ' error="${r.error}" raw=${r.raw}'}',
      );
    }
    final score = report.score;
    final remaining = LlamaModel.memoryLimitRemaining();
    _log(
      'SUMMARY accuracy=${_pct(score.accuracy)} (${score.correct}/${score.total}) '
      'byLang=${score.accuracyByLanguage.map((k, v) => MapEntry(k, _pct(v)))} '
      'errors=${report.errors} wall=${_secs(report.wallTime)} '
      'avg=${_secs(report.averagePerMessage)}/msg '
      'tok/s=${report.averageTokensPerSecond.toStringAsFixed(1)} '
      'peak=${report.peakMemoryBytes == null ? '?' : _mb(report.peakMemoryBytes!)} '
      'headroom=${remaining == null ? '?' : _mb(remaining)}',
    );
  }

  // ignore: avoid_print
  static void _log(String line) => print('VELTRIO $line');

  void _scanModels() {
    final dir = Directory(_documentsDir);
    final models = dir.existsSync()
        ? (dir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.gguf'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path)))
        : <File>[];
    setState(() {
      _models = models;
      if (_selectedModel == null ||
          !models.any((m) => m.path == _selectedModel!.path)) {
        _selectedModel = models.isEmpty ? null : models.first;
      }
    });
  }

  Future<void> _guard(String status, Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _status = status;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      setState(() => _error = e is LlmException ? e.message : e.toString());
    } finally {
      setState(() {
        _busy = false;
        _status = null;
      });
    }
  }

  Future<void> _load() => _guard('Loading model…', () async {
    final info = await _llm.load(
      LlmLoadConfig(modelPath: _selectedModel!.path),
    );
    setState(() => _loaded = info);
  });

  Future<void> _unload() => _guard('Unloading…', () async {
    await _llm.unload();
    setState(() => _loaded = null);
  });

  Future<void> _runOne() => _guard('Running triage…', () async {
    final ds = _dataset!;
    final m = ds.messages.firstWhere((m) => m.id == _selectedMessageId);
    final run = await runTriage(_llm, _prompt!, m, ds.labels[m.id]!);
    setState(() => _lastRun = run);
  });

  Future<void> _runAll() => _guard('Running batch…', () async {
    _cancel = false;
    final report = await runBatch(
      _llm,
      _prompt!,
      _dataset!,
      onProgress: (done, total) => setState(() => _progress = (done, total)),
      isCancelled: () => _cancel,
    );
    setState(() {
      _report = report;
      _progress = null;
    });
  });

  @override
  Widget build(BuildContext context) {
    final ds = _dataset;
    return Scaffold(
      appBar: AppBar(title: const Text('Veltrio · Phase 0 spike')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _memoryCard(),
          if (_error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(_error!),
              ),
            ),
          if (_status != null) ...[
            Text(_status!),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: _progress == null ? null : _progress!.$1 / _progress!.$2,
            ),
            const SizedBox(height: 8),
          ],
          _modelSection(),
          if (ds != null && _loaded != null) ...[
            const Divider(height: 32),
            _messageSection(ds),
            const Divider(height: 32),
            _batchSection(ds),
          ],
        ],
      ),
    );
  }

  Widget _memoryCard() {
    if (!LlamaCppLlm.isAvailable) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'Native llama.cpp library is not bundled for this platform.',
          ),
        ),
      );
    }
    final remaining = LlamaModel.memoryLimitRemaining();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'Memory footprint: ${_mb(LlamaModel.memoryFootprint())}'
          '${remaining == null ? '' : ' · left before iOS kills app: ${_mb(remaining)}'}',
        ),
      ),
    );
  }

  Widget _modelSection() {
    if (_models.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'No .gguf models found in the app\'s Documents folder. '
            'Copy one with:\n'
            'xcrun devicectl device copy to --device <id> '
            '--domain-type appDataContainer --domain-identifier com.teqnya.veltrio '
            '--source <model.gguf> --destination Documents/<model.gguf>',
          ),
          TextButton(onPressed: _scanModels, child: const Text('Rescan')),
        ],
      );
    }
    final loaded = _loaded;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButton<File>(
          isExpanded: true,
          value: _selectedModel,
          items: [
            for (final f in _models)
              DropdownMenuItem(
                value: f,
                child: Text(
                  '${f.uri.pathSegments.last} (${_mb(f.lengthSync())})',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: _busy ? null : (f) => setState(() => _selectedModel = f),
        ),
        Wrap(
          spacing: 8,
          children: [
            FilledButton(
              onPressed: _busy || _selectedModel == null ? null : _load,
              child: const Text('Load'),
            ),
            OutlinedButton(
              onPressed: _busy || loaded == null ? null : _unload,
              child: const Text('Unload'),
            ),
            TextButton(
              onPressed: _busy ? null : _scanModels,
              child: const Text('Rescan'),
            ),
          ],
        ),
        if (loaded != null)
          Text(
            'Loaded ${loaded.name} (${_mb(loaded.fileSizeBytes)}) '
            'in ${_secs(loaded.loadTime)}',
          ),
      ],
    );
  }

  Widget _messageSection(TestDataset ds) {
    final run = _lastRun;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Single message', style: Theme.of(context).textTheme.titleMedium),
        DropdownButton<String>(
          isExpanded: true,
          value: _selectedMessageId,
          items: [
            for (final m in ds.messages)
              DropdownMenuItem(
                value: m.id,
                child: Text(
                  '${m.id} · ${m.language} · ${m.subject}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: _busy
              ? null
              : (id) => setState(() => _selectedMessageId = id),
        ),
        FilledButton(
          onPressed: _busy ? null : _runOne,
          child: const Text('Run triage'),
        ),
        if (run != null) ...[
          const SizedBox(height: 8),
          Text(
            'Expected: ${run.label.category.wire} · '
            'Model suggestion: ${run.result?.category.wire ?? '—'} '
            '${run.correct ? '✓' : '✗'}',
          ),
          if (run.result != null) Text('Summary: ${run.result!.summary}'),
          if (run.error != null) Text('Error: ${run.error}'),
          if (run.truncated) const Text('Body clipped to fit the context.'),
          if (run.stats != null) Text(_statsLine(run.stats!)),
          const SizedBox(height: 4),
          const Text('Raw output:'),
          SelectableText(
            run.raw ?? '—',
            style: const TextStyle(fontFamily: 'Menlo'),
          ),
        ],
      ],
    );
  }

  Widget _batchSection(TestDataset ds) {
    final report = _report;
    final score = report?.score;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Batch (${ds.messages.length} messages)',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Wrap(
          spacing: 8,
          children: [
            FilledButton(
              onPressed: _busy ? null : _runAll,
              child: const Text('Run all'),
            ),
            if (_busy && _progress != null)
              OutlinedButton(
                onPressed: () => _cancel = true,
                child: Text('Cancel (${_progress!.$1}/${_progress!.$2})'),
              ),
          ],
        ),
        if (report != null && score != null) ...[
          const SizedBox(height: 8),
          Text(
            'Accuracy: ${_pct(score.accuracy)} (${score.correct}/${score.total}) '
            '${score.meetsTarget ? '— meets 85% target' : '— below 85% target'}',
          ),
          Text(
            'By language: ${score.accuracyByLanguage.entries.map((e) => '${e.key} ${_pct(e.value)}').join(', ')}',
          ),
          Text(
            'Errors: ${report.errors} (parse failures: ${score.parseFailures})',
          ),
          Text(
            'Total ${_secs(report.wallTime)} · avg ${_secs(report.averagePerMessage)}/message'
            ' · ${report.averageTokensPerSecond.toStringAsFixed(1)} tok/s',
          ),
          if (report.peakMemoryBytes != null)
            Text('Peak memory: ${_mb(report.peakMemoryBytes!)}'),
          const SizedBox(height: 8),
          for (final r in report.runs)
            Text(
              '${r.correct ? '✓' : '✗'} ${r.message.id} ${r.message.language}: '
              'expected ${r.label.category.wire}, got ${r.result?.category.wire ?? 'error'}',
            ),
        ],
      ],
    );
  }

  static String _statsLine(LlmResult s) =>
      'Prompt ${s.promptTokens} tok in ${_secs(s.promptEvalTime)} · '
      'generated ${s.generatedTokens} tok in ${_secs(s.generationTime)} '
      '(${s.generationTokensPerSecond.toStringAsFixed(1)} tok/s) · '
      'total ${_secs(s.totalTime)}'
      '${s.peakMemoryBytes == null ? '' : ' · peak ${_mb(s.peakMemoryBytes!)}'}';

  static String _mb(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  static String _secs(Duration d) =>
      '${(d.inMilliseconds / 1000).toStringAsFixed(2)} s';
  static String _pct(double v) => '${(v * 100).toStringAsFixed(0)}%';
}

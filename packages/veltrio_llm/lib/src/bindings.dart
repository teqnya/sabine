// FFI declarations for src/veltrio_llm.h. Keep in sync with the header.
@DefaultAsset('package:veltrio_llm/veltrio_llm.dart')
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

final class VlStats extends Struct {
  @Int32()
  external int promptTokens;
  @Int32()
  external int generatedTokens;
  @Double()
  external double promptMs;
  @Double()
  external double generationMs;
  @Double()
  external double sampleMs;
  @Int64()
  external int footprintBytes;
  @Int64()
  external int peakFootprintBytes;
}

@Native<Void Function(Int32)>(symbol: 'vl_set_logging')
external void vlSetLogging(int enabled);

@Native<
  Pointer<Void> Function(
    Pointer<Utf8>,
    Int32,
    Int32,
    Int32,
    Pointer<Utf8>,
    Int32,
  )
>(symbol: 'vl_load')
external Pointer<Void> vlLoad(
  Pointer<Utf8> modelPath,
  int nCtx,
  int nGpuLayers,
  int nThreads,
  Pointer<Utf8> err,
  int errLen,
);

@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<Utf8>,
    Int32,
    Float,
    Uint32,
    Pointer<Utf8>,
    Int32,
    Pointer<VlStats>,
    Pointer<Utf8>,
    Int32,
  )
>(symbol: 'vl_generate')
external int vlGenerate(
  Pointer<Void> handle,
  Pointer<Utf8> system,
  Pointer<Utf8> user,
  Pointer<Utf8> grammar,
  int maxTokens,
  double temperature,
  int seed,
  Pointer<Utf8> out,
  int outLen,
  Pointer<VlStats> stats,
  Pointer<Utf8> err,
  int errLen,
);

@Native<Void Function(Pointer<Void>)>(symbol: 'vl_free')
external void vlFree(Pointer<Void> handle);

@Native<Int32 Function(Pointer<Utf8>, Int32)>(symbol: 'vl_backend_info')
external int vlBackendInfo(Pointer<Utf8> buf, int bufLen);

@Native<Int64 Function()>(symbol: 'vl_memory_footprint')
external int vlMemoryFootprint();

@Native<Int64 Function()>(symbol: 'vl_memory_limit_remaining')
external int vlMemoryLimitRemaining();

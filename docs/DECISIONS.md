# Decisions & Findings Log

Newest entries at the top. Each entry: date, decision/finding, rationale.

---

## 2026-10-28 — Prompt-prefix KV cache (owner chose this speed-up)

- The wrapper keeps the previous prompt's tokens and reuses the KV cache for the longest common prefix (`llama_memory_seq_rm`); only the tail is decoded. If a cache cannot remove part of a sequence (e.g. sliding-window attention, as in Gemma 3), it falls back to a clean context. A host test checks that output equals a fresh context.
- iPhone 13, Qwen2.5-1.5B: 126 of ~240 prompt tokens reused; prompt time **~1.0 s → ~0.4 s**. Per message **2.6 s → 2.0 s** (≈1.6 s warm); 5 messages in 10.0 s; same answers (4/5).
- Projection for 50 messages: **~80 s** (target 30 s). The JSON summary (24–55 tokens, 1.0–2.5 s) is now the largest cost. The next lever is to split classification from summarization (owner decision pending).

---

## 2026-10-28 — First on-device measurements (Qwen2.5-1.5B-Instruct Q4_K_M)

Device: iPhone 13 (A15, 4 GB), iOS 27.0.1, profile build, Metal (`MTL0`) with all layers offloaded, context 2048, greedy decoding, `triage.v1` prompt + GBNF grammar. Test set: **5 seed messages only** (full set of 50 pending).

| Metric | Value |
|---|---|
| Model file | 1,066 MB (Apache-2.0, sha256-verified) |
| Load time | 16.6 s cold (first load after copy), 1.8–3.8 s warm |
| Memory | footprint ~240 MB loaded, **peak 278 MB**; jetsam headroom ~1.85 GB (mmap'd weights are not counted against the limit) |
| Prompt | ~250 tokens in ~1.0 s (~240 tok/s) |
| Generation | **~22 tok/s**; 24–55 tokens per message (JSON + summary) |
| Per message | **2.6 s** average; 5 messages in 13.0 s |
| Accuracy | **4/5 (80%)**: de 2/2, ar 1/1, en 1/2. Miss: newsletter (m004) labelled noise, model said fyi |
| Output validity | 5/5 valid JSON (grammar-constrained) |

Findings:
- **Grammar fast path:** applying the GBNF grammar to the full ~150k-token Qwen vocabulary on every step halved speed (9.7 tok/s). Checking only the chosen token, and masking the full vocabulary only when that token is rejected (as llama.cpp's `common_sampler` does), gives 22 tok/s. Sampling is now 30–70 ms per message.
- **Timing bug fixed:** Metal decoding is asynchronous. Without `llama_synchronize` after the prompt, prompt time was billed to generation.
- **Summary quality:** for the Arabic message the summary was generic and in English, although the prompt asks for the email's language. Needs prompt work or a separate summary pass.
- **50-message target (< 30 s):** at 2.6 s per message, 50 messages take ~130 s, about 4× over target. Main costs: prompt processing (~40%) and summary tokens. Options: (1) reuse the KV cache for the fixed instruction prefix, (2) classify first with a short output and summarize only messages that matter, (3) a smaller model for triage.
- `HOME` is not the app container when launched via devicectl. The Documents path now comes from a native channel. Autorun is triggered by a `Documents/autorun.txt` file.

---

## 2026-10-28 — First app running on the device ✅

- **Xcode 26.3 deploys to iOS 27.0.1.** The signed debug and profile builds of the placeholder app install and launch on the iPhone 13 (wireless, via `devicectl`). The Xcode 27 / Apple Silicon risk does not block the spike.
- Signing with Teqnya UG (`3267CMJYRV`) works; Xcode created the provisioning profile for `com.teqnya.veltrio` automatically.
- **Disk lessons:** the first connection to an iOS 27 device extracts debug symbols into `~/Library/Developer/Xcode/iOS DeviceSupport` (>5 GB), and that filled the disk. The owner freed space: **~12 GB free** after the builds. The iOS 18.1 simulator `.dmg` (8.2 GB, SIP-protected) is still present; it can be removed via Recovery mode.
- **Spike measurements use profile builds** (`flutter build ios --profile`). Debug builds need the Flutter tool attached and are not representative of performance.
- How to run: `flutter build ios --profile && xcrun devicectl device install app --device 00008110-0018090E0AF2401E build/ios/iphoneos/Runner.app`

---

## 2026-10-28 — First device build attempt

- The iOS 26.3.1 platform is now installed, and the phone ("iPhone SE" = iPhone 13) shows as an eligible destination.
- After the restart, the orphaned iOS 18.1 runtime was re-registered from its SIP-protected `.dmg` (17.7 GB of runtimes in total). It was deleted again with `simctl`; the 8.2 GB `.dmg` remains. **Free disk: ~2 GB.**
- **Signing fails:** Xcode's session for teqnya.developer@gmail.com expired ("login details were rejected"), so no provisioning profile can be created for `com.teqnya.veltrio`. The owner must sign in again in Xcode → Settings → Accounts.
- **Device fails:** *"The developer disk image could not be mounted on this device."* Likely causes: phone locked, Developer Mode off, or a wireless-only connection. Retry over USB with the phone unlocked.
- **Structural risk:** **Xcode 27 is Apple Silicon only and needs macOS 26.6 or later** (per Apple forum and third-party reports; not checked against Apple's own release notes). This Intel Mac on macOS 15.8 can never run it. If Xcode 26.3 can't deploy to iOS 27, then on-device testing needs an Apple Silicon Mac. Flutter is also deprecating Intel hosts.

---

## 2026-10-28 — Product name and bundle ID

- **Product name: Veltrio** (shown on the home screen and in the app title). Repo, folder and Dart package stay `sabine` (internal only).
- **Bundle ID: `com.teqnya.veltrio`** on iOS (RunnerTests: `com.teqnya.veltrio.RunnerTests`) and as the Android `applicationId`. The owner gave `Veltrio.teqnya.com` and chose its reverse-domain form. The Android `namespace` and Kotlin package stay `com.teqnya.sabine` (internal, not user-visible).
- **Orphaned iOS 18.1 simulator `.dmg` (8.2 GB)** in `/System/Library/AssetsV2` is SIP-`restricted`, so `sudo rm` fails ("Operation not permitted"). Only `mobileassetd` can remove it, usually on its own or after a restart. SIP stays enabled.

---

## 2026-10-28 — Signing, Xcode build setup, device identity

- **Signing team:** Teqnya UG (haftungsbeschraenkt), team `3267CMJYRV` (paid), Apple ID teqnya.developer@gmail.com. Bundle ID `com.teqnya.sabine`.
- **Xcode DerivedData:** the global Xcode setting pointed to a disconnected external drive (`/Volumes/My Passport/.../Bandaroza-Mobile/ios/build`). The owner chose to reset it to the default (`~/Library/Developer/Xcode/DerivedData`). This affects all Xcode projects on this Mac.
- **Removed the iOS 18.1 Simulator runtime** with `xcrun simctl runtime delete`. It was unused, because Xcode 26.3 needs the 26.2 runtime.
- **Blocker:** Xcode 26.3 refuses every iOS device destination with *"iOS 26.2 is not installed"*. The iOS 26.2 platform component has to be installed (Xcode → Settings → Components, or `xcodebuild -downloadPlatform iOS`, roughly 8 GB including the simulator).
- **Device identity:** the test phone is named "iPhone SE", but `devicectl` reports it as an **iPhone 13 (iPhone14,5)**, A15 with 4 GB, running **iOS 27.0.1**. The spike therefore measures on the brief's iPhone 13 hardware, on iOS 27.
- **Open risk:** Xcode 26.3 is older than iOS 27. Deploying to the device may need newer Xcode device support. We will only know after the platform is installed.

---

## 2026-10-28 — Owner decisions: binding and test device

- **Binding: own thin FFI wrapper over llama.cpp** (no plugin). llama.cpp is vendored as a git submodule pinned to a release tag, built as an XCFramework, and called from Dart via `dart:ffi` in a separate isolate. Rationale: brief preference, full control, no build-time binary downloads from third parties, and a smaller dependency surface.
- **llama.cpp pinned to release `b11968`** (shallow submodule at `third_party/llama.cpp`). CMake 4.4.5 is installed as the prebuilt Homebrew cask, because the formula would have compiled from source on this Intel macOS.
- **Test device: iPhone SE (A15, 4 GB), iOS 27.0.1 only.** The iPhone 13 on iOS 15.8.1 is dropped from the spike. Its chip class and RAM are the same, so the memory bar is the same; iOS 15 runtime compatibility stays **unverified**. CLAUDE.md §3 is updated.

---

## 2026-10-28 — llama.cpp binding options (decided below: own FFI wrapper)

Checked 2026-10-28:

| Option | Status | iOS min | Notes |
|---|---|---|---|
| `llamadart` 0.16.5 (pub.dev) | Very active (released 2026-10-27) | **16.4** | Downloads prebuilt native binaries from GitHub releases at build time (SHA-256 verified). Large surface: LiteRT-LM, Stable Diffusion, web. No telemetry found in `lib/`; uses `package:http` only in the build hook. **Cannot target the iPhone 13 on iOS 15.8.1.** |
| `llama_cpp_dart` 0.2.2 | Last release 2026-01-02 | n/a | Bindings only; we would build llama.cpp ourselves anyway. |
| `fllama`, `maid_llm` | Stale (2024) | — | Rejected. |
| `flutter_llama` 1.2.1 | Active, GitLab | not checked | Unknown maintainer; would need a full review. |
| **Own thin FFI wrapper** + llama.cpp built as an XCFramework | — | **15.0 (to verify)** | Upstream `build-xcframework.sh` defaults to iOS 16.4, but the Metal code guards newer APIs with `@available`, so a 15.0 build may work. **Untested upstream on iOS 15.** Needs `cmake`. |

## 2026-10-28 — Flutter toolchain (CLAUDE.md §11 step 1, continued)

- Flutter **3.47.8** stable, Dart 3.13.7, in `~/development/flutter`. Flutter and Dart analytics are **disabled**.
- Flutter's iOS templates default to **IPHONEOS_DEPLOYMENT_TARGET = 15.0**, so the project targets iOS 15.0 with no override.
- `flutter doctor` warns that **Flutter is deprecating Intel-Mac hosts**. A future Flutter release will need an Apple Silicon Mac to build. Medium-term risk for this dev machine.
- Connected device: **iPhone SE, iOS 27.0.1** (A15-class, chip ID 00008110). The iPhone 13 on iOS 15.8.1 named in the brief was not connected.
- Android toolchain is incomplete (cmdline-tools missing). Not needed for the spike.
- Free disk after the Flutter install: **~2.4 GB**.

---

## 2026-10-28 — Setup decisions (owner)

- **Disk:** cleared rebuildable caches in `~/Library/Caches` (Homebrew, Playwright, pnpm, Java, node-gyp), which freed about 2.7 GB of disk; **5.7 GB free** now. This is enough for the Flutter SDK and scaffold. **More space is still needed before the model downloads (~5 GB for 3 models).**
- **Flutter install:** `git clone` of the stable channel into `~/development/flutter`, so the version can be pinned if iOS 15 support becomes an issue.
- **Git:** remote `https://github.com/teqnya/sabine.git`. Initial commit on `main`; spike work on branch `spike/on-device-llm`.

---

## 2026-10-28 — Dev environment inspection (CLAUDE.md §11 step 1)

**Findings**

| Item | Value | Impact |
|---|---|---|
| Host | MacBook, Intel Core i5-8257U (x86_64), 8 GB RAM, macOS 15.8.2 | Fine for building. Slow for llama.cpp builds; desktop model tests will run on CPU only. |
| Xcode | 26.3 (17C529), iOS SDK 26.2 | The iOS SDK accepts deployment targets down to **12.0**, so **iOS 15.0 is achievable** from Xcode's side. |
| Device support | DeviceSupport folders present for iOS 15.0–16.4 | On-device debugging of the iPhone 13 (iOS 15.8.1) should work. Confirm when the device is connected. |
| Flutter / Dart | **Not installed** | Blocker. Once installed, confirm that this Flutter stable release still supports an iOS 15.0 deployment target (CLAUDE.md §7). |
| CocoaPods | Installed (`/usr/local/bin/pod`) | OK |
| CMake | **Not installed** | Needed to build llama.cpp (`brew install cmake`). |
| Homebrew | 7.0.9 | OK |
| iOS Simulator runtimes | None installed | Acceptable: the spike has to run on the real device anyway (Metal and memory figures are only meaningful there). |
| Free disk | **~3 GB of 113 GB** | Blocker. Estimated need: Flutter SDK ~3 GB, Xcode build artifacts/DerivedData ~3–5 GB, llama.cpp ~1 GB, 3 GGUF models ~1–2 GB each. **≈15–20 GB free required.** |

**Conclusion:** the toolchain can target iOS 15 once Flutter is installed and confirmed. Work is blocked on disk space and on installing Flutter.

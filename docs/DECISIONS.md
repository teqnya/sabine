# Decisions & Findings Log

Newest entries at the top. Each entry: date, decision/finding, rationale.

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

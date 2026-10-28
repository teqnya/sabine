# CLAUDE.md — AI Secretary (local-first, privacy-absolute)

This file is the working brief for Claude Code. Read it fully before making changes. Update it when decisions change.

## 1. Product in one paragraph

A Flutter mobile app (iPhone first, Android later) that acts as an **AI secretary for managers at mid-sized companies** (primary market: Germany/DACH). It reads the user's email and calendar, builds a daily brief, triages email, drafts replies in the user's style, and suggests meeting slots. **Everything runs on the device. There is no backend, no account system, no cloud database, and no message content ever leaves the phone.** Privacy is the product's headline feature.

Core promise: "No account. No cloud. No copy of your mail on our side."

## 2. Non-negotiable principles

1. **No server of ours.** No backend, no analytics SDKs, no crash reporters that send content, no ad SDKs. If a feature needs a server, the feature is cut or redesigned.
2. **No message content leaves the device**, except direct, user-authorized traffic between the phone and the user's own mail/calendar provider (Gmail API, Microsoft Graph).
3. **AI inference is on-device only.** No calls to cloud LLM APIs. Do not add one "temporarily".
4. **Nothing is sent on the user's behalf without explicit approval.** Drafts only; the user taps to approve. No auto-send in v1.
5. **Least privilege.** Start with read-only scopes. Request send/modify scopes only when the user enables the feature.
6. **Secrets and data at rest are encrypted.** Tokens in Keychain (iOS) / Keystore (Android). Local DB encrypted (SQLCipher).
7. **Be honest in the UI.** Show when a result is a model suggestion, and never hide failures.

## 3. Current phase: Phase 0 — On-device model spike (2 weeks)

Goal: decide with numbers whether a small on-device model is good enough for a manager's daily mail.

### Test device (hard constraints)
- **iPhone SE (A15, 4 GB RAM), iOS 27.0.1** (owner decision 2026-10-28; replaces the iPhone 13 on iOS 15.8.1, which is not measured in the spike, so iOS 15 compatibility stays unverified).
- Apple Foundation Models are NOT available (needs iOS 26 + Apple Intelligence hardware). Do not build on them for the spike.
- iOS apps are typically killed above roughly 2–2.5 GB memory on this device; keep model + context within that.
- Treat this A15 / 4 GB device as the **minimum bar**, not the target. Real target devices are newer.
- Set the iOS deployment target to the lowest value the installed Xcode supports (aim for 15.0). Verify Xcode/Flutter versions before choosing; report if the toolchain cannot target iOS 15.

### Inference stack
- **llama.cpp** (GGUF models, Q4 quantization), bound to Flutter via FFI or a maintained Flutter plugin. Verify current package maintenance and iOS 15 compatibility before adopting any plugin; prefer a thin own FFI wrapper if plugins are stale.
- Models to compare (verify availability and licenses at download time):
  - Qwen 2.5/3 ~1.5B (Q4)
  - Gemma 2/3 ~2B (Q4)
  - Llama 3.2 ~3B (Q4) — may exceed memory limits; test carefully
- Models are downloaded by the developer for the spike (side-loaded or fetched once). Final product delivery of models is an open question (see section 9).

### Spike tasks (measure each per model)
1. **Triage classification**: urgent / needs decision / FYI / noise. Output must be **structured JSON** (use grammar-constrained / JSON-schema decoding if llama.cpp supports it).
2. **One-line summary** per message; multi-step summary for long threads (chunk, summarize, merge).
3. **Reply drafting** in German, English, Arabic; judged on tone and usability.
4. **Extraction** of dates, times, tasks, and meeting requests from message text.
5. **Performance**: tokens/sec, time per message, peak memory, device temperature behavior, battery drain, number of messages processed before throttling.

### Test data
- 50 messages. Prefer **synthetic or anonymized** messages in German/English/Arabic covering: meeting requests, invoices, escalations, newsletters, internal FYIs, long threads.
- Store test data in `spike/testdata/` with a `labels.json` (ground truth category, expected extraction). Never commit real personal mail.

### Success criteria
- Classification agreement with the owner's labels **>= 85%** on 50 messages.
- Drafts need only minor edits in most cases (owner rates 1–5; target avg >= 3.5 for EN/DE).
- Full brief for ~50 messages in **< 30 seconds** on target hardware (note the A15 test device separately).
- No crashes from memory pressure; no thermal shutdown in a 50-message run.

### Spike deliverable
`spike/RESULTS.md`: a table comparing models (accuracy, speed, memory, quality notes per language), screenshots, and a clear go / no-go / adjust recommendation.

## 4. Product scope after the spike (v1 plan, do not build yet)

Three modules only:
1. **Brief on open**: today's meetings, top messages needing a reply, overdue follow-ups. Built in seconds when the app opens (background execution on iOS is unreliable; do not depend on it).
2. **Email triage + reply drafts** in the user's style (style learned locally from sent mail, stored locally).
3. **Calendar assistant**: propose slots, create events/drafts for approval.

An **Approvals inbox** (approve / edit / reject) is the single place where any outgoing action is confirmed.

Deferred (not v1): data/file analysis, deep Drive/OneDrive search, multi-user delegation, team policies, central audit, web dashboard, any server.

## 5. Integrations (all direct from device)

- **Microsoft 365 (Graph)** first: most mid-sized German companies use it. OAuth 2.0 with **PKCE**, system browser (ASWebAuthenticationSession / Custom Tabs), no client secret on device.
- **Gmail + Google Calendar** second. Note: Google requires a security assessment (CASA) for restricted Gmail scopes in production; plan for this cost/time. Use read-only scopes in the spike.
- Spike may use a test mailbox or exported/synthetic data instead of live OAuth. Do not block the model evaluation on OAuth.
- Tokens only in Keychain/Keystore. Refresh tokens handled on device.

## 6. Architecture (target)

```
lib/
  main.dart
  app/                # app shell, routing, theming, l10n (de, en, ar; RTL support)
  core/
    ai/               # LLM interface + llama.cpp FFI implementation, prompt templates, JSON schemas
    storage/          # encrypted DB (SQLCipher), secure storage wrappers
    mail/             # provider-agnostic MailProvider interface (Graph, Gmail)
    calendar/         # CalendarProvider interface
    approvals/        # approval queue domain logic
  features/
    brief/
    triage/
    drafts/
    calendar_assistant/
    settings/
ios/                  # native glue (FFI build config, background tasks if needed)
android/
spike/
  testdata/
  RESULTS.md
```

Guidelines:
- Put the LLM behind an abstract interface (`LocalLlm`) so models/runtimes can be swapped (llama.cpp now; Apple Foundation Models / Gemini Nano later on supported devices).
- Run inference in a **separate isolate**; never block the UI thread.
- Keep prompts and JSON schemas in versioned files, not scattered in code.
- Prefer deterministic logic (rules, regex, date parsing) over the model wherever it is accurate enough; use the model for summarizing and drafting.
- Process **one message at a time** with a small context; chunk long threads. Do not assume large context windows.

## 7. Tech stack and conventions

- Flutter (stable channel), Dart null-safety. Check that the chosen Flutter version still supports the iOS deployment target; report conflicts instead of silently raising it.
- State management: Riverpod. Navigation: go_router. Serialization: json_serializable/freezed (or plain classes if simpler).
- Localization from day one: German, English, Arabic (RTL must work).
- Lints: `flutter_analyze` clean; format with `dart format`. Small, focused commits.
- Tests: unit tests for parsing, prompt/schema validation, and the approvals queue. A golden test set for model outputs lives in `spike/`.
- Do not add dependencies without stating why; avoid anything that phones home. Review each package for network calls and telemetry.

## 8. Security and privacy checklist (verify before every release)

- [ ] No network calls other than to the user's mail/calendar provider (and one-time model download if applicable).
- [ ] No analytics, ads, or content-sending crash reporting.
- [ ] Tokens in Keychain/Keystore only; DB encrypted; key protected by biometrics/device passcode.
- [ ] Logs never contain message content or tokens (release builds log nothing sensitive).
- [ ] App backgrounding hides sensitive screens in the app switcher.
- [ ] Optional backup is end-to-end encrypted to the user's own iCloud/Google Drive; we never hold keys.
- [ ] Privacy policy and App Store privacy labels accurately say "Data not collected".

## 9. Open questions (ask the owner; do not decide silently)

1. How are model files delivered to users in production (bundled vs on-demand download; size limits, licensing)?
2. Pricing/billing model: App Store / Google Play subscription, plus bulk licensing for companies.
3. How "user style" is learned locally and how much sent mail is needed.
4. Minimum supported device for v1 (likely iPhone 15 Pro+ for best quality; iPhone 13 for degraded mode?).
5. Which Xcode/Flutter versions are installed on the dev Mac, and can they target iOS 15.8.1?

## 10. Working agreements for Claude Code

- Work in small steps; after each step, say what changed and how to run it.
- Never commit secrets, real emails, or personal data. Use `.gitignore` for model files (`*.gguf`), local test data, and build outputs.
- Before large decisions (new dependency, architecture change, scope change), propose options and wait for the owner.
- Record decisions and spike findings in `docs/DECISIONS.md` (create it) with date and rationale.
- If a requirement conflicts with Section 2, stop and ask. Section 2 wins.
- Git: the repository URL will be provided by the owner; push to a feature branch (`spike/on-device-llm`) and open work for review rather than force-pushing to `main`.

## 11. First actions for Claude Code

1. Inspect the environment: `flutter doctor -v`, Xcode version, available iOS SDKs; report whether iOS 15 deployment is achievable.
2. Initialize the Flutter project (if not present) with the structure in section 6 and the git remote supplied by the owner.
3. Build the Phase 0 spike screen: pick a model file, run it on a test message, show JSON output, tokens/sec, and memory use.
4. Add the test-data format and a batch runner that scores classification against `labels.json`.
5. Produce `spike/RESULTS.md` with the comparison and a recommendation.

# Spike test data

**Synthetic messages only. Never commit real mail.** Put any real or anonymized local data in `spike/testdata/local/`, which is git-ignored.

## `messages.json`
An array of objects with these fields:

| Field | Type | Notes |
|---|---|---|
| `id` | string | Unique ID, e.g. `m001` |
| `language` | string | `de`, `en` or `ar` |
| `from` | string | `Name <address>` |
| `subject` | string | |
| `date` | string | ISO 8601 with offset |
| `body` | string | Plain text |

## `labels.json`
The owner's ground truth. Every message needs exactly one entry.

| Field | Type | Notes |
|---|---|---|
| `id` | string | Matches a message `id` |
| `category` | string | `urgent` \| `needs_decision` \| `fyi` \| `noise` |
| `expected_dates` | string[] | ISO 8601 date or date-time (no offset), as the extractor should return them |
| `expected_tasks` | string[] | Free text describing each task, for manual judgement |
| `meeting_request` | bool | |

The loader (`lib/features/spike/test_dataset.dart`) rejects unknown categories, duplicate IDs, unlabeled messages and labels without a message.

Status: 5 seed messages. Target: 50, spread across the three languages and across meeting requests, invoices, escalations, newsletters, internal FYIs and long threads.

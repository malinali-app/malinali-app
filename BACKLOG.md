# Backlog

## Features

### Pulaar → French translation

Direction switcher is disabled until this is implemented. Today the app is **French → Pulaar** only.

- [ ] **Reverse lexical lookup** — Match on `translated_word` (Pulaar), return French lemma + category for “Par mot”.
- [ ] **Reverse FTS / expansions** — Tokenize Pulaar input (Unicode / extended Latin: ɓ, ɗ, ŋ, ƴ, …); expand via `translated_word` → French; build FTS query for Pulaar-in-French-out.
- [ ] **Search index (optional but recommended)** — Second FTS row or table `pulaar → french` at index build time for ranking and simpler queries.
- [ ] **UI mapping** — Primary line = target language (French out), subtitle = source (Pulaar); highlights and dedupe aligned with direction.
- [ ] **Re-enable direction switcher** — Wire `_LanguageDirectionSwitcher` once search + UI are symmetric.
- [ ] **Pulaar speech input** (later) — Would need a Pulaar-capable ASR model; French Vosk stays FR-only.

## Nice to have

- [ ] Search / widget tests for lexical dedupe, phrase sources, and FTS rebuild after sync.
- [ ] Import UI polish for custom SQLite / text-file dictionaries.
- [ ] Offline-first messaging when Turso is configured but unreachable.
- [ ] iOS build and parity (mic currently Android-only).

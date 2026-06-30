# Structured Content and Shared Blocks

## Model Records Before Formatting

Parse documents into explicit records with fields such as:

- stable identifier or generated sequence;
- source text or transcribed text for final output;
- normalized key for matching only;
- options or child paragraphs;
- answer or paired content;
- source file and page;
- shared-block identifier;
- uncertainty and non-text markers.

Do not use paragraph count or a numbered-line regular expression as the authoritative record count. Numberless records, wrapped lines, and shared material invalidate that shortcut.

Keep normalization separate from transcription. Normalized keys may remove spacing noise, unify punctuation, or simplify comparison, but they must not replace final wording. Do not use normalized keys to expand abbreviations, translate terminology, summarize phrases, or alter measured values.

## Pair Two Documents

1. Parse each source independently.
2. Compare explicit identifiers when present.
3. Compare normalized keys from stems or stable leading text.
4. Preserve original order as a fallback signal, not as sole proof.
5. Produce an unresolved list for duplicates, omissions, and numberless records.
6. Proceed to merge only when every record is paired or explicitly waived.

## Shared Stems and Shared Options

Recognize range markers such as `（x~y题共用题干）` or `（x~y题共用选项）` and general equivalents.

Represent the marker, shared material, and every dependent record from `x` through `y` as one atomic group. Apply these invariants:

- keep normal spacing before the group;
- keep the marker, shared material, and dependent records contiguous;
- insert no blank paragraph between records inside the group;
- resume normal spacing before the next independent record;
- shuffle or move the whole group, never an individual dependent record.

## Answer Placement and Cleanup

- Keep answer placement as a presentation rule separate from answer matching.
- For answer-left layouts, use a dedicated prefix run such as `【A】\t1．` and a separate stem run.
- Remove explanations only after answers have been extracted and paired.
- When a printed answer is absent, use an explicit unknown/uncertain marker rather than inferring from handwriting or domain knowledge.

## Group-Safe Randomization

1. Convert independent records and shared groups into a list of top-level units.
2. Shuffle only that top-level list with an explicit seed.
3. Preserve the internal order of each shared group.
4. Renumber display identifiers only after shuffling, and update range markers consistently.
5. Verify total record count, group count, group membership, and answer association after each generated variant.

## Acceptance Checks

- every source record appears exactly once;
- final output preserves source wording unless the user explicitly requested rewriting;
- every paired answer remains attached to the correct record;
- numberless records are represented;
- every shared range is complete and contiguous;
- no shared block is split during spacing or randomization;
- uncertainty and skipped-content markers remain source-traceable.

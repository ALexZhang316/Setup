---
name: question-bank-docx
description: Extract, filter, and rewrite structured exam question banks stored as .docx files. Use when Codex needs to parse question and option blocks, handle shared-stem or shared-option groups, select questions by literal or regex rules, and generate a filtered answer-first .docx output.
---

# Question Bank DOCX

Use this skill for question-bank style `.docx` files where:
- each question head looks like `A12.` or `B 7.`
- options are separate paragraphs like `A.` to `E.`
- shared groups are marked with a full-width parenthesized range followed by either a shared-stem or shared-options label

Do not use this skill for heavily table-based documents, scanned PDFs, or unstructured notes.

## Workflow

1. Inspect the source file and confirm it is a paragraph-based question bank.
2. Choose a matcher:
   - Use `--preset drug` or `--preset imaging` for the two workflows already validated in this environment.
   - Use repeated `--literal` and `--regex` flags for custom rules.
3. Run a dry pass first with `--summary-only` to confirm counts before writing output.
4. Generate the final `.docx` with an explicit `--output` path and title.
5. Open the output with `python-docx` or the local Office app and spot-check one shared-stem group and one shared-option group.

## Matching Rules

- Default matching scope is `options`.
- Under `options`, only local option lines count, plus shared options inherited from a shared-options block.
- Use `stem_and_options` when both question head and options should participate.
- Use `full_block` when the whole question block, including shared stems, should participate.
- Shared-stem and shared-option expansion are both enabled by default; a direct match inside a group pulls in the whole group.

## Output Rules

- Output is answer-first: normalize question heads to `A 14.` style.
- Do not copy chapter or section headings.
- Keep each shared-stem or shared-option block only once.
- For shared-option groups, if a question repeats the same options locally, suppress the duplicate local copy in output.
- Refuse to overwrite by default; pass `--allow-overwrite` only when the user explicitly wants replacement.

## Script

Run [`scripts/filter_question_bank.py`](./scripts/filter_question_bank.py) for all deterministic work.

Example: drug-related selection

```powershell
python "C:\Users\23642\.codex\skills\question-bank-docx\scripts\filter_question_bank.py" `
  --source "<source.docx>" `
  --output "<drug-output.docx>" `
  --title "Drug-Related Questions (Answer First)" `
  --preset drug `
  --match-scope options `
  --expected-questions 1704 `
  --expected-groups 90 `
  --expected-stem-groups 36 `
  --expected-option-groups 54 `
  --expected-direct 143 `
  --expected-selected 163
```

Example: imaging-related selection

```powershell
python "C:\Users\23642\.codex\skills\question-bank-docx\scripts\filter_question_bank.py" `
  --source "<source.docx>" `
  --output "<imaging-output.docx>" `
  --title "Imaging-Related Questions (Answer First)" `
  --preset imaging `
  --match-scope options `
  --expected-questions 1704 `
  --expected-groups 90 `
  --expected-stem-groups 36 `
  --expected-option-groups 54 `
  --expected-direct 109 `
  --expected-selected 125
```

Example: preview custom rules without writing output

```powershell
python "C:\Users\23642\.codex\skills\question-bank-docx\scripts\filter_question_bank.py" `
  --source "<source.docx>" `
  --summary-only `
  --match-scope options `
  --literal "abdomen CT" `
  --literal "MRI" `
  --regex "(?<![A-Za-z])PET-CT(?![A-Za-z])"
```

## Validation

- Prefer a dry run first and read the printed counts.
- When recreating a known document, pass the `--expected-*` assertions so the script fails fast on parser drift.
- After writing, spot-check:
  - the title
  - question count
  - one shared-stem block
  - one shared-options block
  - one known false-positive risk, such as `ACTH` when using the `imaging` preset

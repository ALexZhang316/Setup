---
name: document-ocr-workflow
description: Faithfully extract, OCR, transcribe, merge, format, and verify text from documents and images. Use when the user asks to 识别图片, 识别截图, 识别扫描件, 提取文字, 转写, 图片转 Word, image OCR, screenshot OCR, photo OCR, scanned or hybrid PDF OCR, PDF-to-DOCX recovery, DOCX cleanup and assembly, matching questions or records to answers, preserving shared content blocks, applying Word reference formatting, or validating final document deliverables.
---

# Document OCR Workflow

Build the content model first, apply formatting second, and verify structure and rendering separately. Use the existing PDF and Documents skills for their native operations; use this skill to coordinate OCR from PDFs or image files, format donation, content alignment, and failure recovery.

## Resolve Tools

1. Load the bundled workspace dependencies and use their Python, Node.js, Node packages, and native binaries.
2. Never hard-code a runtime bundle version. Managed plugin/cache versions change.
3. Verify that wrapper commands actually execute. If a bundled `.cmd` wrapper is stale, resolve the underlying executable from the loaded runtime instead of assuming the wrapper is authoritative.
4. Work in a task-specific system temp directory. Keep source files read-only and keep OCR models, page images, render files, and caches out of the project.
5. Deliver only requested artifacts. Do not add a PDF beside a DOCX unless the user requested a PDF. Keep any PDF generated for internal DOCX rendering in temp and delete it after QA.

## Inventory Before Processing

1. List inputs, sizes, extensions, ordering, locks, and expected outputs.
2. Run `scripts/pdf_inspect.py` for each PDF before selecting extraction or OCR.
3. For standalone image inputs, record dimensions, file format, EXIF orientation, visual legibility, ordering, and whether the image is a full page, crop, figure, table, handwritten note, or mixed source.
4. Inspect DOCX page settings, headers, footers, styles, representative paragraphs, tables, drawings, formulas, comments, and fields before editing.
5. Record explicit restrictions such as text-only output, no page numbers, no images, no explanations, or exact source order.
6. Establish a page-level, image-level, or block-level manifest before transforming content.

## Route PDF Pages

Classify each page independently:

- **Text page:** extract with `pdfplumber` or `pypdf`; preserve reading order and verify tables or columns visually.
- **Scan page:** extract the largest embedded raster directly with `scripts/pdf_extract_scan_pages.py`; render only when no usable embedded image exists.
- **Hybrid page:** extract the text layer and inspect the raster so captions, stamps, handwriting, or missing regions are not silently lost.
- **Unknown page:** render and inspect before continuing.

Read [references/scan-ocr.md](references/scan-ocr.md) whenever OCR, handwriting, low-confidence text, formulas, figures, or page-level skip reporting is involved.

## Route Image Inputs

Treat each image as a source page unless the user states it is a crop, figure, or supporting visual:

- Preserve the original image file read-only and apply orientation or preprocessing only to temp copies.
- Keep image provenance explicit: source file, input order, derived page or crop identifier, preprocessing, OCR engine, language, PSM, confidence, and uncertainty.
- Use OCR directly for text-bearing images. Stage images in a temp directory and run `scripts/ocr_pages_tesseractjs.mjs` with `--input-dir`, or create a manifest with one record per image when filenames alone are not enough provenance.
- Inspect non-text regions, handwriting, stamps, figures, tables, and captions visually before deciding whether to transcribe, mark uncertain, or skip.
- Do not infer missing surrounding document text from a cropped image. Use an uncertainty marker or ask only if the missing context blocks the requested output.

## Preserve Source Wording

1. Treat extraction and OCR as transcription, not editing. Preserve original wording, abbreviations, word order, numeric values, units, and domain notation.
2. Only make lossless cleanup that is visibly supported by the source: encoding repair, whitespace, line breaks, punctuation shape, option labels, and obvious OCR substitutions.
3. Never replace source text with synonyms, expansions, summaries, or domain explanations unless the user explicitly requested translation, rewriting, or terminology standardization. Keep `COPD` as `COPD`, not `慢性阻塞性肺疾病`; keep `患者发热温度升至39°`, not `患者体温39°`.
4. Keep `source_text` or `transcribed_text` separate from `normalized_key`. Use normalized text only for matching, sorting, or duplicate detection, never as the final delivered wording.
5. If the correct reading cannot be proven from the source image or text layer, preserve the best reading and add an uncertainty marker instead of rewriting it.

## Build Logical Content

1. Build normalized matching keys for encoding, whitespace, punctuation, option labels, line breaks, and visually proven OCR substitutions. Do not overwrite the transcribed source wording with these keys.
2. Represent records as logical blocks rather than raw lines or paragraph numbers.
3. Preserve provenance: source file, source page or image identifier, original order, OCR confidence, uncertainty, and skipped non-text content.
4. Match paired documents by stable identifiers and normalized matching keys, then review unresolved records. Do not proceed merely because one regular expression produced equal counts.
5. Detect unnumbered records through document structure and content transitions.
6. Keep shared stems, shared options, captions, or other dependent ranges as atomic groups during spacing changes, merging, and randomization.

Read [references/structured-content.md](references/structured-content.md) for question banks, answer alignment, shared ranges, blank-line rules, and group-safe shuffling.

## Apply Reference Formatting

Choose the least invasive mode that meets the request:

1. **Exact donor mode:** clone section, paragraph, and run properties from semantic examples when close visual fidelity is required.
2. **Role-token mode:** measure the donor's margins, fonts, sizes, spacing, indents, tab stops, and emphasis roles, then recreate those values without copying unrelated content.
3. **Visual-reference mode:** preserve only hierarchy and rhythm when the user says the format need not be exact.

Use `scripts/docx_format_tools.py` for exact donor mode. Never assign `paragraph.text` after cloning a formatted paragraph; that destroys run boundaries and direct formatting. Copy only required body formatting, and remove unrelated donor body content, headers, footers, page fields, media, comments, or relationships.

Read [references/format-transplant.md](references/format-transplant.md) before cloning formatting or rebuilding a document from a sample.

## Write Safely

1. Write to a temporary file in the destination directory and atomically replace the final output.
2. If Word holds the destination open, stop after the safe temporary write and ask for the file to be closed. Do not repeatedly overwrite or silently invent duplicate filenames.
3. Preserve source files and unrelated workspace changes.
4. Keep marker text explicit and searchable, for example `【识别存疑：...】` and `【非文本内容已跳过】`.
5. Never infer printed answers or source text from handwriting unless the user explicitly asks for handwritten OCR.

## Verify in Layers

Run structural checks before visual checks:

1. Confirm every source page, source image, or source record produced text, a deliberate empty result, or a documented skip marker.
2. Run `scripts/docx_audit.py` with expectations for text-only output, markers, regex counts, headers, footers, page fields, formulas, or media.
3. Validate record sequence and paired-document correspondence from the logical block model, including unnumbered records and shared groups.
4. Inspect every source image used for OCR and every PDF page image produced during extraction or rendering.
5. Render final PDFs to PNG with Poppler and inspect every page.
6. Render final DOCX files with the Documents skill and inspect every PNG. If LibreOffice is unavailable on Windows, open the DOCX read-only through Word COM, inspect structural metrics, and state that PNG visual QA was unavailable.
7. Treat warnings or stderr as diagnostic evidence, not the verdict. Judge completion from required artifacts, exit status, structural checks, and inspected renders.
8. When OCR or cleanup changed text, spot-check against the source for semantic rewrites, especially abbreviations, medical terms, numeric values, units, and short phrases.
9. Remove temp files after the final checks.

## Failure Playbook

- If a browser or Acrobat workflow cannot upload local files, switch to local extraction/OCR rather than retrying the connector.
- If an OCR engine is absent, prefer bundled tools; otherwise install dependencies and language models only in temp. State any network dependency.
- If OCR confidence is low, run a second page-segmentation mode and compare results against the page image. Do not auto-merge conflicting text.
- If a count disagrees with expectations, inspect unnumbered records, split paragraphs, headers, shared blocks, and OCR omissions before changing the expected count.
- If a DOCX opens but cannot be rendered, do not claim visual validation. Use Word read-only verification as a weaker fallback and report the gap.
- If a merge contains drawings or embedded objects, merge relationships and binary parts deliberately or refuse the unsafe merge.

## Final Report

Report the final artifact path, processed page/image/record counts, skipped non-text locations, unresolved or uncertain locations, applied format mode, and verification methods. If the user did not request rewriting, state that source wording was preserved except for lossless OCR cleanup. Mention any unavailable visual QA explicitly. Do not expose temp renders or OCR caches unless requested.

## Script Index

- `scripts/pdf_inspect.py`: classify PDF pages and inventory text layers and raster objects.
- `scripts/pdf_extract_scan_pages.py`: extract or render page images and write a provenance manifest.
- `scripts/ocr_pages_tesseractjs.mjs`: OCR extracted page images or standalone image inputs with language, confidence, and PSM metadata.
- `scripts/docx_format_tools.py`: importable OOXML-safe formatting and atomic-save helpers.
- `scripts/docx_audit.py`: validate text-only and other structural DOCX requirements.

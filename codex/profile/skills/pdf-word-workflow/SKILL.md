---
name: pdf-word-workflow
description: Process PDF and Word document workflows with text-layer inspection, scanned-page OCR, text normalization, multi-file merging, reference-format transplantation, structured-record alignment, and structural or visual QA. Use for scanned or hybrid PDFs, PDF-to-DOCX recovery, DOCX cleanup and assembly, matching questions or other records to answers, preserving shared content blocks, applying formatting from an example Word file, or validating final PDF/DOCX deliverables.
---

# PDF / Word Workflow

Build the content model first, apply formatting second, and verify structure and rendering separately. Use the existing PDF and Documents skills for their native operations; use this skill to coordinate OCR, format donation, content alignment, and failure recovery.

## Resolve Tools

1. Load the bundled workspace dependencies and use their Python, Node.js, Node packages, and native binaries.
2. Never hard-code a runtime bundle version. Managed plugin/cache versions change.
3. Verify that wrapper commands actually execute. If a bundled `.cmd` wrapper is stale, resolve the underlying executable from the loaded runtime instead of assuming the wrapper is authoritative.
4. Work in a task-specific system temp directory. Keep source files read-only and keep OCR models, page images, render files, and caches out of the project.
5. Deliver only requested artifacts. Do not add a PDF beside a DOCX unless the user requested a PDF. Keep any PDF generated for internal DOCX rendering in temp and delete it after QA.

## Inventory Before Processing

1. List inputs, sizes, extensions, ordering, locks, and expected outputs.
2. Run `scripts/pdf_inspect.py` for each PDF before selecting extraction or OCR.
3. Inspect DOCX page settings, headers, footers, styles, representative paragraphs, tables, drawings, formulas, comments, and fields before editing.
4. Record explicit restrictions such as text-only output, no page numbers, no images, no explanations, or exact source order.
5. Establish a page-level or block-level manifest before transforming content.

## Route PDF Pages

Classify each page independently:

- **Text page:** extract with `pdfplumber` or `pypdf`; preserve reading order and verify tables or columns visually.
- **Scan page:** extract the largest embedded raster directly with `scripts/pdf_extract_scan_pages.py`; render only when no usable embedded image exists.
- **Hybrid page:** extract the text layer and inspect the raster so captions, stamps, handwriting, or missing regions are not silently lost.
- **Unknown page:** render and inspect before continuing.

Read [references/scan-ocr.md](references/scan-ocr.md) whenever OCR, handwriting, low-confidence text, formulas, figures, or page-level skip reporting is involved.

## Build Logical Content

1. Normalize encoding, whitespace, punctuation, option labels, line breaks, and obvious OCR substitutions without changing substantive meaning.
2. Represent records as logical blocks rather than raw lines or paragraph numbers.
3. Preserve provenance: source file, source page, original order, OCR confidence, uncertainty, and skipped non-text content.
4. Match paired documents by stable identifiers and normalized content, then review unresolved records. Do not proceed merely because one regular expression produced equal counts.
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

1. Confirm every source page or source record produced text, a deliberate empty result, or a documented skip marker.
2. Run `scripts/docx_audit.py` with expectations for text-only output, markers, regex counts, headers, footers, page fields, formulas, or media.
3. Validate record sequence and paired-document correspondence from the logical block model, including unnumbered records and shared groups.
4. Render final PDFs to PNG with Poppler and inspect every page.
5. Render final DOCX files with the Documents skill and inspect every PNG. If LibreOffice is unavailable on Windows, open the DOCX read-only through Word COM, inspect structural metrics, and state that PNG visual QA was unavailable.
6. Treat warnings or stderr as diagnostic evidence, not the verdict. Judge completion from required artifacts, exit status, structural checks, and inspected renders.
7. Remove temp files after the final checks.

## Failure Playbook

- If a browser or Acrobat workflow cannot upload local files, switch to local extraction/OCR rather than retrying the connector.
- If an OCR engine is absent, prefer bundled tools; otherwise install dependencies and language models only in temp. State any network dependency.
- If OCR confidence is low, run a second page-segmentation mode and compare results against the page image. Do not auto-merge conflicting text.
- If a count disagrees with expectations, inspect unnumbered records, split paragraphs, headers, shared blocks, and OCR omissions before changing the expected count.
- If a DOCX opens but cannot be rendered, do not claim visual validation. Use Word read-only verification as a weaker fallback and report the gap.
- If a merge contains drawings or embedded objects, merge relationships and binary parts deliberately or refuse the unsafe merge.

## Final Report

Report the final artifact path, processed page/record counts, skipped non-text locations, unresolved or uncertain locations, applied format mode, and verification methods. Mention any unavailable visual QA explicitly. Do not expose temp renders or OCR caches unless requested.

## Script Index

- `scripts/pdf_inspect.py`: classify PDF pages and inventory text layers and raster objects.
- `scripts/pdf_extract_scan_pages.py`: extract or render page images and write a provenance manifest.
- `scripts/ocr_pages_tesseractjs.mjs`: OCR page images with language, confidence, and PSM metadata.
- `scripts/docx_format_tools.py`: importable OOXML-safe formatting and atomic-save helpers.
- `scripts/docx_audit.py`: validate text-only and other structural DOCX requirements.

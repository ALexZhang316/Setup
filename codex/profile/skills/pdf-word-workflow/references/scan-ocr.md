# Scan and OCR Workflow

## Decision Order

1. Inspect the PDF before OCR. Use an existing text layer when it is complete and ordered correctly.
2. For scan pages, extract the embedded page image directly. This usually preserves more detail than rendering the PDF at an arbitrary DPI.
3. Render with Poppler only when the page has no usable embedded raster or contains vector content that must be flattened.
4. Run OCR per page and retain a manifest tying each result to its source file and one-based source page.

## Preprocessing

Apply only transformations that improve OCR without erasing evidence:

- convert to grayscale;
- apply mild autocontrast;
- apply light sharpening;
- deskew only when the measured angle is credible;
- keep the unmodified extracted image available in temp for comparison.

Do not mark scan shadows, paper edges, compression noise, or camera distortion as semantic non-text content.

## Engine Strategy

Prefer an already available local engine. For Tesseract.js:

1. Keep the package and `.traineddata.gz` language files in a runtime or temp directory.
2. Use `chi_sim+eng` for simplified Chinese material containing Latin abbreviations, numbers, and units.
3. Run `PSM.AUTO` first for ordinary pages.
4. Run `PSM.SINGLE_BLOCK` or `PSM.SPARSE_TEXT` on low-confidence or incomplete pages.
5. Compare outputs against the image. Do not select text solely by the higher average confidence.

The OCR script accepts an explicit Tesseract.js module directory and language directory so it does not require a project-local npm install.

On some Chinese Windows hosts, shell pipelines can display valid UTF-8 OCR text as Latin-1/GBK-looking text. Inspect the UTF-8 JSON directly before treating `ÏÂÃæ...` terminal output as an OCR failure. If the JSON itself is affected, the bundled runner applies a conservative reversible GB18030 repair and records `encoding_repaired: true`; still compare repaired text with the page image.

## Reading Order and Cleanup

- Rebuild paragraphs, lists, questions, and options from geometry and labels rather than preserving OCR line breaks blindly.
- Correct obvious character substitutions, broken punctuation, duplicated spaces, and split words.
- Preserve domain-specific notation, units, English abbreviations, and printed numerical values unless the source is clearly a typographical error and the user authorized correction.
- Keep formulas as text when reliable. Otherwise insert a non-text or uncertainty marker at the source position.

## Handwriting and Non-Text

Treat printed text and handwriting as separate evidence channels.

- Do not use a handwritten answer, crossing-out mark, stamp, figure, photograph, or diagram as printed content by default.
- Insert `【非文本内容已跳过】` where meaningful non-text content was omitted.
- Insert `【识别存疑：原识别文本】` when text cannot be resolved reliably.
- Report the source filename and original PDF page for every marker in the final response.

## Page-Level Acceptance

Require every source page to have at least one of:

- extracted text;
- OCR text;
- an explicit empty/skip record with a reason.

Review all low-confidence pages and all pages containing markers. A document-wide confidence average is not sufficient evidence.

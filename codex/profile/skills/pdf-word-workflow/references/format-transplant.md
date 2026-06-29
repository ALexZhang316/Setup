# Reference-Format Transplant

## Select a Mode

- Use **exact donor mode** when the user expects the output to match a supplied Word example closely.
- Use **role-token mode** when the donor supplies typography and spacing but unrelated styles or content should not be copied.
- Use **visual-reference mode** when only hierarchy, density, and general rhythm matter.

## Inspect the Donor

Identify examples by semantic role, not by a hard-coded paragraph index:

- title or heading;
- primary record or question line;
- secondary line or option;
- blank separator;
- shared heading, note, or marker;
- table and caption roles when present.

Record page size, orientation, margins, header/footer distance, paragraph spacing, line spacing, indents, tab stops, borders, fonts, sizes, emphasis, and color.

## Exact Donor Method

1. Load the donor with `python-docx`.
2. Capture representative paragraphs and runs before clearing the body.
3. Keep or copy `sectPr` so page geometry remains valid.
4. Deep-copy the donor paragraph XML, remove content children while retaining `w:pPr`, and insert the paragraph before body `sectPr`.
5. Add each text segment as a separate run and copy the corresponding donor `w:rPr`.
6. Keep structural roles separate. For example, place an answer/number prefix and a stem in different runs when their emphasis differs.
7. Clear unrelated headers, footers, page fields, comments, drawings, and media when the output contract excludes them.

Do not set `paragraph.text` after cloning. It collapses runs and discards direct formatting.

## Role-Token Method

Extract numeric tokens from the donor and recreate named roles in a clean document:

- page geometry;
- body and heading fonts;
- type scale;
- paragraph rhythm;
- list or option indents;
- tab positions;
- emphasis rules.

Use this method when the donor contains unrelated chapters, metadata, macros, relationships, or accumulated direct formatting.

## Safety Rules

- Do not copy the donor body wholesale and then delete visible text; hidden fields, relationships, and metadata may remain.
- Do not append content after `sectPr`; Word requires section properties to remain last in the document body.
- Do not copy image or object XML without copying its relationships and binary parts.
- Use an atomic save. A Word lock should produce a clear close-the-file error rather than partial replacement.
- Re-open the saved DOCX and audit the ZIP package before rendering.

## Verification

Check both structure and appearance:

- expected paragraph/run roles retain their donor formatting;
- page geometry matches the chosen mode;
- no unexpected media, fields, headers, or footers remain;
- long lines wrap without overlap;
- blank separators and dependent blocks follow the content model;
- the latest rendered pages are inspected when rendering is available.

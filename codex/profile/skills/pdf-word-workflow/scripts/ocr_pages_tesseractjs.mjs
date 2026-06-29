#!/usr/bin/env node
import { createRequire } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const require = createRequire(import.meta.url);

function usage() {
  return `Usage:
  node ocr_pages_tesseractjs.mjs --manifest manifest.json --out ocr.json [options]
  node ocr_pages_tesseractjs.mjs --input-dir pages --out ocr.json [options]

Options:
  --lang LANGS          Tesseract languages joined by + (default: eng)
  --lang-dir DIR        Directory containing <lang>.traineddata.gz files
  --cache-dir DIR       Tesseract.js cache directory
  --module-dir DIR      tesseract.js package directory or its node_modules parent
  --psm MODE            auto, single-block, sparse, or numeric PSM (default: auto)
  --min-confidence N    Mark results below this confidence (default: 60)
  --verbose             Print OCR progress to stderr
  --help                Show this help
`;
}

function parseArgs(argv) {
  const args = { lang: 'eng', psm: 'auto', minConfidence: 60, verbose: false };
  for (let i = 0; i < argv.length; i += 1) {
    const value = argv[i];
    if (value === '--help') args.help = true;
    else if (value === '--verbose') args.verbose = true;
    else if (value === '--manifest') args.manifest = argv[++i];
    else if (value === '--input-dir') args.inputDir = argv[++i];
    else if (value === '--out') args.out = argv[++i];
    else if (value === '--lang') args.lang = argv[++i];
    else if (value === '--lang-dir') args.langDir = argv[++i];
    else if (value === '--cache-dir') args.cacheDir = argv[++i];
    else if (value === '--module-dir') args.moduleDir = argv[++i];
    else if (value === '--psm') args.psm = argv[++i];
    else if (value === '--min-confidence') args.minConfidence = Number(argv[++i]);
    else throw new Error(`unknown argument: ${value}`);
  }
  if (args.help) return args;
  if (Boolean(args.manifest) === Boolean(args.inputDir)) {
    throw new Error('provide exactly one of --manifest or --input-dir');
  }
  if (!args.out) throw new Error('--out is required');
  if (!Number.isFinite(args.minConfidence)) throw new Error('--min-confidence must be numeric');
  return args;
}

function packageCandidates(moduleDir) {
  const candidates = [];
  if (moduleDir) {
    const resolved = path.resolve(moduleDir);
    candidates.push(resolved);
    candidates.push(path.join(resolved, 'tesseract.js'));
  }
  if (process.env.NODE_PATH) {
    for (const item of process.env.NODE_PATH.split(path.delimiter)) {
      candidates.push(path.join(item, 'tesseract.js'));
    }
  }
  candidates.push(path.join(process.cwd(), 'node_modules', 'tesseract.js'));
  return [...new Set(candidates)];
}

function loadTesseract(moduleDir) {
  const errors = [];
  for (const candidate of packageCandidates(moduleDir)) {
    try {
      return { module: require(candidate), path: candidate };
    } catch (error) {
      errors.push(`${candidate}: ${error.message}`);
    }
  }
  try {
    return { module: require('tesseract.js'), path: 'tesseract.js' };
  } catch (error) {
    errors.push(`tesseract.js: ${error.message}`);
  }
  throw new Error(`cannot load tesseract.js; pass --module-dir. Tried:\n${errors.join('\n')}`);
}

function naturalCompare(left, right) {
  return left.localeCompare(right, undefined, { numeric: true, sensitivity: 'base' });
}

function imageRecords(args) {
  if (args.manifest) {
    const manifestPath = path.resolve(args.manifest);
    const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
    if (!Array.isArray(manifest.pages)) throw new Error('manifest must contain a pages array');
    return manifest.pages
      .filter((page) => page.status === 'ok' && page.output)
      .map((page) => ({
        image: path.resolve(page.output),
        source_file: page.source_file ?? manifest.source_file ?? null,
        source_page: page.source_page ?? null,
      }));
  }

  const inputDir = path.resolve(args.inputDir);
  const extensions = new Set(['.png', '.jpg', '.jpeg', '.tif', '.tiff', '.bmp', '.webp']);
  return fs.readdirSync(inputDir)
    .filter((name) => extensions.has(path.extname(name).toLowerCase()))
    .sort(naturalCompare)
    .map((name, index) => ({
      image: path.join(inputDir, name),
      source_file: null,
      source_page: index + 1,
    }));
}

function resolvePsm(psm, constants) {
  const aliases = {
    auto: constants.AUTO,
    'single-block': constants.SINGLE_BLOCK,
    sparse: constants.SPARSE_TEXT,
  };
  if (aliases[psm] !== undefined) return aliases[psm];
  if (/^(?:[0-9]|1[0-3])$/.test(psm)) return psm;
  throw new Error(`unsupported PSM: ${psm}`);
}

function cjkCount(text) {
  return (text.match(/[\u3400-\u9fff]/g) ?? []).length;
}

function repairWindowsMojibake(text) {
  const characters = Array.from(text);
  const highLatin = characters.filter((character) => {
    const value = character.charCodeAt(0);
    return value >= 0x80 && value <= 0xff;
  }).length;
  if (highLatin < 8 || highLatin / Math.max(characters.length, 1) < 0.05 || cjkCount(text) >= 3) {
    return { text, repaired: false };
  }
  if (characters.some((character) => character.charCodeAt(0) > 0xff)) {
    return { text, repaired: false };
  }
  try {
    const bytes = Uint8Array.from(characters, (character) => character.charCodeAt(0));
    const decoded = new TextDecoder('gb18030', { fatal: true }).decode(bytes);
    if (cjkCount(decoded) >= cjkCount(text) + 5) {
      return { text: decoded, repaired: true };
    }
  } catch {
    // Keep the original OCR text when conversion is not lossless.
  }
  return { text, repaired: false };
}

async function main() {
  let args;
  try {
    args = parseArgs(process.argv.slice(2));
  } catch (error) {
    console.error(`error: ${error.message}\n\n${usage()}`);
    process.exitCode = 2;
    return;
  }
  if (args.help) {
    process.stdout.write(usage());
    return;
  }

  const records = imageRecords(args);
  if (records.length === 0) throw new Error('no input images found');
  const loaded = loadTesseract(args.moduleDir);
  const Tesseract = loaded.module;
  const psm = resolvePsm(args.psm, Tesseract.PSM);
  const options = {
    logger: args.verbose
      ? (message) => console.error(`${message.status}: ${Math.round((message.progress ?? 0) * 100)}%`)
      : () => {},
  };
  if (args.langDir) options.langPath = path.resolve(args.langDir);
  if (args.cacheDir) {
    options.cachePath = path.resolve(args.cacheDir);
    fs.mkdirSync(options.cachePath, { recursive: true });
  }

  const results = [];
  let worker;
  try {
    worker = await Tesseract.createWorker(args.lang, Tesseract.OEM.LSTM_ONLY, options);
    await worker.setParameters({
      tessedit_pageseg_mode: psm,
      preserve_interword_spaces: '1',
    });
    for (const record of records) {
      const pageResult = { ...record };
      try {
        const result = await worker.recognize(record.image);
        const rawText = (result.data.text ?? '').replace(/\r\n/g, '\n').trim();
        const repairedText = repairWindowsMojibake(rawText);
        const confidence = Number(result.data.confidence ?? 0);
        Object.assign(pageResult, {
          status: 'ok',
          text: repairedText.text,
          confidence,
          low_confidence: confidence < args.minConfidence,
          encoding_repaired: repairedText.repaired,
        });
      } catch (error) {
        Object.assign(pageResult, { status: 'error', error: `${error.name}: ${error.message}` });
      }
      results.push(pageResult);
    }
  } finally {
    if (worker) await worker.terminate();
  }

  const report = {
    schema_version: 1,
    engine: 'tesseract.js',
    module_path: loaded.path,
    languages: args.lang,
    psm,
    minimum_confidence: args.minConfidence,
    pages: results,
  };
  const outputPath = path.resolve(args.out);
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
  console.log(outputPath);
  if (results.some((result) => result.status === 'error')) process.exitCode = 2;
}

main().catch((error) => {
  console.error(`error: ${error.stack ?? error.message}`);
  process.exitCode = 2;
});

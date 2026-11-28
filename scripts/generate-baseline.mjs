#!/usr/bin/env node
// Generate the Code Analyzer baseline (the suppressions in code-analyzer.yml)
// from a violation results JSON. The entry point is pnpm run baseline, which
// scans with suppressions disabled and feeds the results to this script.
// Never feed it post-suppression results (a normal scan or a CI artifact):
// those would always yield 0 violations.
//
// Ratchet protection: if any count would rise above the existing
// code-analyzer.yml, the script stops with an error. Pass --allow-increase
// only when the increase is intended.
import fs from 'node:fs';
import process from 'node:process';

const log = (msg) => process.stderr.write(`${msg}\n`);
const args = process.argv.slice(2);
const allowIncrease = args.includes('--allow-increase');
const jsonPath = args.find((a) => !a.startsWith('--'));
if (!jsonPath) {
  log('usage: node scripts/generate-baseline.mjs <sfca_results.json> [--allow-increase]');
  process.exit(1);
}

const OUT = 'code-analyzer.yml';
// CI fails on every severity, so pin all of them
const GATED_SEVERITY = 5;

const results = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));
const counts = results.violations
  .filter((v) => v.severity <= GATED_SEVERITY)
  .reduce((acc, v) => {
    const file = v.locations[v.primaryLocationIndex].file;
    const rule = `${v.engine}:${v.rule}`;
    const key = `${file}\u0000${rule}`;
    return { ...acc, [key]: (acc[key] ?? 0) + 1 };
  }, {});

// Ratchet protection: compare against the existing baseline and detect increases
if (fs.existsSync(OUT) && !allowIncrease) {
  const current = fs.readFileSync(OUT, 'utf8');
  const existing = {};
  let file = null;
  let rule = null;
  for (const line of current.split('\n')) {
    const f = line.match(/^ {2}['"](.+)['"]:$/);
    const r = line.match(/rule_selector: ['"](.+)['"]/);
    const m = line.match(/max_suppressed_violations: (\d+)/);
    if (f) file = f[1];
    else if (r) rule = r[1];
    else if (m && file && rule) existing[`${file}\u0000${rule}`] = Number(m[1]);
  }
  const increases = Object.entries(counts).filter(([key, n]) => n > (existing[key] ?? 0));
  if (increases.length > 0) {
    log('This regeneration would raise the baseline (possible new violations):');
    for (const [key, n] of increases) {
      const [f, r] = key.split('\u0000');
      log(`  ${r} ${f}: ${existing[key] ?? 0} -> ${n}`);
    }
    log('Re-run with --allow-increase to accept the increase.');
    process.exit(1);
  }
}

const byFile = Object.entries(counts).reduce((acc, [key, n]) => {
  const [file, rule] = key.split('\u0000');
  return { ...acc, [file]: [...(acc[file] ?? []), { rule, n }] };
}, {});

const header = `# Salesforce Code Analyzer config.
# suppressions is the baseline of existing violations: debt to repay, not acceptance.
# - Each cap equals the violation count at generation time. Only violations
#   beyond a cap (= new violations) fail CI
# - When you fix an existing violation, lower the cap in the same PR.
#   Regenerate with scripts/generate-baseline.mjs
suppressions:
`;

const body = Object.keys(byFile)
  .toSorted()
  .map((file) => {
    const rules = byFile[file]
      .toSorted((a, b) => a.rule.localeCompare(b.rule))
      .map(
        ({ rule, n }) =>
          `    - rule_selector: '${rule}'\n      max_suppressed_violations: ${n}\n      reason: 'Baseline of existing violations'`
      )
      .join('\n');
    return `  '${file}':\n${rules}`;
  })
  .join('\n');

fs.writeFileSync(OUT, header + body + '\n');
const total = Object.values(counts).reduce((a, b) => a + b, 0);
log(
  `Generated ${OUT}: ${Object.keys(byFile).length} files / ${Object.keys(counts).length} pairs / ${total} violations`
);

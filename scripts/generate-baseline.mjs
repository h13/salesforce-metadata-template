#!/usr/bin/env node
// Code Analyzer のベースライン (code-analyzer.yml の suppressions) を
// 違反結果 JSON から生成する。入口は pnpm run baseline（抑止を無効化して
// スキャンし、その結果を本スクリプトに渡す）。
// 抑止後の結果（通常スキャンや CI 成果物）を渡すと 0 件になるので使わないこと。
//
// ラチェット保護: 既存の code-analyzer.yml より件数が増える場合はエラーで
// 止まる。増加を承知で取り込むときだけ --allow-increase を付ける。
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
// CI は全 severity で fail するので、全件を固定する
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

// ラチェット保護: 既存ベースラインと比較して、増える変更を検出する
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
    log('ベースラインが増える変更が含まれています（新規違反の疑い）:');
    for (const [key, n] of increases) {
      const [f, r] = key.split('\u0000');
      log(`  ${r} ${f}: ${existing[key] ?? 0} -> ${n}`);
    }
    log('取り込む場合は --allow-increase を付けて再実行してください。');
    process.exit(1);
  }
}

const byFile = Object.entries(counts).reduce((acc, [key, n]) => {
  const [file, rule] = key.split('\u0000');
  return { ...acc, [file]: [...(acc[file] ?? []), { rule, n }] };
}, {});

const header = `# Salesforce Code Analyzer 設定。
# suppressions は既存違反のベースライン。容認ではなく返済対象。
# - 各上限は生成時点の違反数ちょうど。上限を超えた分＝新規違反だけが CI で fail する
# - 違反を修正したら同じ PR で上限を下げる。再生成は scripts/generate-baseline.mjs
suppressions:
`;

const body = Object.keys(byFile)
  .toSorted()
  .map((file) => {
    const rules = byFile[file]
      .toSorted((a, b) => a.rule.localeCompare(b.rule))
      .map(
        ({ rule, n }) =>
          `    - rule_selector: '${rule}'\n      max_suppressed_violations: ${n}\n      reason: '既存違反のベースライン'`
      )
      .join('\n');
    return `  '${file}':\n${rules}`;
  })
  .join('\n');

fs.writeFileSync(OUT, header + body + '\n');
const total = Object.values(counts).reduce((a, b) => a + b, 0);
log(
  `${OUT} を生成: ${Object.keys(byFile).length}ファイル / ${Object.keys(counts).length}組 / ${total}件`
);

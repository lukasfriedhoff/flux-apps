#!/usr/bin/env node
// Renovate postUpgradeTask. Renovate bumps ONLY the release-tag version in a
// Nextcloud fetch_app URL *path* (it can't hash release tarballs). This
// reconciles the rest of each pin so the PR is actually mergeable:
//   - the versioned asset filename  (app-vX.Y.Z.tar.gz)
//   - the desired_version arg (5th positional)
//   - the sha256 (downloads the corrected tarball and hashes it)
// Idempotent: consistent blocks are skipped (no network).
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { get } from 'node:https';

const FILES = ['apps/nextcloud/helm-release.yaml', 'apps/nextcloud/verify-custom-apps.yaml'];

const sha256 = (url, redirects = 5) =>
  new Promise((resolve, reject) => {
    get(url, (res) => {
      if ([301, 302, 303, 307, 308].includes(res.statusCode) && res.headers.location && redirects > 0) {
        res.resume();
        return resolve(sha256(new URL(res.headers.location, url).toString(), redirects - 1));
      }
      if (res.statusCode !== 200) { res.resume(); return reject(new Error(`HTTP ${res.statusCode} for ${url}`)); }
      const h = createHash('sha256');
      res.on('data', (c) => h.update(c));
      res.on('end', () => resolve(h.digest('hex')));
      res.on('error', reject);
    }).on('error', reject);
  });

// fetch_app \ \n name \ \n url \ \n sha256 \ \n required \ \n desired_version
const BLOCK = /(fetch_app\s*\\\s*\n\s*)(\S+)(\s*\\\s*\n\s*)(https:\/\/github\.com\/\S+)(\s*\\\s*\n\s*)([0-9a-f]{64})(\s*\\\s*\n\s*)(\S+)(\s*\\\s*\n\s*)(\S+)/g;

let anyChange = false;
for (const file of FILES) {
  if (!existsSync(file)) continue;
  let text = readFileSync(file, 'utf8');
  const matches = [...text.matchAll(BLOCK)];
  for (const m of matches) {
    const [full, p1, name, p2, url, p3, , p4, required, p5, desired] = m;
    const pathVer = (url.match(/\/releases\/download\/v([0-9][0-9A-Za-z.\-]*)\//) || [])[1];
    if (!pathVer) continue;
    const fixedUrl = url.replace(
      /(\/releases\/download\/v[^/]+\/[A-Za-z0-9_.-]*?-v)[0-9][0-9A-Za-z.\-]*(\.tar\.gz)/,
      `$1${pathVer}$2`,
    );
    if (fixedUrl === url && desired === pathVer) continue; // already consistent
    const newSha = await sha256(fixedUrl);
    text = text.replace(full, p1 + name + p2 + fixedUrl + p3 + newSha + p4 + required + p5 + pathVer);
    anyChange = true;
    console.log(`[renovate-fix] ${name} -> v${pathVer} sha256=${newSha}`);
  }
  if (anyChange) writeFileSync(file, text);
}
if (!anyChange) console.log('[renovate-fix] all Nextcloud app pins already consistent');

#!/usr/bin/env node
// Renovate postUpgradeTask. Renovate bumps ONLY the release-tag version in a
// Nextcloud fetch_app URL *path* (it can't hash release tarballs). This
// reconciles the rest of each pin so the PR is actually mergeable:
//   - the versioned asset filename  (app-vX.Y.Z.tar.gz)
//   - the desired_version arg (5th positional)
//   - the sha256 (downloads the corrected tarball and hashes it)
// Idempotent: consistent blocks are skipped (no network).
// If the rewritten URL 404s (upstream renamed its asset, e.g. nextpod 0.7.13
// went from nextpod-nc.tar.gz to nextpod-0.7.13.tar.gz), the release's asset
// list is looked up and its single app tarball is used instead.
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

const githubJson = (url) =>
  new Promise((resolve, reject) => {
    const headers = { 'User-Agent': 'renovate-fix-nextcloud-app-pins', Accept: 'application/vnd.github+json' };
    if (process.env.GITHUB_COM_TOKEN) headers.Authorization = `Bearer ${process.env.GITHUB_COM_TOKEN}`;
    get(url, { headers }, (res) => {
      let body = '';
      res.on('data', (c) => (body += c));
      res.on('end', () => (res.statusCode === 200 ? resolve(JSON.parse(body)) : reject(new Error(`HTTP ${res.statusCode} for ${url}`))));
      res.on('error', reject);
    }).on('error', reject);
  });

// Pick the app tarball from a release's assets: a .tar.gz (not .sha256/.sig),
// preferring one named after the app when the release ships several.
const releaseAssetUrl = async (url, name) => {
  const [, repo, tag] = url.match(/^https:\/\/github\.com\/([^/]+\/[^/]+)\/releases\/download\/([^/]+)\//);
  const release = await githubJson(`https://api.github.com/repos/${repo}/releases/tags/${tag}`);
  const tarballs = release.assets.filter((a) => a.name.endsWith('.tar.gz'));
  const named = tarballs.filter((a) => a.name.startsWith(name));
  const pick = named.length === 1 ? named[0] : tarballs.length === 1 ? tarballs[0] : null;
  if (!pick) throw new Error(`cannot pick the app tarball for ${name} from ${tag}: ${tarballs.map((a) => a.name).join(', ')}`);
  return pick.browser_download_url;
};

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
    let fixedUrl = url.replace(
      /(\/releases\/download\/v[^/]+\/[A-Za-z0-9_.-]*?-v?)[0-9][0-9A-Za-z.\-]*(\.tar\.gz)/,
      `$1${pathVer}$2`,
    );
    if (fixedUrl === url && desired === pathVer) continue; // already consistent
    let newSha;
    try {
      newSha = await sha256(fixedUrl);
    } catch (err) {
      if (!/HTTP 404/.test(err.message)) throw err;
      fixedUrl = await releaseAssetUrl(fixedUrl, name);
      newSha = await sha256(fixedUrl);
    }
    text = text.replace(full, p1 + name + p2 + fixedUrl + p3 + newSha + p4 + required + p5 + pathVer);
    anyChange = true;
    console.log(`[renovate-fix] ${name} -> v${pathVer} sha256=${newSha}`);
  }
  if (anyChange) writeFileSync(file, text);
}
if (!anyChange) console.log('[renovate-fix] all Nextcloud app pins already consistent');

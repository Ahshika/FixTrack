// Builds public_dist/ from public/ for Firebase Hosting, filling in the Firebase web API key
// from ../config/firebase.json (git-ignored). Runs automatically before `firebase deploy` (see firebase.json).
import { cpSync, readFileSync, writeFileSync, rmSync, readdirSync, statSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const configPath = join(here, '..', 'config', 'firebase.json');
const PLACEHOLDER = '__FIREBASE_API_KEY__';

let key;
try {
  key = JSON.parse(readFileSync(configPath, 'utf8')).FIREBASE_API_KEY;
} catch (err) {
  console.error(`Missing or invalid ${configPath}: copy config/firebase.example.json and add the key.`);
  process.exit(1);
}
if (typeof key !== 'string' || !/^[A-Za-z0-9_-]{20,60}$/.test(key)) {
  console.error('FIREBASE_API_KEY in config/firebase.json is missing or malformed.');
  process.exit(1);
}

const src = join(here, 'public');
const out = join(here, 'public_dist');
rmSync(out, { recursive: true, force: true });
cpSync(src, out, { recursive: true });

function fill(dir) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) fill(p);
    else if (name.endsWith('.html')) {
      const text = readFileSync(p, 'utf8');
      if (text.includes(PLACEHOLDER)) writeFileSync(p, text.replaceAll(PLACEHOLDER, key));
    }
  }
}
fill(out);
console.log(`Hosting files ready in ${out}`);

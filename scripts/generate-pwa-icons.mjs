// Rasterizes public/icons/icon-source*.svg into the PNG files the PWA
// manifest (App\Http\Controllers\PwaManifestController) references. Run
// manually (`npm run generate:pwa-icons`) whenever the source SVGs change —
// not wired into `npm run build`, since branding rarely changes and sharp's
// native binary shouldn't be a build-time dependency for every CI run.
import sharp from 'sharp';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const dir = path.dirname(fileURLToPath(import.meta.url));
const iconsDir = path.join(dir, '..', 'public', 'icons');

const jobs = [
    { source: 'icon-source.svg', out: 'icon-192.png', size: 192 },
    { source: 'icon-source.svg', out: 'icon-512.png', size: 512 },
    { source: 'icon-source-maskable.svg', out: 'icon-512-maskable.png', size: 512 },
];

for (const job of jobs) {
    const svg = readFileSync(path.join(iconsDir, job.source));
    await sharp(svg, { density: 384 })
        .resize(job.size, job.size)
        .png()
        .toFile(path.join(iconsDir, job.out));
    console.log(`wrote ${job.out} (${job.size}x${job.size}) from ${job.source}`);
}

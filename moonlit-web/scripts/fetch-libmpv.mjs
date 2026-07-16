// Fetches Windows playback sidecars into src-tauri/: libmpv-2.dll (+ mpv.lib
// import library generated from mpv.def) and Anime4K GLSL shaders.
// Windows-only artifacts; safe to run on any OS (shaders always fetched,
// DLL steps skipped off-Windows unless FORCE_DLL=1).
import { mkdirSync, writeFileSync, existsSync, renameSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execSync } from 'node:child_process';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const libmpvDir = join(root, 'src-tauri', 'libmpv');
const shadersDir = join(root, 'src-tauri', 'shaders');

function encodePathSegments(path) {
  return path.split('/').map(seg => encodeURIComponent(seg)).join('/');
}

async function download(url, dest) {
  console.log(`↓ ${url}`);
  const res = await fetch(url, { redirect: 'follow' });
  if (!res.ok) throw new Error(`${res.status} ${res.statusText} for ${url}`);
  writeFileSync(dest, Buffer.from(await res.arrayBuffer()));
  console.log(`  → ${dest}`);
}

// ── Anime4K shaders (all platforms; tiny text files) ────────────────────────
const SHADERS = [
  'Restore/Anime4K_Clamp_Highlights.glsl',
  'Restore/Anime4K_Restore_CNN_M.glsl',
  'Upscale+Denoise/Anime4K_Upscale_Denoise_CNN_x2_M.glsl',
];
mkdirSync(shadersDir, { recursive: true });
for (const s of SHADERS) {
  const name = s.split('/').pop();
  const dest = join(shadersDir, name);
  if (existsSync(dest)) { console.log(`✓ ${name} (cached)`); continue; }
  await download(`https://raw.githubusercontent.com/bloc97/Anime4K/master/glsl/${encodePathSegments(s)}`, dest);
}

// ── libmpv DLL + import lib (Windows only) ───────────────────────────────────
if (process.platform !== 'win32' && process.env.FORCE_DLL !== '1') {
  console.log('Non-Windows: skipping libmpv DLL fetch (video playback is Windows-only).');
  process.exit(0);
}
mkdirSync(libmpvDir, { recursive: true });

if (existsSync(join(libmpvDir, 'libmpv-2.dll')) && existsSync(join(libmpvDir, 'mpv.lib'))) {
  console.log('✓ libmpv-2.dll + mpv.lib (cached)');
  process.exit(0);
}

// Resolve mpv-dev asset from shinchiro/mpv-winbuild-cmake (override with MPV_DEV_URL)
let devUrl = process.env.MPV_DEV_URL;
if (!devUrl) {
  const rel = await (await fetch(
    'https://api.github.com/repos/shinchiro/mpv-winbuild-cmake/releases/latest',
    { headers: { 'User-Agent': 'moonlit-desktop-setup' } },
  )).json();
  const asset = (rel.assets ?? []).find(
    (a) => a.name.startsWith('mpv-dev-x86_64-2') && a.name.endsWith('.7z'),
  );
  if (!asset) throw new Error('No mpv-dev-x86_64 asset found in latest release');
  devUrl = asset.browser_download_url;
}
const archive = join(libmpvDir, 'mpv-dev.7z');
await download(devUrl, archive);

// Extract (7z.exe present on GitHub runners and most dev boxes; else install 7-Zip)
execSync(`7z x -y -o"${libmpvDir}" "${archive}" libmpv-2.dll mpv.def`, { stdio: 'inherit' });

// Generate MSVC import library from the .def
// Prefer llvm-dlltool (ships with LLVM on GitHub runners), fall back to VS lib.exe.
const def = join(libmpvDir, 'mpv.def');
const lib = join(libmpvDir, 'mpv.lib');
try {
  execSync(`llvm-dlltool -m i386:x86-64 -d "${def}" -D libmpv-2.dll -l "${lib}"`, { stdio: 'inherit' });
} catch {
  execSync(`lib /def:"${def}" /machine:x64 /out:"${lib}"`, { stdio: 'inherit' });
}
console.log('✓ sidecars ready:', readdirSync(libmpvDir).join(', '));

import { writeFileSync } from 'fs';

const URL = 'https://hvfsntdyowapjxobtyli.supabase.co/functions/v1/home-organizer';

console.log('[fetch-organizer] Fetching live data from edge function…');

try {
  const res = await fetch(URL);
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const json = await res.json();
  writeFileSync('public/home-organizer.json', JSON.stringify(json));
  const count = Array.isArray(json) ? json.length : '?';
  console.log(`[fetch-organizer] Wrote ${count} collections to public/home-organizer.json`);
} catch (e) {
  console.warn(`[fetch-organizer] Failed to fetch (${e.message}) — keeping existing bundled file`);
}

import type { StreamItem } from '@/lib/types';
import { getStreamUrl } from '@/lib/player-utils';

function resolutionScore(text: string): number {
  if (/2160p|4k|uhd/i.test(text)) return 4;
  if (/1080p/i.test(text)) return 3;
  if (/720p/i.test(text)) return 2;
  return 1;
}

function streamText(s: StreamItem): string {
  return [s.name, s.title, s.description, s.behaviorHints?.filename].filter(Boolean).join(' ');
}

export function sortStreamsForDesktop(streams: StreamItem[], prefer4K: boolean): StreamItem[] {
  return streams
    .filter((s) => Boolean(getStreamUrl(s)))
    .map((s) => {
      const res = resolutionScore(streamText(s));
      const score = prefer4K ? res : res === 4 ? 2.5 : res;
      return { s, score };
    })
    .sort((a, b) => b.score - a.score)
    .map(({ s }) => s);
}

export function pickDesktopStream(sorted: StreamItem[], lastUrl: string | null): StreamItem | null {
  if (lastUrl) {
    const match = sorted.find((s) => getStreamUrl(s) === lastUrl);
    if (match) return match;
  }
  return sorted[0] ?? null;
}

const PREF_KEY = 'moonlit.desktop.prefer4k';

export function getPrefer4K(): boolean {
  try { return localStorage.getItem(PREF_KEY) === '1'; } catch { return false; }
}

export function setPrefer4K(v: boolean): void {
  try { localStorage.setItem(PREF_KEY, v ? '1' : '0'); } catch { /* */ }
}

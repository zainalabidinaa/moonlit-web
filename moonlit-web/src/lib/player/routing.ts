import { getStreamingServerUrl } from '@/lib/config';
import { buildRemuxUrl } from '@/lib/streaming-server';
import type { StreamItem } from '@/lib/types';
import type {
  PlaybackAttempt,
  PlaybackMethod,
  PlaybackPlan,
  PlayerAdapterKind,
} from './contracts';
import { sanitizeSourceRequestHeaders } from './media-proxy';

export interface PlaybackEnvironment {
  chromium: boolean;
  mediaSource: boolean;
  nativeHls: boolean;
  hevc: boolean;
  hevc10: boolean;
  av1: boolean;
  ac3: boolean;
  eac3: boolean;
  webCodecs: boolean;
  mediabunny: boolean;
  mpv: boolean;
}

export interface PlaybackPlanOptions {
  serverUrl?: string;
  isLive?: boolean;
  enginePreference?: 'auto' | 'native' | 'mpv';
  requestHeaders?: Record<string, string>;
}

const ARCHIVE = /\.(zip|rar|7z|tar|gz|iso|nfo|exe)(?:$|[\s?#])/i;
const AUDIO_ONLY = /\.(flac|mp3|m4a|aac|ogg|wav)(?:$|[\s?#])|\b(audio[ ._-]?only|soundtrack)\b/i;
const HLS = /\.(m3u8|m3u)(?:$|[?#])|\/hls\/|\/manifest(?:[/?#]|$)|\/playlist(?:[/?#]|$)|\/elfmagic\//i;
const MKV = /\.mkv(?:$|[\s?#])|\bmatroska\b/i;
const MPEG_TS = /\.ts(?:$|[?#&])|\.ts%3f|\.ts&/i;

function text(stream: StreamItem): string {
  return `${stream.url ?? ''} ${stream.name ?? ''} ${stream.title ?? ''} ${stream.description ?? ''} ${stream.behaviorHints?.filename ?? ''}`.toLowerCase();
}

function isChromium(): boolean {
  if (typeof navigator === 'undefined') return false;
  return /Chrome\/|Chromium\/|CriOS\/|EdgA?\//.test(navigator.userAgent) && !/Firefox\//.test(navigator.userAgent);
}

export function detectPlaybackEnvironment(video?: HTMLVideoElement): PlaybackEnvironment {
  const element = video ?? (typeof document !== 'undefined' ? document.createElement('video') : undefined);
  const canPlay = (mime: string) => !!element?.canPlayType(mime);
  const mediaSource = typeof window !== 'undefined' && 'MediaSource' in window;
  return {
    chromium: isChromium(),
    mediaSource,
    nativeHls: canPlay('application/vnd.apple.mpegurl'),
    hevc: canPlay('video/mp4; codecs="hvc1"') || canPlay('video/mp4; codecs="hev1"'),
    hevc10: canPlay('video/mp4; codecs="hvc1.2.4.L153.B0"'),
    av1: canPlay('video/mp4; codecs="av01.0.08M.08"'),
    ac3: canPlay('audio/mp4; codecs="ac-3"'),
    eac3: canPlay('audio/mp4; codecs="ec-3"'),
    webCodecs: typeof VideoDecoder !== 'undefined',
    mediabunny: mediaSource,
    mpv: false,
  };
}

function attempt(
  method: PlaybackMethod,
  adapter: PlayerAdapterKind,
  url: string,
  sourceType: PlaybackAttempt['sourceType'],
  isLive: boolean,
  reason: string,
  requestHeaders?: Record<string, string>,
): PlaybackAttempt {
  return { id: `${method}:${url}`, method, adapter, url, sourceType, isLive, reason, requestHeaders };
}

function plan(
  stream: StreamItem,
  outcome: PlaybackPlan['outcome'],
  label: string,
  detail: string,
  attempts: PlaybackAttempt[] = [],
  externalUrl?: string,
): PlaybackPlan {
  return { stream, outcome, label, detail, attempts, externalUrl };
}

function liveTsCandidate(url: string): boolean {
  if (MPEG_TS.test(url)) return true;
  try {
    return /\/live\/[^/]+\/[^/]+\/\d+$/.test(new URL(url).pathname);
  } catch {
    return false;
  }
}

function codecBlockReason(value: string, env: PlaybackEnvironment): { reason: string; video: boolean; audio: boolean } | null {
  const hevc = /\b(x265|h\.?265|hevc)\b/.test(value);
  const av1 = /\bav1\b/.test(value);
  const dolbyVision = /dolby[. _-]?vision|\bdovi\b|\bdv\b/.test(value);
  const dv5 = /\b(?:dv|dovi)[. _-]?p?0?5\b|profile[. _-]?5/.test(value);
  const dvBase = /\b(?:dv|dovi)[. _-]?p?0?[78]\b|profile[. _-]?[78]|\bhdr10?\b|\bremux\b/.test(value);
  if (dolbyVision && (dv5 || !dvBase)) {
    return { reason: 'Dolby Vision profile 5 can render a black picture in browsers.', video: true, audio: false };
  }
  if (hevc && !(env.hevc || env.hevc10)) {
    return { reason: 'This browser has no HEVC decoder.', video: true, audio: false };
  }
  if (av1 && !env.av1) {
    return { reason: 'This browser has no AV1 decoder.', video: true, audio: false };
  }
  if (/\b(truehd|true-hd|dts(?:-hd|-x|:x)?|atmos)\b/.test(value)) {
    return { reason: 'This audio track is not browser-decodable.', video: false, audio: true };
  }
  if (/(?:\b(?:eac3|e-ac-?3|ddp)\b|\bdd\+)/.test(value) && !env.eac3) {
    return { reason: 'Dolby Digital Plus is unavailable in this browser.', video: false, audio: true };
  }
  if (/\b(ac3|ac-3|dd5\.1)\b/.test(value) && !(env.ac3 || env.eac3)) {
    return { reason: 'Dolby Digital is unavailable in this browser.', video: false, audio: true };
  }
  return null;
}

export function buildPlaybackPlan(
  stream: StreamItem,
  env = detectPlaybackEnvironment(),
  options: PlaybackPlanOptions = {},
): PlaybackPlan {
  const rawUrl = stream.url;
  const value = text(stream);
  const isLive = options.isLive === true;
  const serverUrl = options.serverUrl ?? getStreamingServerUrl();
  const requestHeaders = sanitizeSourceRequestHeaders(stream.behaviorHints?.proxyHeaders?.request);
  const hasRequestHeaders = Object.keys(requestHeaders).length > 0;
  const sourceRequestHeaders = hasRequestHeaders ? requestHeaders : undefined;

  if (!rawUrl) {
    if (stream.externalUrl) return plan(stream, 'external', 'Open externally', 'This source exposes only an external-player URL.', [], stream.externalUrl);
    return plan(stream, 'unsupported', 'Not playable', stream.infoHash || stream.behaviorHints?.notWebReady ? 'This source still needs a resolver.' : 'No playback URL is available.');
  }
  const protectedBrowserUrl = rawUrl;
  const isHls = HLS.test(rawUrl) || stream.behaviorHints?.webPlayableType === 'application/x-mpegurl';
  if (ARCHIVE.test(value)) return plan(stream, 'unsupported', 'Not playable', 'Archive files are not video sources.');
  if (AUDIO_ONLY.test(value)) return plan(stream, 'unsupported', 'Not playable', 'This source has no video track.');
  if (hasRequestHeaders && !isHls) {
    return plan(
      stream,
      'external',
      'Open externally',
      'This protected source requires an authenticated playback session; the insecure URL proxy is disabled.',
      [],
      stream.externalUrl ?? rawUrl,
    );
  }

  const mpvUnavailable = options.enginePreference === 'mpv' && !env.mpv;
  const mpvAttempt = env.mpv && !hasRequestHeaders
    ? attempt('mpv', 'mpv', rawUrl, MKV.test(value) ? 'mkv' : 'video', isLive, 'Desktop MPV')
    : null;
  const preferMpv = options.enginePreference === 'mpv' && !!mpvAttempt;
  const blocked = codecBlockReason(value, env);
  if (blocked) {
    const blockedAttempts: PlaybackAttempt[] = [];
    if (preferMpv && mpvAttempt) blockedAttempts.push(mpvAttempt);
    if (serverUrl && !hasRequestHeaders) {
      const method: PlaybackMethod = 'server-transcode';
      const tier = 'transcode';
      blockedAttempts.push(
        attempt(method, 'html-video', buildRemuxUrl(serverUrl, rawUrl, tier), 'hls', isLive, blocked.reason),
      );
    }
    if (!preferMpv && mpvAttempt) blockedAttempts.push(mpvAttempt);
    if (blockedAttempts.length > 0) {
      return plan(stream, 'play-here', 'Plays here', blocked.reason, blockedAttempts);
    }
    return plan(stream, 'external', 'Open externally', blocked.reason, [], stream.externalUrl ?? rawUrl);
  }

  const attempts: PlaybackAttempt[] = [];
  const detail = mpvUnavailable ? 'MPV unavailable; using a browser adapter.' : 'Direct browser playback.';
  if (preferMpv && mpvAttempt) attempts.push(mpvAttempt);

  if (isLive && liveTsCandidate(rawUrl)) {
    if (env.mediaSource) attempts.push(attempt('mpeg-ts', 'html-video', rawUrl, 'mpeg-ts', true, 'Live MPEG-TS via lazy MSE loader', sourceRequestHeaders));
    if (serverUrl && !hasRequestHeaders) {
      attempts.push(attempt('server-remux', 'html-video', buildRemuxUrl(serverUrl, rawUrl, 'remux'), 'hls', true, 'Configured server live remux'));
    }
  } else if (isHls) {
    if (env.nativeHls && !hasRequestHeaders) attempts.push(attempt('native-hls', 'html-video', rawUrl, 'hls', isLive, 'Native HLS'));
    if (env.mediaSource) attempts.push(attempt('hls-mse', 'html-video', rawUrl, 'hls', isLive, 'HLS.js over Media Source Extensions', sourceRequestHeaders));
    if (serverUrl && !hasRequestHeaders) {
      attempts.push(attempt('server-remux', 'html-video', buildRemuxUrl(serverUrl, rawUrl, 'remux'), 'hls', isLive, 'Server HLS fallback'));
    }
  } else if (MKV.test(value)) {
    if (env.chromium) attempts.push(attempt('chromium-mkv', 'html-video', protectedBrowserUrl, 'mkv', isLive, 'Chromium native Matroska demuxing', sourceRequestHeaders));
    if (env.mediabunny) attempts.push(attempt('mediabunny-remux', 'mediabunny', protectedBrowserUrl, 'mkv', isLive, 'Lossless in-browser remux', sourceRequestHeaders));
    if (serverUrl) attempts.push(attempt('server-remux', 'html-video', buildRemuxUrl(serverUrl, rawUrl, 'remux'), 'hls', isLive, 'Configured server remux'));
    if (env.webCodecs) attempts.push(attempt('webcodecs', 'webcodecs', protectedBrowserUrl, 'mkv', isLive, 'Retained WebCodecs fallback', sourceRequestHeaders));
  } else {
    attempts.push(attempt('native', 'html-video', protectedBrowserUrl, 'video', isLive, 'Native HTML media', sourceRequestHeaders));
    if (serverUrl) {
      attempts.push(attempt('server-remux', 'html-video', buildRemuxUrl(serverUrl, rawUrl, 'remux'), 'hls', isLive, 'Configured server fallback'));
    }
  }

  if (!preferMpv && mpvAttempt) attempts.push(mpvAttempt);

  if (attempts.length === 0) {
    return plan(stream, 'external', 'Open externally', 'No safe browser playback adapter is available.', [], stream.externalUrl ?? rawUrl);
  }

  return plan(stream, 'play-here', 'Plays here', detail, attempts);
}

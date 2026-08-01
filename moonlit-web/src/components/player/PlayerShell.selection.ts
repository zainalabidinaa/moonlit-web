import { getPlayableStreamUrl, sortStreamsForBrowserPlayback } from '@/lib/player-utils';
import { buildPlaybackPlan, type PlaybackEnvironment, type PlaybackPlanOptions } from '@/lib/player/routing';
import type { PlaybackPlan } from '@/lib/player/contracts';
import type { StreamItem } from '@/lib/types';

export interface StreamSelectionOptions extends PlaybackPlanOptions {
  explicitUrl?: string;
  rememberedUrl?: string;
  showOnlyCompatibleFormats?: boolean;
}

export interface StreamPlaybackSelection {
  stream: StreamItem;
  plan: PlaybackPlan;
}

export function selectStreamPlayback(
  streams: StreamItem[],
  environment: PlaybackEnvironment,
  options: StreamSelectionOptions = {},
): StreamPlaybackSelection | null {
  const explicit = options.explicitUrl
    ? streams.find(stream => getPlayableStreamUrl(stream) === options.explicitUrl)
    : undefined;
  const remembered = options.rememberedUrl
    ? streams.find(stream => getPlayableStreamUrl(stream) === options.rememberedUrl)
    : undefined;
  const ranked = sortStreamsForBrowserPlayback(streams);
  const ordered = [explicit, remembered, ...ranked, ...streams]
    .filter((stream): stream is StreamItem => !!stream)
    .filter((stream, index, list) => list.findIndex(candidate => candidate === stream) === index);

  if (explicit) {
    return { stream: explicit, plan: buildPlaybackPlan(explicit, environment, options) };
  }

  let firstExternal: StreamPlaybackSelection | null = null;
  let firstUnsupported: StreamPlaybackSelection | null = null;
  for (const stream of ordered) {
    const plan = buildPlaybackPlan(stream, environment, options);
    const selection = { stream, plan };
    if (plan.outcome === 'play-here') return selection;
    if (plan.outcome === 'external' && !firstExternal) firstExternal = selection;
    if (plan.outcome === 'unsupported' && !firstUnsupported) firstUnsupported = selection;
  }

  return firstExternal ?? (options.showOnlyCompatibleFormats ? null : firstUnsupported);
}

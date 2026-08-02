import type { EPGChannelMeta, EPGNowNext, EPGParseResult, EPGProgram, IPTVChannel } from './models';
import { EMPTY_NOW_NEXT } from './models';

export class EPGIndex {
  readonly byChannel: Record<string, EPGProgram[]>;
  readonly channelMeta: Record<string, EPGChannelMeta>;
  private readonly nameKeyToTvgId: Record<string, string>;

  constructor(programs: EPGProgram[], channelMeta: Record<string, EPGChannelMeta>) {
    const grouped: Record<string, EPGProgram[]> = {};
    for (const program of programs) {
      (grouped[program.channelTvgId] ??= []).push(program);
    }
    for (const key of Object.keys(grouped)) {
      grouped[key].sort((a, b) => a.startMs - b.startMs);
    }
    this.byChannel = grouped;
    this.channelMeta = channelMeta;

    const nameIndex: Record<string, string> = {};
    for (const [id, meta] of Object.entries(channelMeta)) {
      if (meta.displayName) {
        const key = EPGIndex.nameKey(meta.displayName);
        if (key.length >= 3) nameIndex[key] = id;
      }
    }
    this.nameKeyToTvgId = nameIndex;
  }

  static from(result: EPGParseResult): EPGIndex {
    return new EPGIndex(result.programs, result.channelMeta);
  }

  get isEmpty(): boolean {
    return Object.keys(this.byChannel).length === 0;
  }

  programsFor(channel: IPTVChannel, overrides: Record<string, string> = {}): EPGProgram[] | undefined {
    const forced = overrides[channel.id];
    if (forced) {
      const programs = this.byChannel[forced];
      if (programs) return programs;
    }
    if (channel.tvgId) {
      const programs = this.byChannel[channel.tvgId];
      if (programs) return programs;
    }
    const key = EPGIndex.nameKey(channel.name);
    if (key.length >= 3) {
      const tvgId = this.nameKeyToTvgId[key];
      if (tvgId) {
        const programs = this.byChannel[tvgId];
        if (programs) return programs;
      }
    }
    return undefined;
  }

  nowNextFor(
    channel: IPTVChannel,
    at: Date = new Date(),
    overrides: Record<string, string> = {},
  ): EPGNowNext {
    return EPGIndex.findCurrent(this.programsFor(channel, overrides), at.getTime());
  }

  static findCurrent(programs: EPGProgram[] | undefined, nowMs: number): EPGNowNext {
    if (!programs || !programs.length) return EMPTY_NOW_NEXT;
    let lo = 0;
    let hi = programs.length - 1;
    let foundIdx = -1;
    while (lo <= hi) {
      const mid = (lo + hi) >> 1;
      const p = programs[mid];
      if (nowMs < p.startMs) hi = mid - 1;
      else if (nowMs >= p.endMs) lo = mid + 1;
      else { foundIdx = mid; break; }
    }
    if (foundIdx < 0) {
      return { current: null, next: lo < programs.length ? programs[lo] : null };
    }
    return {
      current: programs[foundIdx],
      next: foundIdx + 1 < programs.length ? programs[foundIdx + 1] : null,
    };
  }

  static nameKey(s: string): string {
    return s.toLowerCase().replace(/[^a-z0-9]/g, '');
  }
}

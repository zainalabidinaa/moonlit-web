import { useEffect, useState, useCallback, useRef } from 'react';
import type { PlayerLaunch } from '@/app/PlayerProvider';
import { usePlayer } from '@/app/PlayerProvider';
import { useAuth } from '@/app/AuthProvider';
import { MpvPlayer } from '@/components/player/MpvPlayer';
import SourcePickerPanel from '@/components/player/SourcePickerPanel';
import AudioTrackPanel from '@/components/player/AudioTrackPanel';
import SubtitleTrackPanel from '@/components/player/SubtitleTrackPanel';
import EpisodeInfoPanel from '@/components/player/EpisodeInfoPanel';
import TitleInfoPanel from '@/components/player/TitleInfoPanel';
import { fetchStreamsFromAll, fetchSubtitlesFromAll, type SubtitleItem } from '@/lib/stremio';
import { sortStreamsForDesktop, pickDesktopStream, getPrefer4K } from '@/lib/platform/desktop-selection';
import { getStreamUrl } from '@/lib/player-utils';
import { getLastStream, saveLastStream } from '@/lib/last-stream';
import { mpv, type MpvState, initialMpvState } from '@/lib/platform/mpv';
import type { StreamItem, MetaPreview } from '@/lib/types';

export function PlayerScreen({ launch, onClose }: { launch: PlayerLaunch; onClose: () => void }) {
  const { currentProfile, addons } = useAuth();
  const player = usePlayer();

  const [activeUrl, setActiveUrl] = useState<string>(launch.streamUrl ?? '');
  const [allStreams, setAllStreams] = useState<StreamItem[]>(launch.streams ?? []);
  const [selectedStream, setSelectedStream] = useState<StreamItem | null>(null);
  const [subtitles, setSubtitles] = useState<SubtitleItem[]>(launch.subtitles ?? []);
  const [resolved, setResolved] = useState(false);

  const [sourcePickerOpen, setSourcePickerOpen] = useState(false);
  const [audioPanelOpen, setAudioPanelOpen] = useState(false);
  const [subtitlePanelOpen, setSubtitlePanelOpen] = useState(false);
  const [episodeInfoOpen, setEpisodeInfoOpen] = useState(false);
  const [titleInfoOpen, setTitleInfoOpen] = useState(false);
  const [mpvState, setMpvState] = useState<MpvState>(initialMpvState());
  const [audioDelay, setAudioDelay] = useState(0);

  const streamResolveStarted = useRef(false);

  useEffect(() => {
    if (streamResolveStarted.current) return;
    streamResolveStarted.current = true;
    if (launch.streamUrl) {
      setActiveUrl(launch.streamUrl);
      setSelectedStream({ url: launch.streamUrl, addonName: 'Direct' });
      setResolved(true);
      return;
    }
    (async () => {
      const streams = await fetchStreamsFromAll(launch.type, launch.id, addons);
      const sorted = sortStreamsForDesktop(streams, getPrefer4K());
      const last = getLastStream(`${launch.type}:${launch.id}`);
      const picked = pickDesktopStream(sorted, last?.url ?? null);
      const url = picked ? getStreamUrl(picked) : undefined;
      setAllStreams(sorted);
      if (picked && url) {
        setSelectedStream(picked);
        setActiveUrl(url);
      } else if (sorted[0]) {
        const fallback = getStreamUrl(sorted[0]);
        setSelectedStream(sorted[0]);
        setActiveUrl(fallback ?? '');
      }
      setResolved(true);
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    (async () => {
      const subs = await fetchSubtitlesFromAll(launch.type, launch.id, addons);
      setSubtitles(subs);
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const handleSwitchStream = useCallback((stream: StreamItem) => {
    const url = getStreamUrl(stream);
    if (url) {
      setActiveUrl(url);
      setSelectedStream(stream);
      saveLastStream(`${launch.type}:${launch.id}`, {
        url,
        addonName: stream.addonName,
        streamTitle: stream.title,
      });
    }
  }, [launch.type, launch.id]);

  const handleOpenSources = useCallback(() => {
    setSourcePickerOpen(true);
  }, []);

  const titlePreviewItem: MetaPreview = {
    id: launch.id,
    type: launch.type,
    name: launch.metadata.title,
    poster: launch.metadata.poster,
    background: launch.metadata.background,
    logo: launch.metadata.logo,
  };

  return (
    <div className="fixed inset-0 z-[150] bg-black">
      {activeUrl && selectedStream && resolved && (
        <MpvPlayer
          streamUrl={activeUrl}
          streams={allStreams}
          currentStream={selectedStream}
          title={launch.metadata.title}
          mediaLogo={launch.metadata.logo}
          mediaId={launch.id}
          mediaType={launch.type}
          startPosition={launch.startPosition}
          subtitles={subtitles}
          onSwitchStream={handleSwitchStream}
          onOpenSources={handleOpenSources}
          onBack={onClose}
        />
      )}

      {!activeUrl && resolved && (
        <div className="absolute inset-0 z-30 flex flex-col items-center justify-center gap-4 bg-black">
          <div className="text-white text-lg font-bold">No stream available</div>
          <div className="text-white/60 text-sm">Could not find a playable stream.</div>
          <button type="button" onClick={onClose} className="rounded-full bg-white/10 px-5 py-2 text-[13px] font-bold text-white">Back</button>
        </div>
      )}

      {sourcePickerOpen && (
        <SourcePickerPanel
          streams={allStreams}
          selected={selectedStream}
          onSelect={(s) => { handleSwitchStream(s); setSourcePickerOpen(false); }}
          onClose={() => setSourcePickerOpen(false)}
          mode="manual"
        />
      )}

      {audioPanelOpen && (
        <AudioTrackPanel
          state={mpvState}
          onClose={() => setAudioPanelOpen(false)}
          onSelectTrack={(id) => { mpv.setProp('aid', id); }}
          onAudioDelay={setAudioDelay}
          audioDelay={audioDelay}
        />
      )}

      {subtitlePanelOpen && (
        <SubtitleTrackPanel
          state={mpvState}
          externalSubtitles={subtitles}
          onSelectExternal={(s) => { mpv.subAdd(s.url, { title: s.name, lang: s.lang, select: true }); }}
          onDisableExternal={() => { mpv.setProp('sid', false); }}
          onSelectTrack={(id) => { mpv.setProp('sid', id ?? false); }}
          onSubDelay={(d) => { mpv.setProp('sub-delay', d); }}
          onClose={() => setSubtitlePanelOpen(false)}
        />
      )}

      {episodeInfoOpen && (
        <EpisodeInfoPanel
          episode={{
            id: launch.id,
            title: launch.metadata.title,
          }}
          onClose={() => setEpisodeInfoOpen(false)}
        />
      )}

      {titleInfoOpen && (
        <TitleInfoPanel
          item={titlePreviewItem}
          onClose={() => setTitleInfoOpen(false)}
          onOpenDetail={() => { onClose(); }}
        />
      )}
    </div>
  );
}

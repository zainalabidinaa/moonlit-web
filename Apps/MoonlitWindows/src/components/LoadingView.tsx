import { useMemo } from 'react';
import StrokeSpinner from './StrokeSpinner';

const CAPTIONS = [
  'Buttering the popcorn…',
  'Dimming the lights…',
  'Finding your seat in the dark…',
  'Rolling the opening credits…',
  "Skipping the trailers, unlike the cinema…",
  'Untangling the film reel…',
  'Warming up the projector bulb…',
  'Convincing a server to cooperate…',
  'Negotiating with the streaming gods…',
  'Checking under the couch cushions for a working link…',
  'Politely asking the internet for bandwidth…',
  'Locating the last known copy on Earth…',
  'Consulting the Rotten Tomatoes oracle…',
  'Judging your watch history silently…',
  "Pretending to know what you'll like…",
  "Curating something you'll pretend you didn't cry at…",
  'Cross-referencing your taste with your dignity…',
  "Reading the fine print nobody reads…",
  "Double-checking the ending hasn't changed…",
  'Counting how many times this got nominated and lost…',
  'Confirming this is not, in fact, a rerun…',
  'Untangling a few plot holes…',
  'Waking the algorithm from its nap…',
  'Polishing pixels one by one…',
  'Buffering, but make it cinematic…',
];

export default function LoadingView() {
  const caption = useMemo(
    () => CAPTIONS[Math.floor(Math.random() * CAPTIONS.length)],
    []
  );

  return (
    <div className="flex items-center justify-center" style={{ minHeight: '60vh' }}>
      <div className="flex flex-col items-center gap-4">
        <StrokeSpinner size={28} />
        <span className="text-[13px] font-semibold text-white/60">{caption}</span>
      </div>
    </div>
  );
}

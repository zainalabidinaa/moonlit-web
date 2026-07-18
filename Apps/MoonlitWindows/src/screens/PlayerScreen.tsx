import type { PlayerLaunch } from '@/app/PlayerProvider';

export function PlayerScreen({ launch, onClose }: { launch: PlayerLaunch; onClose: () => void }) {
  return (
    <div className="fixed inset-0 z-50 bg-black flex items-center justify-center">
      <div className="text-white/50 text-center">
        <div className="text-lg mb-2">{launch.metadata.title}</div>
        <button onClick={onClose} className="text-white/50 hover:text-white mt-4">Close Player</button>
      </div>
    </div>
  );
}

import { useCallback, useEffect, useState } from 'react';
import { createPortal } from 'react-dom';

import { useAuth } from '@/app/AuthProvider';
import { usePlayer } from '@/app/PlayerProvider';
import { PlayerShell } from '@/components/player/PlayerShell';

export function PlayerOverlay() {
  const { isOpen, launch, close } = usePlayer();
  const { currentProfile } = useAuth();
  const [desktopLaunchKey, setDesktopLaunchKey] = useState<string | null>(null);
  const launchKey = launch
    ? `${launch.type}:${launch.id}:${launch.streamUrl ?? ''}`
    : 'closed';

  useEffect(() => {
    if (!isOpen) return;
    const handler = (event: KeyboardEvent) => {
      if (event.key !== 'Escape' || event.defaultPrevented || document.fullscreenElement) return;
      close();
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [close, isOpen]);

  useEffect(() => {
    const root = document.getElementById('root');
    if (!root) return;
    if (isOpen) root.setAttribute('inert', '');
    else root.removeAttribute('inert');
    return () => root.removeAttribute('inert');
  }, [isOpen]);

  const handleBack = useCallback(() => close(), [close]);
  const handleReady = useCallback(() => undefined, []);
  const handleError = useCallback(() => undefined, []);
  const handleDesktop = useCallback(() => setDesktopLaunchKey(launchKey), [launchKey]);

  if (!isOpen || !launch) return null;

  return createPortal(
    <div
      role="dialog"
      aria-label={`${launch.metadata.title} player`}
      aria-modal="true"
      className={`fixed inset-0 z-[100] ${desktopLaunchKey === launchKey ? 'bg-transparent' : 'bg-black'}`}
    >
      <PlayerShell
        key={launchKey}
        launch={launch}
        onBack={handleBack}
        onVideoReady={handleReady}
        onError={handleError}
        onDesktop={handleDesktop}
        profileId={currentProfile?.id}
      />
    </div>,
    document.body,
  );
}

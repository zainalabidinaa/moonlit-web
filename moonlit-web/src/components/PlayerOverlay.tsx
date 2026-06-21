import { useEffect, useState, useRef, useCallback } from 'react';
import { createPortal } from 'react-dom';
import { usePlayer } from '@/app/PlayerProvider';
import { PlayerShell } from '@/components/player/PlayerShell';
import { LoadingCard } from '@/components/player/LoadingCard';
import { useAuth } from '@/app/AuthProvider';

export function PlayerOverlay() {
  const { isOpen, launch, close } = usePlayer();
  const { currentProfile } = useAuth();

  const [phase, setPhase] = useState<'enter' | 'visible' | 'exit'>('enter');
  const [showLoading, setShowLoading] = useState(true);
  const overlayRef = useRef<HTMLDivElement>(null);

  // Handle open/close animations
  useEffect(() => {
    if (isOpen) {
      setPhase('enter');
      setShowLoading(true);
      requestAnimationFrame(() => {
        requestAnimationFrame(() => setPhase('visible'));
      });
    } else {
      setPhase('exit');
    }
  }, [isOpen]);

  // Keyboard shortcut to close
  useEffect(() => {
    if (!isOpen) return;
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && !document.fullscreenElement) {
        close();
      }
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [isOpen, close]);

  // Set inert on #root when overlay is open
  useEffect(() => {
    const root = document.getElementById('root');
    if (!root) return;
    if (isOpen) {
      root.setAttribute('inert', '');
    } else {
      root.removeAttribute('inert');
    }
    return () => root.removeAttribute('inert');
  }, [isOpen]);

  const handleBack = useCallback(() => {
    close();
  }, [close]);

  const handleLoadCardMinElapsed = useCallback(() => {
    // min visible window elapsed
  }, []);

  const handleVideoReady = useCallback(() => {
    setShowLoading(false);
  }, []);

  const handleError = useCallback(() => {
    setShowLoading(false);
  }, []);

  if (!isOpen && phase === 'exit') return null;
  if (!launch) return null;

  const overlay = (
    <div
      ref={overlayRef}
      className="fixed inset-0 z-[100] bg-black"
      style={{
        transform: phase === 'visible' || phase === 'exit'
          ? 'translateY(0)'
          : 'translateY(100%)',
        opacity: phase === 'visible' || phase === 'exit' ? 1 : 0,
        transition: phase === 'exit'
          ? 'transform 0.2s ease-in, opacity 0.2s ease-in'
          : 'transform 0.3s ease-out, opacity 0.3s ease-out',
      }}
      onTransitionEnd={() => {
        if (phase === 'exit') close();
      }}
    >
      {/* Branded loading card — shown while video initializes */}
      {showLoading && (
        <LoadingCard
          background={launch.metadata.background}
          poster={launch.metadata.poster}
          logo={launch.metadata.logo}
          title={launch.metadata.title}
          minVisibleMs={800}
          onMinElapsed={handleLoadCardMinElapsed}
        />
      )}

      {/* Player shell — stream resolution + Vidstack */}
      <PlayerShell
        launch={launch}
        onBack={handleBack}
        onVideoReady={handleVideoReady}
        onError={handleError}
        profileId={currentProfile?.id}
      />
    </div>
  );

  return createPortal(overlay, document.body);
}

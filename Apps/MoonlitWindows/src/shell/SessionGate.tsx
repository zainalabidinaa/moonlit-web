import { useState, useEffect } from 'react';
import { AnimatePresence, motion } from 'framer-motion';
import { useAuth } from '@/app/AuthProvider';
import { OnboardingScreen } from '@/screens/OnboardingScreen';
import { AuthScreen } from '@/screens/AuthScreen';
import { ProfilePickerScreen } from '@/screens/ProfilePickerScreen';
import { Shell } from './Shell';

const CAPTIONS = [
  'Loading your library...',
  'Preparing the screen...',
  'Getting things ready...',
  'Almost there...',
];

function LoadingView() {
  const caption = CAPTIONS[Math.floor(Math.random() * CAPTIONS.length)];
  return (
    <div className="min-h-screen bg-moonlit-bg flex flex-col items-center justify-center gap-6">
      <div className="w-8 h-8 border-2 border-white/20 border-t-white rounded-full animate-spin-arc" />
      <p className="text-sm text-white/40">{caption}</p>
    </div>
  );
}

function SplashView() {
  return (
    <div className="min-h-screen bg-moonlit-bg flex flex-col items-center justify-center gap-8">
      <div className="font-brand text-[42px] tracking-[2px] animate-breathing-wordmark text-white">
        M O O N L I T
      </div>
      <div className="w-6 h-6 border-2 border-white/20 border-t-white rounded-full animate-spin-arc" />
    </div>
  );
}

export function SessionGate() {
  const { user, currentProfile, profiles, isLoading, guestMode, enterGuestMode } = useAuth();
  const [hasRestoredSession, setHasRestoredSession] = useState(false);
  const [hasSeenOnboarding, setHasSeenOnboarding] = useState(() => {
    try { return localStorage.getItem('moonlit.hasSeenOnboarding') === '1'; }
    catch { return false; }
  });

  useEffect(() => {
    if (isLoading) return;
    const t = setTimeout(() => setHasRestoredSession(true), 1500);
    return () => clearTimeout(t);
  }, [isLoading]);

  function handleOnboardingFinish() {
    localStorage.setItem('moonlit.hasSeenOnboarding', '1');
    setHasSeenOnboarding(true);
  }

  function handleOnboardingSkip() {
    enterGuestMode();
    localStorage.setItem('moonlit.hasSeenOnboarding', '1');
    setHasSeenOnboarding(true);
  }

  if (isLoading || !hasRestoredSession) {
    if (isLoading) return <LoadingView />;
    return (
      <AnimatePresence>
        <SplashView />
      </AnimatePresence>
    );
  }

  if (!hasSeenOnboarding) {
    return (
      <OnboardingScreen
        onFinish={handleOnboardingFinish}
        onSkip={handleOnboardingSkip}
      />
    );
  }

  if (guestMode) return <Shell />;

  if (!user) return <AuthScreen />;

  if (!currentProfile) return <ProfilePickerScreen />;

  return <Shell />;
}

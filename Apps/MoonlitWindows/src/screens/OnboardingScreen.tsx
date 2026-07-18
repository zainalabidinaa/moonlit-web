import { useState } from 'react';

interface OnboardingScreenProps {
  onFinish: () => void;
  onSkip: () => void;
}

export function OnboardingScreen({ onFinish, onSkip }: OnboardingScreenProps) {
  const [page, setPage] = useState(0);

  return (
    <div className="min-h-screen bg-moonlit-bg flex flex-col items-center justify-center relative">
      <div className="flex-1 flex flex-col items-center justify-center w-full">
        {page === 0 && (
          <div className="flex flex-col items-center gap-5 px-10">
            <div className="w-24 h-24 rounded-[24px] bg-white/10 shadow-lg" />
            <div className="font-brand text-[36px] font-semibold text-white">Moonlit</div>
            <p className="text-sm text-white/60 text-center max-w-xs">
              A quieter place for the films and shows you care about.
            </p>
          </div>
        )}

        {page === 1 && (
          <div className="flex flex-col items-center gap-5 px-10">
            <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
              <rect x="3" y="3" width="7" height="7" rx="1" />
              <rect x="14" y="3" width="7" height="7" rx="1" />
              <rect x="3" y="14" width="7" height="7" rx="1" />
              <rect x="14" y="14" width="7" height="7" rx="1" />
            </svg>
            <div className="text-[28px] font-semibold text-white">Collections, not chores</div>
            <p className="text-sm text-white/55 text-center max-w-xs leading-relaxed">
              Name shelves around how you actually watch: movie nights, comfort rewatches, prestige series.
            </p>
          </div>
        )}

        {page === 2 && (
          <div className="flex flex-col items-center gap-5 px-10">
            <div className="w-20 h-20 rounded-[20px] bg-white/10 shadow-lg" />
            <div className="text-[28px] font-semibold text-white text-center">Sign in when you&apos;re ready</div>
            <p className="text-sm text-white/55 text-center max-w-xs leading-relaxed">
              Use your Moonlit account to sync profiles and collections. You can skip this on first launch.
            </p>
            <div className="flex flex-col gap-3 mt-4 w-full max-w-[320px]">
              <button
                onClick={onFinish}
                className="btn-primary w-full"
              >
                Sign in with email
              </button>
              <button
                onClick={onSkip}
                className="btn-secondary w-full"
              >
                Skip for now
              </button>
            </div>
          </div>
        )}
      </div>

      <div className="flex items-center justify-between w-full px-7 pb-12 pt-4">
        <div className="w-[72px]">
          {page < 2 && (
            <button
              onClick={onSkip}
              className="text-sm font-medium text-white/55 hover:text-white/80"
            >
              Skip
            </button>
          )}
        </div>

        <div className="flex items-center gap-[7px]">
          {[0, 1, 2].map(i => (
            <div
              key={i}
              className="rounded-full transition-all duration-[260ms]"
              style={{
                width: i === page ? 22 : 7,
                height: 7,
                backgroundColor: i === page ? 'white' : 'rgba(255,255,255,0.24)',
              }}
            />
          ))}
        </div>

        <div className="w-[72px] flex justify-end">
          {page < 2 ? (
            <button
              onClick={() => setPage(p => p + 1)}
              className="btn-primary text-sm px-5 py-2"
            >
              {page === 0 ? 'Get Started' : 'Next'}
            </button>
          ) : null}
        </div>
      </div>
    </div>
  );
}

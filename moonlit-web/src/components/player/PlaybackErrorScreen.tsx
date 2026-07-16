import { useState, useEffect, useRef } from 'react';
import { ChevronDown, ChevronUp } from 'lucide-react';

export interface PlaybackErrorInfo {
  message: string;
  details?: string;
  streamTitle?: string;
  streamAddon?: string;
  sourceType?: string;
  streamUrl?: string;
  retryCount?: number;
  maxRetries?: number;
}

interface PlaybackErrorScreenProps {
  error: PlaybackErrorInfo;
  onBack: () => void;
  onRetry?: () => void;
  onChooseSource?: () => void;
  autoRetrySeconds?: number;
  onAutoRetry?: () => void;
}

export function PlaybackErrorScreen({
  error,
  onBack,
  onRetry,
  onChooseSource,
  autoRetrySeconds = 0,
  onAutoRetry,
}: PlaybackErrorScreenProps) {
  const [showDetails, setShowDetails] = useState(false);
  const [countdown, setCountdown] = useState(autoRetrySeconds);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  useEffect(() => {
    if (autoRetrySeconds <= 0 || !onAutoRetry) return;
    setCountdown(autoRetrySeconds);
    timerRef.current = setInterval(() => {
      setCountdown(prev => {
        if (prev <= 1) {
          onAutoRetry();
          return 0;
        }
        return prev - 1;
      });
    }, 1000);
    return () => {
      if (timerRef.current) clearInterval(timerRef.current);
    };
  }, [autoRetrySeconds, onAutoRetry]);

  const retriesLeft = error.maxRetries != null && error.retryCount != null
    ? error.maxRetries - error.retryCount
    : null;

  const streamLabel = [error.streamTitle, error.streamAddon]
    .filter(Boolean)
    .join(' · ');

  return (
    <div className="absolute inset-0 z-50 flex flex-col items-center justify-center gap-3 bg-black/95 px-6">
      <p className="text-white text-lg font-semibold">Playback Error</p>
      <p className="text-white/50 text-sm text-center max-w-xs">{error.message}</p>

      {streamLabel && (
        <p className="text-white/30 text-xs text-center max-w-xs truncate">
          {streamLabel}
          {error.sourceType ? ` · ${error.sourceType === 'application/x-mpegurl' ? 'HLS' : 'MP4'}` : ''}
        </p>
      )}

      {retriesLeft != null && retriesLeft > 0 && (
        <p className="text-white/25 text-xs">
          {retriesLeft} {retriesLeft === 1 ? 'retry' : 'retries'} remaining
        </p>
      )}

      {/* Actions */}
      <div className="flex gap-3 mt-2">
        {onRetry && (
          <button
            onClick={onRetry}
            className="px-6 py-2.5 bg-white/10 hover:bg-white/15 border border-white/10 text-white rounded-full text-sm transition-colors"
          >
            Retry
          </button>
        )}
        {onChooseSource && (
          <button
            onClick={onChooseSource}
            className="px-6 py-2.5 bg-white hover:bg-white/90 text-black font-semibold rounded-full text-sm transition-colors"
          >
            Choose source
          </button>
        )}
        <button
          onClick={onBack}
          className="px-6 py-2.5 bg-white/10 hover:bg-white/15 border border-white/10 text-white rounded-full text-sm transition-colors"
        >
          Back
        </button>
      </div>

      {/* Auto-retry countdown */}
      {countdown > 0 && onAutoRetry && (
        <p className="text-white/25 text-xs mt-1">
          Auto-retrying in {countdown}s...
        </p>
      )}

      {/* Details expandable */}
      {error.details && (
        <div className="mt-3 w-full max-w-sm">
          <button
            onClick={() => setShowDetails(!showDetails)}
            className="flex items-center gap-1.5 text-white/30 hover:text-white/50 text-xs mx-auto transition-colors"
          >
            Details
            {showDetails ? <ChevronUp size={14} /> : <ChevronDown size={14} />}
          </button>
          {showDetails && (
            <pre className="mt-2 p-3 rounded-xl bg-white/5 border border-white/10 text-white/40 text-xs font-mono whitespace-pre-wrap break-all max-h-32 overflow-y-auto">
              {error.details}
            </pre>
          )}
        </div>
      )}
    </div>
  );
}

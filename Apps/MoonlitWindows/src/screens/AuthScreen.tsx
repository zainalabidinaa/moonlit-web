import { useState } from 'react';
import { useAuth } from '@/app/AuthProvider';
import { supabase } from '@/lib/supabase';
import { isDesktop } from '@/lib/platform';

export function AuthScreen() {
  const { signIn, signUp } = useAuth();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [inviteCode, setInviteCode] = useState('');
  const [isSignUp, setIsSignUp] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!email || !password) return;
    setIsLoading(true);
    setErrorMessage(null);
    try {
      if (isSignUp) {
        if (!inviteCode) { setErrorMessage('Invite code required'); setIsLoading(false); return; }
        await signUp(email, password, inviteCode);
      } else {
        await signIn(email, password);
      }
    } catch (err: any) {
      const msg = err?.message || String(err);
      if (msg.includes('Invalid login') || msg.includes('401')) {
        setErrorMessage('Invalid email or password');
      } else if (msg.length > 100) {
        setErrorMessage('Something went wrong — please try again');
      } else {
        setErrorMessage(msg);
      }
    }
    setIsLoading(false);
  }

  async function handleAppleSignIn() {
    setIsLoading(true);
    setErrorMessage(null);
    try {
      const { error } = await supabase.auth.signInWithOAuth({
        provider: 'apple',
        options: { redirectTo: window.location.origin },
      });
      if (error) throw error;
    } catch (err: any) {
      setErrorMessage(err?.message || 'Apple sign in failed');
      setIsLoading(false);
    }
  }

  return (
    <div className="min-h-screen bg-moonlit-bg flex items-center justify-center p-4">
      <div className="w-full max-w-[320px] flex flex-col items-center gap-6">
        <div className="flex flex-col items-center gap-2">
          <div className="w-20 h-20 rounded-[20px] bg-white/10 shadow-lg" />
          <div className="font-brand text-[32px] font-bold text-white">Moonlit</div>
          <p className="text-[13px] text-white/50">Sign in to your media hub</p>
        </div>

        <form onSubmit={handleSubmit} className="w-full flex flex-col gap-2.5">
          <input
            type="email"
            placeholder="Email"
            value={email}
            onChange={e => setEmail(e.target.value)}
            className="w-full px-3.5 py-2.5 bg-moonlit-surface border border-white/8 rounded-[10px] text-sm text-white placeholder:text-white/30 outline-none"
            autoComplete="email"
          />
          <input
            type="password"
            placeholder="Password"
            value={password}
            onChange={e => setPassword(e.target.value)}
            className="w-full px-3.5 py-2.5 bg-moonlit-surface border border-white/8 rounded-[10px] text-sm text-white placeholder:text-white/30 outline-none"
            autoComplete={isSignUp ? 'new-password' : 'current-password'}
          />
          {isSignUp && (
            <input
              type="text"
              placeholder="Invite Code"
              value={inviteCode}
              onChange={e => setInviteCode(e.target.value)}
              className="w-full px-3.5 py-2.5 bg-moonlit-surface border border-white/8 rounded-[10px] text-sm text-white placeholder:text-white/30 outline-none"
            />
          )}

          {errorMessage && (
            <p className="text-red-400 text-xs text-center">{errorMessage}</p>
          )}

          <button
            type="submit"
            disabled={isLoading || !email || !password}
            className="btn-primary w-full mt-1 disabled:opacity-50"
          >
            {isLoading ? 'Loading...' : isSignUp ? 'Create Account' : 'Sign In'}
          </button>
        </form>

        <div className="flex items-center gap-2.5 w-full">
          <div className="flex-1 h-px bg-white/8" />
          <span className="text-[11px] font-medium text-white/50">or</span>
          <div className="flex-1 h-px bg-white/8" />
        </div>

        {isDesktop() && (
          <button
            onClick={handleAppleSignIn}
            disabled={isLoading}
            className="w-full h-[42px] flex items-center justify-center gap-2 bg-black border border-white/18 rounded-[10px] text-sm font-semibold text-white hover:bg-white/5 disabled:opacity-50"
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
              <path d="M17.1 12.6c0 3.3 2.4 4.9 2.5 5-.1.2-.4 1.3-1.3 2.6-.8 1.2-1.7 2.3-3 2.3s-1.7-.8-3.2-.8-1.9.8-3.1.8-2.3-1.1-3.1-2.4c-1.1-1.6-2-4.2-2-6.6 0-3.9 2.5-5.9 5-6 1.3 0 2.4.9 3.2.9s2.2-1.1 3.7-.9c.6 0 2.4.2 3.5 1.9-.1.1-2.1 1.2-2.1 3.7zM14.7 4.8c.7-.8 1.1-2 1-3.1-1 0-2.1.7-2.8 1.5-.6.7-1.2 1.9-1 3 .6.1 2.2-.1 2.8-1.4z"/>
            </svg>
            Sign in with Apple
          </button>
        )}

        <button
          onClick={() => { setIsSignUp(!isSignUp); setErrorMessage(null); }}
          className="text-[13px] text-white/50 hover:text-white/80"
        >
          {isSignUp ? 'Have an account? Sign In' : 'New to Moonlit? Create Account'}
        </button>
      </div>
    </div>
  );
}

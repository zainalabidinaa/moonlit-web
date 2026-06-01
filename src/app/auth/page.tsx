'use client';

import { useState } from 'react';
import { useAuth } from '../AuthProvider';
import { useRouter } from 'next/navigation';
import { validateInviteCode } from '@/lib/services/api';

const MoonIcon = () => (
  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" className="w-8 h-8 text-luna-accent">
    <path fillRule="evenodd" d="M9.528 1.718a.75.75 0 01.162.819A8.97 8.97 0 009 6a9 9 0 009 9 8.97 8.97 0 003.463-.69.75.75 0 01.981.98 10.503 10.503 0 01-9.694 6.46c-5.799 0-10.5-4.701-10.5-10.5 0-4.368 2.667-8.112 6.46-9.694a.75.75 0 01.818.162z" clipRule="evenodd" />
  </svg>
);

const SpinnerIcon = () => (
  <svg className="animate-spin w-5 h-5" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
    <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
    <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
  </svg>
);

export default function AuthPage() {
  const { signIn, signUp } = useAuth();
  const router = useRouter();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [inviteCode, setInviteCode] = useState('');
  const [isSignUp, setIsSignUp] = useState(false);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError('');
    setLoading(true);
    try {
      if (isSignUp) {
        if (!inviteCode) { setError('Invite code required'); setLoading(false); return; }
        const valid = await validateInviteCode(inviteCode);
        if (!valid) { setError('Invalid or used invite code'); setLoading(false); return; }
        await signUp(email, password, inviteCode.toUpperCase());
      } else {
        await signIn(email, password);
      }
      router.push('/home');
    } catch (err: any) {
      setError(err.message || 'Authentication failed');
    }
    setLoading(false);
  }

  return (
    <div className="relative flex items-center justify-center min-h-screen overflow-hidden">
      {/* Background glow */}
      <div className="absolute inset-0 bg-luna-bg" />
      <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[600px] h-[600px] rounded-full bg-purple-600/10 blur-3xl pointer-events-none" />
      <div className="absolute top-1/3 left-1/3 w-[300px] h-[300px] rounded-full bg-purple-500/5 blur-2xl pointer-events-none" />

      {/* Auth card */}
      <div className="relative w-full max-w-sm mx-4 p-8 glass rounded-3xl shadow-2xl shadow-black/50">
        <div className="text-center mb-8">
          <div className="flex justify-center mb-3">
            <MoonIcon />
          </div>
          <h1 className="text-2xl font-semibold tracking-tight">Luna</h1>
          <p className="text-luna-muted text-sm mt-1.5">
            {isSignUp ? 'Create your account' : 'Sign in to continue'}
          </p>
        </div>

        <form onSubmit={handleSubmit} className="space-y-3">
          <input
            type="email"
            placeholder="Email"
            value={email}
            onChange={e => setEmail(e.target.value)}
            className="w-full px-4 py-3 bg-white/5 border border-white/10 rounded-xl text-white placeholder-luna-muted focus:outline-none focus:border-purple-400/60 focus:bg-white/8 transition-all text-sm"
            required
          />
          <input
            type="password"
            placeholder="Password"
            value={password}
            onChange={e => setPassword(e.target.value)}
            className="w-full px-4 py-3 bg-white/5 border border-white/10 rounded-xl text-white placeholder-luna-muted focus:outline-none focus:border-purple-400/60 focus:bg-white/8 transition-all text-sm"
            required
          />
          {isSignUp && (
            <input
              type="text"
              placeholder="Invite Code"
              value={inviteCode}
              onChange={e => setInviteCode(e.target.value.toUpperCase())}
              className="w-full px-4 py-3 bg-white/5 border border-white/10 rounded-xl text-white placeholder-luna-muted focus:outline-none focus:border-purple-400/60 focus:bg-white/8 transition-all text-sm uppercase tracking-widest"
              maxLength={8}
            />
          )}

          {error && (
            <p className="text-red-400 text-xs bg-red-500/10 border border-red-500/20 rounded-lg px-3 py-2">{error}</p>
          )}

          <button
            type="submit"
            disabled={loading}
            className="w-full py-3 bg-luna-accent hover:bg-purple-400 text-white font-semibold rounded-xl transition-all duration-200 disabled:opacity-50 flex items-center justify-center gap-2 mt-1 cursor-pointer text-sm"
          >
            {loading ? <SpinnerIcon /> : null}
            {loading ? 'Loading...' : isSignUp ? 'Create Account' : 'Sign In'}
          </button>
        </form>

        <p className="text-center mt-6 text-sm text-luna-muted">
          {isSignUp ? 'Already have an account?' : "Don't have an account?"}{' '}
          <button
            onClick={() => { setIsSignUp(!isSignUp); setError(''); }}
            className="text-luna-accent hover:text-purple-300 underline underline-offset-2 transition-colors cursor-pointer"
          >
            {isSignUp ? 'Sign In' : 'Sign Up'}
          </button>
        </p>
      </div>
    </div>
  );
}

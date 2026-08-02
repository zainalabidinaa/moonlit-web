import { useState, useEffect, FormEvent } from 'react';
import { useSearch } from '@tanstack/react-router';
import { supabase, supabaseUrl, supabaseAnonKey } from '@/lib/supabase';

function LoadingSpinner() {
  return (
    <div className="flex items-center justify-center min-h-screen">
      <div className="w-7 h-7 rounded-full border-2 border-white/[0.14] border-t-white animate-spin-arc" />
    </div>
  );
}

export default function ActivatePage() {
  const search = useSearch({ from: '/activate' }) as { code?: string };
  const [code, setCode] = useState(search.code ?? '');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [isSignUp, setIsSignUp] = useState(false);
  const [inviteCode, setInviteCode] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState(false);

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      if (session && code.length >= 6) {
        handleLink(session.access_token, session.refresh_token ?? '');
      }
    });
  }, []);

  async function handleLink(accessToken: string, refreshToken: string) {
    setLoading(true);
    setError('');
    try {
      const res = await fetch(
        `${supabaseUrl}/functions/v1/device-code?action=link`,
        {
          method: 'POST',
          headers: {
            'apikey': supabaseAnonKey,
            'Authorization': `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            code: code.trim(),
            access_token: accessToken,
            refresh_token: refreshToken,
          }),
        },
      );
      const data = await res.json();
      if (data.status === 'linked') {
        setSuccess(true);
      } else if (data.error) {
        setError(data.error);
      } else {
        setError('Could not link device. Check the code and try again.');
      }
    } catch {
      setError('Connection failed. Please try again.');
    }
    setLoading(false);
  }

  async function handleSignIn(e: FormEvent) {
    e.preventDefault();
    setError('');
    setLoading(true);
    try {
      const { data, error: err } = await supabase.auth.signInWithPassword({ email, password });
      if (err) throw err;
      if (data.session) {
        await handleLink(data.session.access_token, data.session.refresh_token ?? '');
      }
    } catch (err: any) {
      setError(err.message || 'Sign in failed');
      setLoading(false);
    }
  }

  async function handleSignUp(e: FormEvent) {
    e.preventDefault();
    setError('');
    setLoading(true);
    try {
      const { data, error: err } = await supabase.auth.signUp({
        email,
        password,
        options: { data: { invite_code: inviteCode } },
      });
      if (err) throw err;
      if (data.session) {
        await handleLink(data.session.access_token, data.session.refresh_token ?? '');
      } else {
        setError('Check your email for confirmation before linking your device.');
        setLoading(false);
      }
    } catch (err: any) {
      setError(err.message || 'Sign up failed');
      setLoading(false);
    }
  }

  if (success) {
    return (
      <div className="flex items-center justify-center min-h-screen bg-[#0a0a0b]">
        <div className="text-center p-8 max-w-sm">
          <div className="w-12 h-12 rounded-full bg-[#FF8A35]/20 flex items-center justify-center mx-auto mb-6">
            <svg className="w-6 h-6 text-[#FF8A35]" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
            </svg>
          </div>
          <h1 className="text-xl font-semibold text-white mb-2">Device Linked!</h1>
          <p className="text-sm text-white/50">Your Apple TV is now signed in. You can close this page.</p>
        </div>
      </div>
    );
  }

  return (
    <div className="flex items-center justify-center min-h-screen bg-[#0a0a0b]">
      <div className="w-full max-w-sm p-8">
        <h1 className="text-2xl font-semibold text-white text-center mb-2">Link your Apple TV</h1>
        <p className="text-sm text-white/40 text-center mb-8">Enter the code shown on your TV, then sign in.</p>

        <div className="mb-6">
          <label className="block text-xs font-medium text-white/40 mb-2" htmlFor="code">
            Device Code
          </label>
          <input
            id="code"
            type="text"
            className="w-full bg-white/[0.06] border border-white/[0.08] rounded-lg px-4 py-3 text-white text-lg font-mono tracking-[0.25em] text-center placeholder-white/20 focus:outline-none focus:border-[#FF8A35]/50"
            placeholder="ABC123"
            maxLength={6}
            value={code}
            onChange={(e) => { setCode(e.target.value.toUpperCase()); setError(''); }}
          />
        </div>

        <form onSubmit={isSignUp ? handleSignUp : handleSignIn}>
          <div className="mb-3">
            <input
              type="email"
              aria-label="Email address"
              className="w-full bg-white/[0.06] border border-white/[0.08] rounded-lg px-4 py-3 text-white text-sm placeholder-white/20 focus:outline-none focus:border-[#FF8A35]/50"
              placeholder="Email"
              value={email}
              onChange={(e) => { setEmail(e.target.value); setError(''); }}
              required
            />
          </div>

          <div className="mb-4">
            <input
              type="password"
              aria-label="Password"
              className="w-full bg-white/[0.06] border border-white/[0.08] rounded-lg px-4 py-3 text-white text-sm placeholder-white/20 focus:outline-none focus:border-[#FF8A35]/50"
              placeholder="Password"
              value={password}
              onChange={(e) => { setPassword(e.target.value); setError(''); }}
              required
            />
          </div>

          {isSignUp && (
            <div className="mb-4">
              <input
                type="text"
                aria-label="Invite code"
                className="w-full bg-white/[0.06] border border-white/[0.08] rounded-lg px-4 py-3 text-white text-sm placeholder-white/20 focus:outline-none focus:border-[#FF8A35]/50"
                placeholder="Invite Code"
                value={inviteCode}
                onChange={(e) => setInviteCode(e.target.value)}
              />
            </div>
          )}

          {error && (
            <p className="text-red-400 text-xs text-center mb-4">{error}</p>
          )}

          <button
            type="submit"
            disabled={loading || code.length < 6}
            className="w-full py-3 rounded-lg bg-[#FF8A35] text-white text-sm font-semibold disabled:opacity-40 hover:bg-[#FF8A35]/90 transition-colors"
          >
            {loading ? 'Linking...' : isSignUp ? 'Sign Up & Link' : 'Sign In & Link'}
          </button>
        </form>

        <p className="text-white/30 text-xs text-center mt-4">
          <button onClick={() => setIsSignUp(!isSignUp)} className="hover:text-white/50 transition-colors">
            {isSignUp ? 'Already have an account? Sign in' : "Don't have an account? Sign up"}
          </button>
        </p>
      </div>
    </div>
  );
}

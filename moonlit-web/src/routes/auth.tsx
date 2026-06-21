import { useState } from 'react';
import { useAuth } from '@/app/AuthProvider';
import { useNavigate } from '@tanstack/react-router';
import { validateInviteCode } from '@/lib/services/api';

export default function AuthPage() {
  const { signIn, signUp, resetPassword, enterGuestMode } = useAuth();
  const navigate = useNavigate();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [inviteCode, setInviteCode] = useState('');
  const [isSignUp, setIsSignUp] = useState(false);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const [_resetEmail, setResetEmail] = useState('');
  const [showReset, setShowReset] = useState(false);
  const [resetLoading, setResetLoading] = useState(false);
  const [resetSent, setResetSent] = useState(false);

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
      navigate({ to: '/home' });
    } catch (err: any) {
      setError(err.message || 'Authentication failed');
    }
    setLoading(false);
  }

  async function handleResetPassword() {
    if (!_resetEmail.trim()) return;
    setResetLoading(true);
    setError('');
    try {
      await resetPassword(_resetEmail.trim());
      setResetSent(true);
    } catch (err: any) {
      setError(err.message || 'Failed to send reset email');
    }
    setResetLoading(false);
  }

  function handleGuestMode() {
    enterGuestMode();
    navigate({ to: '/home' });
  }

  return (
    <div className="relative flex items-center justify-center min-h-screen overflow-hidden select-none">
      {/* Dark gradient background — matches iOS LinearGradient(#101114 → #050506) */}
      <div className="absolute inset-0" style={{ background: 'linear-gradient(180deg, #101114 0%, #050506 100%)' }} />

      {/* Radial orange glow — matches iOS RadialGradient(#FF8A35 at 0.34 → 0.12 → clear) */}
      <div className="absolute top-[23%] left-1/2 -translate-x-1/2 -translate-y-1/2 pointer-events-none"
        style={{
          width: 380,
          height: 380,
          background: 'radial-gradient(circle, rgba(255,138,53,0.34) 0%, rgba(255,138,53,0.12) 40%, transparent 70%)',
        }}
      />

      <div className="relative w-full max-w-sm mx-4 flex flex-col items-center">
        {/* App Icon — matches iOS Image("AppIconPreview") */}
        <div className="relative mb-6">
          <div className="absolute inset-0 rounded-[26px] blur-2xl opacity-40"
            style={{ background: 'radial-gradient(circle, rgba(255,138,53,0.5), transparent)' }} />
          <img
            src="/apple-touch-icon.png"
            alt="Moonlit"
            className="relative w-[104px] h-[104px] rounded-[26px]"
            style={{
              boxShadow: '0 14px 34px rgba(255,138,53,0.34), 0 18px 28px rgba(0,0,0,0.5)',
            }}
          />
        </div>

        {/* Title */}
        <h1 className="text-[40px] font-semibold text-white mb-2 tracking-tight">Moonlit</h1>

        {/* Subtitle */}
        <p className="text-[15px] text-white/55 text-center mb-9 leading-relaxed max-w-[280px]">
          {isSignUp ? 'Create your account to get started.' : 'Sign in to sync profiles and collections.'}
        </p>

        {/* Form */}
        <form onSubmit={handleSubmit} className="w-full space-y-3">
          <input
            type="email"
            placeholder="Email"
            value={email}
            onChange={e => setEmail(e.target.value)}
            className="w-full px-4 py-[15px] bg-white/[0.06] border border-white/10 rounded-2xl text-white placeholder-white/40 text-[16px] focus:outline-none focus:border-orange-400/60 transition-colors"
            required
            autoComplete="email"
          />
          <input
            type="password"
            placeholder="Password"
            value={password}
            onChange={e => setPassword(e.target.value)}
            className="w-full px-4 py-[15px] bg-white/[0.06] border border-white/10 rounded-2xl text-white placeholder-white/40 text-[16px] focus:outline-none focus:border-orange-400/60 transition-colors"
            required
            autoComplete={isSignUp ? 'new-password' : 'current-password'}
          />
          {isSignUp && (
            <input
              type="text"
              placeholder="Invite Code"
              value={inviteCode}
              onChange={e => setInviteCode(e.target.value.toUpperCase())}
              className="w-full px-4 py-[15px] bg-white/[0.06] border border-white/10 rounded-2xl text-white placeholder-white/40 text-[16px] uppercase tracking-widest focus:outline-none focus:border-orange-400/60 transition-colors"
              maxLength={8}
            />
          )}

          {/* Forgot password */}
          {!isSignUp && (
            <div className="flex justify-end pt-1">
              <button
                type="button"
                onClick={() => { setShowReset(!showReset); setResetSent(false); }}
                className="text-[13px] font-medium text-moonlit-accent opacity-80 hover:opacity-100 transition-opacity cursor-pointer"
              >
                Forgot password?
              </button>
            </div>
          )}

          {/* Password reset form */}
          {showReset && !isSignUp && (
            <div className="space-y-3 pt-1">
              <input
                type="email"
                placeholder="Email address"
                value={_resetEmail}
                onChange={e => setResetEmail(e.target.value)}
                className="w-full px-4 py-[13px] bg-white/[0.06] border border-white/10 rounded-2xl text-white placeholder-white/40 text-[15px] focus:outline-none focus:border-orange-400/60 transition-colors"
                autoComplete="email"
              />
              {resetSent && (
                <p className="text-[#4ADE80] text-xs text-center">Check your email for a reset link.</p>
              )}
              <div className="flex gap-3">
                <button
                  type="button"
                  onClick={() => { setShowReset(false); setResetSent(false); }}
                  className="flex-1 py-3 text-[14px] font-medium text-white/50 bg-white/[0.06] rounded-2xl cursor-pointer hover:bg-white/10 transition-colors"
                >
                  Cancel
                </button>
                <button
                  type="button"
                  onClick={handleResetPassword}
                  disabled={!_resetEmail.trim() || resetLoading}
                  className="flex-1 py-3 text-[14px] font-semibold text-black bg-moonlit-accent rounded-2xl cursor-pointer disabled:opacity-50 hover:bg-moonlit-accent-dim transition-colors flex items-center justify-center gap-2"
                >
                  {resetLoading ? (
                    <svg className="animate-spin w-4 h-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                      <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                      <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
                    </svg>
                  ) : null}
                  Send Reset Link
                </button>
              </div>
            </div>
          )}

          {/* Error */}
          {error && (
            <p className="text-[#FF6B6B] text-xs text-center py-1">{error}</p>
          )}
        </form>

        {/* Action buttons */}
        <div className="w-full space-y-3 mt-6">
          <button
            onClick={handleSubmit}
            disabled={loading || !email || !password}
            className="w-full py-[17px] bg-white text-black font-semibold text-[17px] rounded-[18px] cursor-pointer disabled:opacity-50 hover:bg-white/90 transition-colors flex items-center justify-center gap-2"
          >
            {loading ? (
              <svg className="animate-spin w-5 h-5" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
              </svg>
            ) : null}
            {loading ? 'Loading...' : isSignUp ? 'Create Account' : 'Sign In'}
          </button>

          <button
            type="button"
            onClick={handleGuestMode}
            className="w-full py-4 bg-white/[0.045] border border-white/[0.08] text-white/60 font-medium text-[15px] rounded-[18px] cursor-pointer hover:bg-white/[0.06] transition-colors"
          >
            Skip login
          </button>
        </div>

        {/* Toggle Sign In / Sign Up */}
        <p className="text-center mt-5 text-[13px] text-white/40">
          {isSignUp ? 'Already have an account?' : "Don't have an account?"}{' '}
          <button
            onClick={() => { setIsSignUp(!isSignUp); setError(''); setShowReset(false); }}
            className="text-moonlit-accent hover:text-orange-400 underline underline-offset-2 transition-colors cursor-pointer"
          >
            {isSignUp ? 'Sign In' : 'Sign Up'}
          </button>
        </p>
      </div>
    </div>
  );
}

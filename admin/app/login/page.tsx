'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { useAdminAuth } from '../../components/AdminAuthProvider';

export default function LoginPage() {
  const { signIn } = useAdminAuth();
  const router = useRouter();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError('');
    setLoading(true);
    try {
      await signIn(email, password);
      router.push('/dashboard');
    } catch (err: any) {
      setError(err.message || 'Login failed');
    }
    setLoading(false);
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-luna-bg">
      <div className="w-full max-w-sm p-8 bg-luna-surface border border-luna-border rounded-2xl shadow-2xl">
        <div className="text-center mb-8">
          <div className="w-10 h-10 bg-luna-accent rounded-xl mx-auto mb-3 flex items-center justify-center text-xl">🌙</div>
          <h1 className="text-xl font-bold text-white">Luna Admin</h1>
          <p className="text-luna-muted text-sm mt-1">Admin access only</p>
        </div>
        <form onSubmit={handleSubmit} className="space-y-3">
          <input type="email" placeholder="Email" value={email} onChange={e => setEmail(e.target.value)} required className="w-full px-4 py-3 bg-luna-elevated border border-luna-border rounded-xl text-white placeholder-luna-muted focus:outline-none focus:border-luna-accent text-sm" />
          <input type="password" placeholder="Password" value={password} onChange={e => setPassword(e.target.value)} required className="w-full px-4 py-3 bg-luna-elevated border border-luna-border rounded-xl text-white placeholder-luna-muted focus:outline-none focus:border-luna-accent text-sm" />
          {error && <p className="text-red-400 text-xs bg-red-500/10 border border-red-500/20 rounded-lg px-3 py-2">{error}</p>}
          <button type="submit" disabled={loading} className="w-full py-3 bg-luna-accent hover:bg-purple-400 text-white font-semibold rounded-xl transition-all text-sm disabled:opacity-50 cursor-pointer">
            {loading ? 'Signing in...' : 'Sign In'}
          </button>
        </form>
      </div>
    </div>
  );
}

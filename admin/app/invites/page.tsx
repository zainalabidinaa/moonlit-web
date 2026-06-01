'use client';
import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { useAdminAuth } from '../../components/AdminAuthProvider';
import { AdminShell } from '../../components/AdminShell';
import { getInviteCodes, generateInviteCode, revokeInviteCode, InviteCode } from '../../lib/api';

export default function InvitesPage() {
  const { user, isLoading } = useAdminAuth();
  const router = useRouter();
  const [codes, setCodes] = useState<InviteCode[]>([]);
  const [maxUses, setMaxUses] = useState(1);
  const [loading, setLoading] = useState(true);
  const [generating, setGenerating] = useState(false);

  useEffect(() => {
    if (isLoading) return;
    if (!user) { router.replace('/login'); return; }
    getInviteCodes().then(c => { setCodes(c); setLoading(false); });
  }, [isLoading, user]);

  async function handleGenerate() {
    if (!user) return;
    setGenerating(true);
    await generateInviteCode(user.id, maxUses);
    getInviteCodes().then(c => setCodes(c));
    setGenerating(false);
  }

  async function handleRevoke(code: string) {
    await revokeInviteCode(code);
    setCodes(prev => prev.map(c => c.code === code ? { ...c, is_active: false } : c));
  }

  const active = codes.filter(c => c.is_active && !c.used_by).length;

  if (loading) return <AdminShell><div className="flex items-center justify-center h-full"><div className="animate-spin rounded-full h-6 w-6 border-2 border-luna-accent border-t-transparent" /></div></AdminShell>;

  return (
    <AdminShell>
      <div className="p-6">
        <div className="flex items-center justify-between mb-6">
          <div><h1 className="text-xl font-bold text-white">Invite Codes</h1><p className="text-sm text-luna-muted mt-0.5">{active} active · {codes.length} total</p></div>
          <div className="flex items-center gap-2">
            <input type="number" value={maxUses} onChange={e => setMaxUses(Math.max(1, Number(e.target.value)))} min={1} max={100} className="w-16 px-3 py-2 bg-luna-elevated border border-luna-border rounded-xl text-white text-sm focus:outline-none focus:border-luna-accent text-center" />
            <span className="text-xs text-luna-muted">uses</span>
            <button onClick={handleGenerate} disabled={generating} className="px-4 py-2 bg-luna-accent hover:bg-purple-400 text-white text-sm font-semibold rounded-xl transition-all cursor-pointer disabled:opacity-50">
              {generating ? 'Generating...' : '+ Generate'}
            </button>
          </div>
        </div>
        <div className="bg-luna-surface border border-luna-border rounded-xl overflow-hidden">
          <table className="w-full">
            <thead><tr className="border-b border-luna-border">
              <th className="text-left px-5 py-2.5 text-[10px] font-bold uppercase tracking-wider text-luna-muted">Code</th>
              <th className="text-left px-5 py-2.5 text-[10px] font-bold uppercase tracking-wider text-luna-muted">Max Uses</th>
              <th className="text-left px-5 py-2.5 text-[10px] font-bold uppercase tracking-wider text-luna-muted">Used By</th>
              <th className="text-left px-5 py-2.5 text-[10px] font-bold uppercase tracking-wider text-luna-muted">Created</th>
              <th className="text-left px-5 py-2.5 text-[10px] font-bold uppercase tracking-wider text-luna-muted">Status</th>
              <th></th>
            </tr></thead>
            <tbody>
              {codes.map(c => (
                <tr key={c.code} className="border-b border-luna-border/50 hover:bg-luna-elevated/50 transition-colors">
                  <td className="px-5 py-3 font-mono text-sm font-bold text-white tracking-widest">{c.code}</td>
                  <td className="px-5 py-3 text-sm text-luna-muted">{c.max_uses}</td>
                  <td className="px-5 py-3 text-sm text-luna-muted">{c.used_by ? c.used_by.slice(0, 8) + '…' : '—'}</td>
                  <td className="px-5 py-3 text-sm text-luna-muted">{new Date(c.created_at).toLocaleDateString()}</td>
                  <td className="px-5 py-3">
                    {c.is_active && !c.used_by && <span className="text-[10px] font-bold px-2 py-1 rounded-full bg-green-500/10 text-green-400">active</span>}
                    {c.used_by && <span className="text-[10px] font-bold px-2 py-1 rounded-full bg-luna-elevated text-luna-muted">used</span>}
                    {!c.is_active && !c.used_by && <span className="text-[10px] font-bold px-2 py-1 rounded-full bg-red-500/10 text-red-400">revoked</span>}
                  </td>
                  <td className="px-5 py-3">
                    {c.is_active && !c.used_by && <button onClick={() => handleRevoke(c.code)} className="text-xs text-[#444] hover:text-red-400 transition-colors cursor-pointer">Revoke</button>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </AdminShell>
  );
}

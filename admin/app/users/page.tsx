'use client';
import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { useAdminAuth } from '../../components/AdminAuthProvider';
import { AdminShell } from '../../components/AdminShell';
import { getUsers, AdminUser } from '../../lib/api';

export default function UsersPage() {
  const { user, isLoading } = useAdminAuth();
  const router = useRouter();
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [search, setSearch] = useState('');
  const [expanded, setExpanded] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (isLoading) return;
    if (!user) { router.replace('/login'); return; }
    getUsers().then(u => { setUsers(u); setLoading(false); });
  }, [isLoading, user]);

  const filtered = users.filter(u => u.email?.toLowerCase().includes(search.toLowerCase()));

  if (loading) return <AdminShell><div className="flex items-center justify-center h-full"><div className="animate-spin rounded-full h-6 w-6 border-2 border-luna-accent border-t-transparent" /></div></AdminShell>;

  return (
    <AdminShell>
      <div className="p-6">
        <div className="flex items-center justify-between mb-6">
          <div><h1 className="text-xl font-bold text-white">Users</h1><p className="text-sm text-luna-muted mt-0.5">{users.length} total accounts</p></div>
          <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search by email..." className="px-3 py-2 bg-luna-elevated border border-luna-border rounded-xl text-sm text-white placeholder-luna-muted focus:outline-none focus:border-luna-accent w-56" />
        </div>
        <div className="bg-luna-surface border border-luna-border rounded-xl overflow-hidden">
          <table className="w-full">
            <thead><tr className="border-b border-luna-border">
              <th className="text-left px-5 py-2.5 text-[10px] font-bold uppercase tracking-wider text-luna-muted">Email</th>
              <th className="text-left px-5 py-2.5 text-[10px] font-bold uppercase tracking-wider text-luna-muted">Profiles</th>
              <th className="text-left px-5 py-2.5 text-[10px] font-bold uppercase tracking-wider text-luna-muted">Joined</th>
              <th className="text-left px-5 py-2.5 text-[10px] font-bold uppercase tracking-wider text-luna-muted">Role</th>
            </tr></thead>
            <tbody>
              {filtered.map(u => (
                <>
                  <tr key={u.id} onClick={() => setExpanded(expanded === u.id ? null : u.id)} className="border-b border-luna-border/50 hover:bg-luna-elevated/50 transition-colors cursor-pointer">
                    <td className="px-5 py-3 text-sm text-white font-medium">{u.email}</td>
                    <td className="px-5 py-3 text-sm text-luna-muted">{u.profiles.length}</td>
                    <td className="px-5 py-3 text-sm text-luna-muted">{new Date(u.created_at).toLocaleDateString()}</td>
                    <td className="px-5 py-3">
                      {u.profiles.some(p => p.role === 'admin')
                        ? <span className="text-[10px] font-bold px-2 py-1 rounded-full bg-purple-500/20 text-luna-accent">admin</span>
                        : <span className="text-[10px] font-bold px-2 py-1 rounded-full bg-blue-500/10 text-blue-400">user</span>}
                    </td>
                  </tr>
                  {expanded === u.id && u.profiles.length > 0 && (
                    <tr key={`${u.id}-exp`} className="border-b border-luna-border/50 bg-luna-elevated/30">
                      <td colSpan={4} className="px-8 py-3">
                        <p className="text-[10px] font-bold uppercase tracking-wider text-luna-muted mb-2">Profiles</p>
                        <div className="flex gap-2 flex-wrap">
                          {u.profiles.map(p => (
                            <div key={p.id} className="flex items-center gap-2 px-3 py-1.5 bg-luna-surface rounded-lg border border-luna-border">
                              <div className="w-5 h-5 rounded-full flex items-center justify-center text-[10px] font-bold text-white" style={{ background: p.avatar_color || '#c084fc' }}>{p.name[0]}</div>
                              <span className="text-xs text-white">{p.name}</span>
                              <span className="text-[10px] text-luna-muted">{p.role}</span>
                            </div>
                          ))}
                        </div>
                      </td>
                    </tr>
                  )}
                </>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </AdminShell>
  );
}

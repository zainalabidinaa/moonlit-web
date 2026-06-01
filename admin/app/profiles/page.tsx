'use client';
import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { useAdminAuth } from '../../components/AdminAuthProvider';
import { AdminShell } from '../../components/AdminShell';
import { getAllProfiles, deleteProfile, AdminProfile } from '../../lib/api';

export default function ProfilesPage() {
  const { user, isLoading } = useAdminAuth();
  const router = useRouter();
  const [profiles, setProfiles] = useState<AdminProfile[]>([]);
  const [loading, setLoading] = useState(true);
  const [deleting, setDeleting] = useState<string | null>(null);

  useEffect(() => {
    if (isLoading) return;
    if (!user) { router.replace('/login'); return; }
    getAllProfiles().then(p => { setProfiles(p); setLoading(false); });
  }, [isLoading, user]);

  async function handleDelete(profileId: string, name: string) {
    if (!confirm(`Delete profile "${name}"? This cannot be undone.`)) return;
    setDeleting(profileId);
    await deleteProfile(profileId);
    setProfiles(p => p.filter(x => x.id !== profileId));
    setDeleting(null);
  }

  if (loading) return <AdminShell><div className="flex items-center justify-center h-full"><div className="animate-spin rounded-full h-6 w-6 border-2 border-luna-accent border-t-transparent" /></div></AdminShell>;

  return (
    <AdminShell>
      <div className="p-6">
        <div className="mb-6"><h1 className="text-xl font-bold text-white">Profiles</h1><p className="text-sm text-luna-muted mt-0.5">{profiles.length} profiles across all users</p></div>
        <div className="bg-luna-surface border border-luna-border rounded-xl overflow-hidden">
          <table className="w-full">
            <thead><tr className="border-b border-luna-border">
              <th className="text-left px-5 py-2.5 text-[10px] font-bold uppercase tracking-wider text-luna-muted">Name</th>
              <th className="text-left px-5 py-2.5 text-[10px] font-bold uppercase tracking-wider text-luna-muted">Role</th>
              <th className="text-left px-5 py-2.5 text-[10px] font-bold uppercase tracking-wider text-luna-muted">Addons</th>
              <th className="text-left px-5 py-2.5 text-[10px] font-bold uppercase tracking-wider text-luna-muted">Library</th>
              <th className="text-left px-5 py-2.5 text-[10px] font-bold uppercase tracking-wider text-luna-muted">User ID</th>
              <th></th>
            </tr></thead>
            <tbody>
              {profiles.map(p => (
                <tr key={p.id} className="border-b border-luna-border/50 hover:bg-luna-elevated/50 transition-colors">
                  <td className="px-5 py-3">
                    <div className="flex items-center gap-2.5">
                      <div className="w-7 h-7 rounded-full flex items-center justify-center text-xs font-bold text-white flex-shrink-0" style={{ background: p.avatar_color || '#c084fc' }}>{p.name[0]}</div>
                      <span className="text-sm font-medium text-white">{p.name}</span>
                    </div>
                  </td>
                  <td className="px-5 py-3"><span className={`text-[10px] font-bold px-2 py-1 rounded-full ${p.role === 'admin' ? 'bg-purple-500/20 text-luna-accent' : 'bg-blue-500/10 text-blue-400'}`}>{p.role}</span></td>
                  <td className="px-5 py-3 text-sm text-luna-muted">{p.addon_count}</td>
                  <td className="px-5 py-3 text-sm text-luna-muted">{p.library_count}</td>
                  <td className="px-5 py-3 text-xs text-luna-muted font-mono truncate max-w-[120px]">{p.user_id.slice(0, 8)}…</td>
                  <td className="px-5 py-3">
                    <button onClick={() => handleDelete(p.id, p.name)} disabled={deleting === p.id} className="text-xs text-[#444] hover:text-red-400 transition-colors cursor-pointer disabled:opacity-50">
                      {deleting === p.id ? '...' : 'Delete'}
                    </button>
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

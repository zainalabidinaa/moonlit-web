'use client';
import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { useAdminAuth } from '../../components/AdminAuthProvider';
import { AdminShell } from '../../components/AdminShell';
import { getAdminStats, getUsers, AdminStats, AdminUser } from '../../lib/api';

function StatCard({ label, value, color }: { label: string; value: number | string; color?: string }) {
  return (
    <div className="bg-luna-surface border border-luna-border rounded-xl p-5">
      <p className="text-[10px] font-bold uppercase tracking-widest text-luna-muted mb-2">{label}</p>
      <p className={`text-3xl font-extrabold ${color || 'text-white'}`}>{value}</p>
    </div>
  );
}

export default function DashboardPage() {
  const { user, isLoading } = useAdminAuth();
  const router = useRouter();
  const [stats, setStats] = useState<AdminStats | null>(null);
  const [recentUsers, setRecentUsers] = useState<AdminUser[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (isLoading) return;
    if (!user) { router.replace('/login'); return; }
    Promise.all([getAdminStats(), getUsers()]).then(([s, users]) => {
      setStats(s); setRecentUsers(users.slice(0, 10)); setLoading(false);
    });
  }, [isLoading, user]);

  if (loading) return <AdminShell><div className="flex items-center justify-center h-full"><div className="animate-spin rounded-full h-6 w-6 border-2 border-luna-accent border-t-transparent" /></div></AdminShell>;

  return (
    <AdminShell>
      <div className="p-6">
        <div className="mb-6"><h1 className="text-xl font-bold text-white">Dashboard</h1><p className="text-sm text-luna-muted mt-0.5">Luna overview</p></div>
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
          <StatCard label="Total Users" value={stats?.totalUsers || 0} />
          <StatCard label="Profiles" value={stats?.totalProfiles || 0} />
          <StatCard label="Active Invites" value={stats?.activeInvites || 0} color="text-green-400" />
          <StatCard label="Watch Events" value={stats?.watchEvents || 0} />
        </div>
        <div className="bg-luna-surface border border-luna-border rounded-xl overflow-hidden">
          <div className="px-5 py-3 border-b border-luna-border"><h2 className="text-sm font-semibold text-white">Recent Users</h2></div>
          <table className="w-full">
            <thead><tr className="border-b border-luna-border">
              <th className="text-left px-5 py-2.5 text-[10px] font-bold uppercase tracking-wider text-luna-muted">Email</th>
              <th className="text-left px-5 py-2.5 text-[10px] font-bold uppercase tracking-wider text-luna-muted">Profiles</th>
              <th className="text-left px-5 py-2.5 text-[10px] font-bold uppercase tracking-wider text-luna-muted">Joined</th>
            </tr></thead>
            <tbody>
              {recentUsers.map(u => (
                <tr key={u.id} className="border-b border-luna-border/50 hover:bg-luna-elevated/50 transition-colors">
                  <td className="px-5 py-3 text-sm text-white">{u.email}</td>
                  <td className="px-5 py-3 text-sm text-luna-muted">{u.profiles.length}</td>
                  <td className="px-5 py-3 text-sm text-luna-muted">{new Date(u.created_at).toLocaleDateString()}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </AdminShell>
  );
}

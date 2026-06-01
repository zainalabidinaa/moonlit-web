'use client';
import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { useAdminAuth } from '../../components/AdminAuthProvider';
import { AdminShell } from '../../components/AdminShell';
import { DEFAULT_ADDON_URLS } from '../../lib/api';
import { supabase } from '../../lib/supabase';

interface AddonInfo { url: string; name: string; resources: string; profileCount: number; }

export default function AddonsPage() {
  const { user, isLoading } = useAdminAuth();
  const router = useRouter();
  const [addons, setAddons] = useState<AddonInfo[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (isLoading) return;
    if (!user) { router.replace('/login'); return; }
    load();
  }, [isLoading, user]);

  async function load() {
    const { data: usageRows } = await supabase.from('installed_addons').select('addon_url');
    const usageCounts: Record<string, number> = {};
    for (const r of (usageRows || [])) usageCounts[r.addon_url] = (usageCounts[r.addon_url] || 0) + 1;
    const results = await Promise.allSettled(DEFAULT_ADDON_URLS.map(async url => {
      try {
        const res = await fetch(url);
        const json = await res.json();
        const resources = Array.isArray(json.resources) ? json.resources.map((r: any) => typeof r === 'string' ? r : r.name).join(', ') : '—';
        return { url, name: json.name || url, resources, profileCount: usageCounts[url] || 0 };
      } catch { return { url, name: url, resources: '—', profileCount: usageCounts[url] || 0 }; }
    }));
    setAddons(results.filter((r): r is PromiseFulfilledResult<AddonInfo> => r.status === 'fulfilled').map(r => r.value));
    setLoading(false);
  }

  if (loading) return <AdminShell><div className="flex items-center justify-center h-full"><div className="animate-spin rounded-full h-6 w-6 border-2 border-luna-accent border-t-transparent" /></div></AdminShell>;

  return (
    <AdminShell>
      <div className="p-6">
        <div className="mb-6"><h1 className="text-xl font-bold text-white">Addons</h1><p className="text-sm text-luna-muted mt-0.5">Default addons loaded for all new profiles</p></div>
        <div className="bg-luna-surface border border-luna-border rounded-xl overflow-hidden">
          <table className="w-full">
            <thead><tr className="border-b border-luna-border">
              <th className="text-left px-5 py-2.5 text-[10px] font-bold uppercase tracking-wider text-luna-muted">Name</th>
              <th className="text-left px-5 py-2.5 text-[10px] font-bold uppercase tracking-wider text-luna-muted">Resources</th>
              <th className="text-left px-5 py-2.5 text-[10px] font-bold uppercase tracking-wider text-luna-muted">Profiles Using</th>
              <th className="text-left px-5 py-2.5 text-[10px] font-bold uppercase tracking-wider text-luna-muted">Status</th>
            </tr></thead>
            <tbody>
              {addons.map(a => (
                <tr key={a.url} className="border-b border-luna-border/50 hover:bg-luna-elevated/50 transition-colors">
                  <td className="px-5 py-3"><p className="text-sm font-medium text-white">{a.name}</p><p className="text-[10px] text-luna-muted truncate max-w-xs mt-0.5">{a.url}</p></td>
                  <td className="px-5 py-3 text-xs text-luna-muted">{a.resources}</td>
                  <td className="px-5 py-3 text-sm text-luna-muted">{a.profileCount}</td>
                  <td className="px-5 py-3"><span className="text-[10px] font-bold px-2 py-1 rounded-full bg-green-500/10 text-green-400">active</span></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </AdminShell>
  );
}

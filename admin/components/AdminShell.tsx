'use client';

import { usePathname, useRouter } from 'next/navigation';
import { useAdminAuth } from './AdminAuthProvider';

const NAV = [
  { href: '/dashboard', label: 'Dashboard', icon: '📊', section: 'Overview' },
  { href: '/users',     label: 'Users',      icon: '👥', section: 'Manage' },
  { href: '/profiles',  label: 'Profiles',   icon: '🎭', section: 'Manage' },
  { href: '/addons',    label: 'Addons',     icon: '🧩', section: 'Manage' },
  { href: '/invites',   label: 'Invite Codes', icon: '🎟️', section: 'Access' },
];

export function AdminShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const router = useRouter();
  const { user, signOut } = useAdminAuth();
  const sections = ['Overview', 'Manage', 'Access'];

  async function handleSignOut() {
    await signOut();
    router.push('/login');
  }

  return (
    <div className="flex h-screen bg-luna-bg overflow-hidden">
      <aside className="w-52 flex-shrink-0 bg-[#0a0a12] border-r border-luna-border flex flex-col">
        <div className="flex items-center gap-2.5 px-4 py-4 border-b border-luna-border">
          <div className="w-7 h-7 bg-luna-accent rounded-lg flex items-center justify-center text-sm">🌙</div>
          <div>
            <div className="text-sm font-bold text-white leading-none">Luna</div>
            <div className="text-[10px] text-luna-accent font-semibold tracking-wider mt-0.5">ADMIN</div>
          </div>
        </div>
        <nav className="flex-1 px-2 py-3 overflow-y-auto">
          {sections.map(section => {
            const items = NAV.filter(n => n.section === section);
            return (
              <div key={section} className="mb-3">
                <p className="text-[9px] font-bold uppercase tracking-widest text-[#333] px-2 py-1.5">{section}</p>
                {items.map(item => (
                  <button key={item.href} onClick={() => router.push(item.href)} className={`w-full flex items-center gap-2.5 px-2.5 py-2 rounded-lg text-sm font-medium transition-all mb-0.5 cursor-pointer ${pathname === item.href ? 'bg-[#1e1a2e] text-luna-accent' : 'text-[#666] hover:bg-[#13131a] hover:text-[#aaa]'}`}>
                    <span className="text-base">{item.icon}</span>
                    {item.label}
                  </button>
                ))}
              </div>
            );
          })}
        </nav>
        <div className="p-2 border-t border-luna-border">
          <div className="flex items-center gap-2 px-2.5 py-2 rounded-lg">
            <div className="w-6 h-6 bg-luna-accent rounded-full flex items-center justify-center text-[11px] font-bold text-white flex-shrink-0">{user?.email?.[0]?.toUpperCase() || 'A'}</div>
            <span className="text-xs text-luna-muted truncate flex-1">{user?.email}</span>
            <button onClick={handleSignOut} className="text-[10px] text-[#444] hover:text-red-400 cursor-pointer flex-shrink-0">Out</button>
          </div>
        </div>
      </aside>
      <main className="flex-1 overflow-y-auto">{children}</main>
    </div>
  );
}

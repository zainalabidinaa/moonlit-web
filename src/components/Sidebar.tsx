'use client';

import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { useAuth } from '@/app/AuthProvider';
import { ReactNode } from 'react';
import { SFSymbol } from '@/components/SFSymbol';

const navItems = [
  { href: '/home', label: 'Home', symbol: 'house.fill' },
  { href: '/search', label: 'Search', symbol: 'magnifyingglass' },
  { href: '/library', label: 'Library', symbol: 'book.fill' },
  { href: '/settings', label: 'Settings', symbol: 'gear' },
];

const adminItems = [
  { href: '/admin', label: 'Admin', symbol: 'person.fill' },
];

export function Sidebar({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const { currentProfile, signOut, selectProfile } = useAuth();
  const router = useRouter();
  const isAdmin = currentProfile?.role === 'admin';

  return (
    <div className="relative min-h-screen">
      {/* Centered floating pill navbar */}
      <nav className="fixed top-3 left-1/2 -translate-x-1/2 z-50 flex items-center gap-0 px-1.5 py-1.5 bg-[#1e1e1e]/90 border border-white/10 rounded-full shadow-lg shadow-black/40">
        {/* Nav links */}
        {navItems.map(({ href, label, symbol }) => (
          <Link
            key={href}
            href={href}
            className={`flex items-center gap-1.5 px-3.5 py-1.5 rounded-full text-xs font-medium transition-all duration-150 ${
              pathname === href
                ? 'bg-white/12 text-white font-semibold'
                : 'text-white/50 hover:text-white/80'
            }`}
          >
            <SFSymbol name={symbol} size={13} opacity={pathname === href ? 1 : 0.5} />
            <span>{label}</span>
          </Link>
        ))}

        {isAdmin && adminItems.map(({ href, label, symbol }) => (
          <Link
            key={href}
            href={href}
            className={`flex items-center gap-1.5 px-3.5 py-1.5 rounded-full text-xs font-medium transition-all duration-150 ${
              pathname === href
                ? 'bg-white/12 text-white font-semibold'
                : 'text-white/50 hover:text-white/80'
            }`}
          >
            <SFSymbol name={symbol} size={13} opacity={pathname === href ? 1 : 0.5} />
            <span>{label}</span>
          </Link>
        ))}

        {/* Thin separator before profile */}
        {currentProfile && <div className="w-px h-5 bg-white/10 mx-1" />}

        {/* Profile avatar */}
        {currentProfile && (
          <button
            onClick={() => { selectProfile(null as any); router.push('/profiles'); }}
            className="flex items-center gap-2 pl-1.5 pr-3 py-1 rounded-full hover:bg-white/8 transition-colors cursor-pointer"
            aria-label="Switch profile"
          >
            <div
              className="w-6 h-6 rounded-full flex items-center justify-center text-[10px] font-bold"
              style={{ backgroundColor: currentProfile.avatar_color || '#c084fc' }}
            >
              {currentProfile.name[0].toUpperCase()}
            </div>
            <span className="text-xs text-white/55">{currentProfile.name}</span>
          </button>
        )}
      </nav>

      {/* Page content — offset to clear the ~48px pill + 12px top margin */}
      <main className="min-h-screen pt-14">
        {children}
      </main>
    </div>
  );
}

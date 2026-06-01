'use client';

import { useState } from 'react';
import { useAuth } from '../AuthProvider';
import { useRouter } from 'next/navigation';

const MoonIcon = () => (
  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" className="w-7 h-7 text-luna-accent">
    <path fillRule="evenodd" d="M9.528 1.718a.75.75 0 01.162.819A8.97 8.97 0 009 6a9 9 0 009 9 8.97 8.97 0 003.463-.69.75.75 0 01.981.98 10.503 10.503 0 01-9.694 6.46c-5.799 0-10.5-4.701-10.5-10.5 0-4.368 2.667-8.112 6.46-9.694a.75.75 0 01.818.162z" clipRule="evenodd" />
  </svg>
);

export default function ProfilesPage() {
  const { profiles, currentProfile, selectProfile, createProfile, deleteProfile, signOut } = useAuth();
  const router = useRouter();
  const [showCreate, setShowCreate] = useState(false);
  const [newName, setNewName] = useState('');

  function handleSelect(profile: any) {
    selectProfile(profile);
    router.push('/home');
  }

  async function handleCreate() {
    if (!newName.trim()) return;
    await createProfile(newName.trim());
    setNewName('');
    setShowCreate(false);
  }

  return (
    <div className="relative flex items-center justify-center min-h-screen overflow-hidden">
      {/* Background glow */}
      <div className="absolute inset-0 bg-luna-bg" />
      <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[500px] h-[500px] rounded-full bg-purple-600/8 blur-3xl pointer-events-none" />

      <div className="relative text-center max-w-lg w-full px-6">
        <div className="flex justify-center mb-4">
          <MoonIcon />
        </div>
        <h1 className="text-2xl font-semibold tracking-tight mb-1">Who&apos;s watching?</h1>
        <p className="text-sm text-luna-muted mb-10">Select a profile to continue</p>

        <div className="grid grid-cols-3 gap-4 mb-8">
          {profiles.map(p => (
            <button
              key={p.id}
              onClick={() => handleSelect(p)}
              className="group flex flex-col items-center gap-2.5 p-4 rounded-2xl hover:bg-white/5 transition-all duration-200 cursor-pointer relative"
            >
              <div
                className="w-16 h-16 rounded-full flex items-center justify-center text-xl font-bold ring-2 ring-transparent group-hover:ring-luna-accent/50 transition-all duration-200"
                style={{ backgroundColor: p.avatar_color || '#c084fc' }}
              >
                {p.name[0].toUpperCase()}
              </div>
              <span className="text-sm font-medium text-white/90 group-hover:text-white">{p.name}</span>
              {p.role === 'admin' && (
                <span className="text-xs text-luna-accent font-medium">Admin</span>
              )}
              {p.id !== currentProfile?.id && (
                <button
                  onClick={e => { e.stopPropagation(); deleteProfile(p.id); }}
                  className="absolute top-2 right-2 text-xs text-luna-muted hover:text-red-400 opacity-0 group-hover:opacity-100 transition-all duration-200 cursor-pointer"
                  aria-label="Remove profile"
                >
                  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" className="w-3.5 h-3.5">
                    <path d="M6.28 5.22a.75.75 0 00-1.06 1.06L8.94 10l-3.72 3.72a.75.75 0 101.06 1.06L10 11.06l3.72 3.72a.75.75 0 101.06-1.06L11.06 10l3.72-3.72a.75.75 0 00-1.06-1.06L10 8.94 6.28 5.22z" />
                  </svg>
                </button>
              )}
            </button>
          ))}

          <button
            onClick={() => setShowCreate(true)}
            className="flex flex-col items-center gap-2.5 p-4 rounded-2xl hover:bg-white/5 transition-all duration-200 cursor-pointer"
          >
            <div className="w-16 h-16 rounded-full border-2 border-dashed border-white/20 hover:border-luna-accent/50 flex items-center justify-center text-2xl text-luna-muted hover:text-luna-accent transition-all duration-200">
              +
            </div>
            <span className="text-sm text-luna-muted hover:text-white transition-colors">Add Profile</span>
          </button>
        </div>

        {showCreate && (
          <div className="flex gap-2 mb-6 max-w-xs mx-auto">
            <input
              autoFocus
              value={newName}
              onChange={e => setNewName(e.target.value)}
              onKeyDown={e => e.key === 'Enter' && handleCreate()}
              placeholder="Profile name"
              className="flex-1 px-4 py-2.5 bg-white/5 border border-white/10 rounded-xl text-white text-sm focus:outline-none focus:border-purple-400/60 transition-all"
            />
            <button
              onClick={handleCreate}
              className="px-4 py-2.5 bg-luna-accent hover:bg-purple-400 rounded-xl text-sm font-semibold transition-colors cursor-pointer"
            >
              Create
            </button>
          </div>
        )}

        <button
          onClick={signOut}
          className="text-sm text-luna-muted hover:text-white transition-colors cursor-pointer"
        >
          Sign Out
        </button>
      </div>
    </div>
  );
}

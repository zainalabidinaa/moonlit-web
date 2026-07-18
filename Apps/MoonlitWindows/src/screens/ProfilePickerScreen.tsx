import { useState } from 'react';
import { useAuth } from '@/app/AuthProvider';

function AvatarCircle({ name, color, size = 80 }: { name: string; color?: string; size?: number }) {
  const initial = name.charAt(0).toUpperCase() || '?';
  const bg = color || '#444';
  return (
    <div
      className="rounded-full flex items-center justify-center text-white font-semibold select-none"
      style={{ width: size, height: size, backgroundColor: bg, fontSize: size * 0.35 }}
    >
      {initial}
    </div>
  );
}

export function ProfilePickerScreen() {
  const { profiles, currentProfile, selectProfile, createProfile, signOut } = useAuth();
  const [showCreate, setShowCreate] = useState(false);
  const [newName, setNewName] = useState('');
  const [isCreating, setIsCreating] = useState(false);

  async function handleCreate(e: React.FormEvent) {
    e.preventDefault();
    if (!newName.trim()) return;
    setIsCreating(true);
    try {
      await createProfile(newName.trim());
      setShowCreate(false);
      setNewName('');
    } catch {}
    setIsCreating(false);
  }

  if (showCreate) {
    return (
      <div className="min-h-screen bg-moonlit-bg flex items-center justify-center p-4">
        <form onSubmit={handleCreate} className="w-full max-w-[300px] flex flex-col items-center gap-5">
          <div className="w-[72px] h-[72px] rounded-[20px] bg-white/10 shadow-lg" />
          <div className="text-xl font-semibold text-white">Create Profile</div>
          <AvatarCircle name={newName || '?'} size={92} />
          <input
            type="text"
            placeholder="Profile Name"
            value={newName}
            onChange={e => setNewName(e.target.value)}
            className="w-full px-3.5 py-2.5 bg-moonlit-surface border border-white/10 rounded-[10px] text-sm text-white placeholder:text-white/30 outline-none"
            autoFocus
          />
          <button
            type="submit"
            disabled={!newName.trim() || isCreating}
            className="btn-primary w-full disabled:opacity-50"
          >
            {isCreating ? 'Creating...' : 'Create Profile'}
          </button>
          <button
            type="button"
            onClick={() => setShowCreate(false)}
            className="text-[13px] text-white/50 hover:text-white/80"
          >
            Cancel
          </button>
        </form>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-moonlit-bg flex items-center justify-center p-4">
      <div className="flex flex-col items-center gap-7">
        <div className="w-16 h-16 rounded-[16px] bg-white/10 shadow-lg" />
        <div className="text-xl font-semibold text-white">Who&apos;s watching?</div>

        <div className="grid grid-cols-2 sm:grid-cols-3 gap-5 max-w-[400px]">
          {profiles.map(profile => (
            <button
              key={profile.id}
              onClick={() => selectProfile(profile)}
              className="flex flex-col items-center gap-2"
            >
              <AvatarCircle name={profile.name} color={profile.avatar_color} size={80} />
              <span className="text-sm text-white">{profile.name}</span>
              {profile.isAdmin && (
                <span className="text-[11px] text-white/50">Admin</span>
              )}
            </button>
          ))}

          <button
            onClick={() => setShowCreate(true)}
            className="flex flex-col items-center gap-2"
          >
            <div
              className="rounded-full border-2 border-white/20 flex items-center justify-center"
              style={{ width: 80, height: 80 }}
            >
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="text-white/50">
                <path d="M12 5v14M5 12h14" />
              </svg>
            </div>
            <span className="text-sm text-white/50">Add Profile</span>
          </button>
        </div>

        <button
          onClick={signOut}
          className="text-sm text-white/50 hover:text-white/80"
        >
          Sign Out
        </button>
      </div>
    </div>
  );
}

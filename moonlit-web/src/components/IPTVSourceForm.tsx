import { useState } from 'react';
import { createPortal } from 'react-dom';
import type { FormEvent } from 'react';
import type { IPTVPlaylistSource, IPTVSourceKind, XtreamCredentials } from '@/lib/iptv';
import { IPTV_SOURCE_KIND_LABELS } from '@/lib/iptv';

interface Props {
  source?: IPTVPlaylistSource;
  onSave: (source: IPTVPlaylistSource) => void;
  onClose: () => void;
}

export function IPTVSourceForm({ source, onSave, onClose }: Props) {
  const [name, setName] = useState(source?.name ?? '');
  const [kind, setKind] = useState<IPTVSourceKind>(source?.kind ?? 'm3u');
  const [url, setUrl] = useState(source?.url ?? '');
  const [epgUrl, setEpgUrl] = useState(source?.epgUrl ?? '');
  const [server, setServer] = useState(source?.xtream?.server ?? '');
  const [username, setUsername] = useState(source?.xtream?.username ?? '');
  const [password, setPassword] = useState(source?.xtream?.password ?? '');
  const [submitting, setSubmitting] = useState(false);

  const isEditing = !!source;

  function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setSubmitting(true);
    const now = Date.now();
    let xtream: XtreamCredentials | undefined;
    if (kind === 'xtream') {
      xtream = { server: server.trim(), username: username.trim(), password: password.trim() };
    }
    const newSource: IPTVPlaylistSource = {
      id: source?.id ?? crypto.randomUUID(),
      name: name.trim() || 'Untitled Source',
      url: kind === 'xtream' ? '' : url.trim(),
      epgUrl: epgUrl.trim() || undefined,
      kind,
      xtream,
      createdAt: source?.createdAt ?? now,
    };
    onSave(newSource);
  }

  function handleBackdropClick(e: React.MouseEvent) {
    if (e.target === e.currentTarget) onClose();
  }

  function handleKeyDown(e: React.KeyboardEvent) {
    if (e.key === 'Escape') onClose();
  }

  const content = (
    <div
      className="fixed inset-0 z-[100] flex items-center justify-center bg-black/60"
      onClick={handleBackdropClick}
      onKeyDown={handleKeyDown}
      role="dialog"
      aria-modal="true"
      aria-label={isEditing ? 'Edit IPTV source' : 'Add IPTV source'}
    >
      <div className="w-full max-w-lg mx-4 rounded-ml-lg border border-white/10 bg-[#1f1f1f] p-6 shadow-2xl">
        <div className="flex items-center justify-between mb-6">
          <h2 className="text-lg font-semibold text-white">
            {isEditing ? 'Edit source' : 'Add IPTV source'}
          </h2>
          <button
            onClick={onClose}
            className="flex h-7 w-7 items-center justify-center rounded text-white/50 hover:bg-white/10 hover:text-white"
            aria-label="Close"
          >
            <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="1.5">
              <path d="M1 1l12 12M13 1L1 13" />
            </svg>
          </button>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="block text-xs font-bold text-white/40 uppercase tracking-wider mb-1.5">
              Source type
            </label>
            <div className="flex gap-2">
              {(Object.entries(IPTV_SOURCE_KIND_LABELS) as [IPTVSourceKind, string][]).map(([k, label]) => (
                <button
                  key={k}
                  type="button"
                  onClick={() => setKind(k)}
                  className={`px-3 py-1.5 rounded text-xs font-medium transition-colors ${
                    kind === k
                      ? 'bg-white text-black'
                      : 'bg-[#2a2a2a] text-white/60 hover:bg-white/10 hover:text-white'
                  }`}
                >
                  {label}
                </button>
              ))}
            </div>
          </div>

          <div>
            <label htmlFor="iptv-name" className="block text-xs font-bold text-white/40 uppercase tracking-wider mb-1.5">
              Display name
            </label>
            <input
              id="iptv-name"
              value={name}
              onChange={e => setName(e.target.value)}
              placeholder="e.g. My Provider"
              className="w-full px-3 py-2.5 bg-[#2a2a2a] rounded text-sm text-white placeholder-white/25 border border-white/10 focus:outline-none focus:ring-1 focus:ring-white/30"
            />
          </div>

          {kind === 'xtream' ? (
            <>
              <div>
                <label htmlFor="iptv-server" className="block text-xs font-bold text-white/40 uppercase tracking-wider mb-1.5">
                  Server URL
                </label>
                <input
                  id="iptv-server"
                  value={server}
                  onChange={e => setServer(e.target.value)}
                  placeholder="http://example.com:8080"
                  className="w-full px-3 py-2.5 bg-[#2a2a2a] rounded text-sm text-white placeholder-white/25 border border-white/10 focus:outline-none focus:ring-1 focus:ring-white/30"
                />
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label htmlFor="iptv-username" className="block text-xs font-bold text-white/40 uppercase tracking-wider mb-1.5">
                    Username
                  </label>
                  <input
                    id="iptv-username"
                    value={username}
                    onChange={e => setUsername(e.target.value)}
                    className="w-full px-3 py-2.5 bg-[#2a2a2a] rounded text-sm text-white placeholder-white/25 border border-white/10 focus:outline-none focus:ring-1 focus:ring-white/30"
                  />
                </div>
                <div>
                  <label htmlFor="iptv-password" className="block text-xs font-bold text-white/40 uppercase tracking-wider mb-1.5">
                    Password
                  </label>
                  <input
                    id="iptv-password"
                    type="password"
                    value={password}
                    onChange={e => setPassword(e.target.value)}
                    className="w-full px-3 py-2.5 bg-[#2a2a2a] rounded text-sm text-white placeholder-white/25 border border-white/10 focus:outline-none focus:ring-1 focus:ring-white/30"
                  />
                </div>
              </div>
            </>
          ) : (
            <div>
              <label htmlFor="iptv-url" className="block text-xs font-bold text-white/40 uppercase tracking-wider mb-1.5">
                {kind === 'epg' ? 'EPG URL' : 'Playlist URL'}
              </label>
              <input
                id="iptv-url"
                value={url}
                onChange={e => setUrl(e.target.value)}
                placeholder={kind === 'epg' ? 'https://example.com/epg.xml' : 'https://example.com/playlist.m3u'}
                className="w-full px-3 py-2.5 bg-[#2a2a2a] rounded text-sm text-white placeholder-white/25 border border-white/10 focus:outline-none focus:ring-1 focus:ring-white/30"
              />
            </div>
          )}

          {kind !== 'epg' && (
            <div>
              <label htmlFor="iptv-epg" className="block text-xs font-bold text-white/40 uppercase tracking-wider mb-1.5">
                EPG URL
                <span className="font-normal text-white/25 ml-1">(optional)</span>
              </label>
              <input
                id="iptv-epg"
                value={epgUrl}
                onChange={e => setEpgUrl(e.target.value)}
                placeholder="https://example.com/epg.xml"
                className="w-full px-3 py-2.5 bg-[#2a2a2a] rounded text-sm text-white placeholder-white/25 border border-white/10 focus:outline-none focus:ring-1 focus:ring-white/30"
              />
            </div>
          )}

          <div className="flex gap-3 pt-2">
            <button
              type="button"
              onClick={onClose}
              className="flex-1 px-4 py-2.5 rounded text-sm font-medium text-white/60 hover:bg-white/10 hover:text-white transition-colors"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={submitting}
              className="flex-1 px-4 py-2.5 bg-white text-black rounded text-sm font-semibold disabled:opacity-40 hover:bg-white/90 transition-colors flex items-center justify-center"
            >
              {submitting
                ? <div className="w-4 h-4 rounded-full border-2 border-black/20 border-t-black animate-spin-arc" />
                : isEditing ? 'Save changes' : 'Add source'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );

  return createPortal(content, document.body);
}

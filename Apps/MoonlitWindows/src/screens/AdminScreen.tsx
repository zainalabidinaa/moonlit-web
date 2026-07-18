import { useState, useEffect, useCallback } from 'react';
import { motion } from 'framer-motion';
import { supabase } from '@/lib/supabase';
import { generateInviteCode, getInviteCodes, revokeInviteCode } from '@/lib/services/api';
import StrokeSpinner from '@/components/StrokeSpinner';
import type { InviteCode } from '@/lib/types';

export function AdminScreen() {
  const [inviteCodes, setInviteCodes] = useState<InviteCode[]>([]);
  const [maxUses, setMaxUses] = useState(1);
  const [isGenerating, setIsGenerating] = useState(false);

  const loadCodes = useCallback(async () => {
    try {
      const codes = await getInviteCodes();
      setInviteCodes(codes);
    } catch {}
  }, []);

  useEffect(() => {
    loadCodes();
  }, [loadCodes]);

  const handleGenerate = async () => {
    setIsGenerating(true);
    try {
      const { data: { session } } = await supabase.auth.getSession();
      if (session?.user) {
        await generateInviteCode(session.user.id, maxUses);
        await loadCodes();
      }
    } catch {}
    setIsGenerating(false);
  };

  const handleRevoke = async (code: string) => {
    await revokeInviteCode(code);
    await loadCodes();
  };

  return (
    <div className="min-h-screen bg-moonlit-bg">
      <div className="max-w-[640px] mx-auto px-6 pt-24 pb-12">
        <h1 className="text-[26px] font-bold text-white mb-5">Admin Panel</h1>

        <div className="mb-5">
          <span className="text-[11px] font-bold text-white/35 tracking-[1px] uppercase block mb-2">Generate Invite Code</span>
          <div className="p-4 bg-moonlit-surface rounded-xl">
            <div className="flex items-center gap-4 mb-4">
              <span className="text-[14px] text-white/60">Max uses</span>
              <div className="flex items-center gap-3">
                <button
                  type="button"
                  onClick={() => setMaxUses(Math.max(1, maxUses - 1))}
                  className="w-7 h-7 rounded-full bg-white/[0.1] text-white flex items-center justify-center text-[16px]"
                >−</button>
                <span className="text-[16px] font-semibold text-white min-w-[28px] text-center">{maxUses}</span>
                <button
                  type="button"
                  onClick={() => setMaxUses(Math.min(100, maxUses + 1))}
                  className="w-7 h-7 rounded-full bg-white/[0.1] text-white flex items-center justify-center text-[16px]"
                >+</button>
              </div>
            </div>

            <button
              type="button"
              onClick={handleGenerate}
              disabled={isGenerating}
              className="w-full flex items-center justify-center gap-1.5 py-2.5 text-[14px] font-semibold text-white bg-harbor-gold rounded-lg disabled:opacity-50"
            >
              {isGenerating && <StrokeSpinner size={16} />}
              {isGenerating ? 'Generating...' : 'Generate Code'}
            </button>
          </div>
        </div>

        <div>
          <span className="text-[11px] font-bold text-white/35 tracking-[1px] uppercase block mb-2">
            Invite Codes ({inviteCodes.length})
          </span>

          {inviteCodes.length === 0 ? (
            <div className="p-4 bg-moonlit-surface rounded-xl text-[12px] text-white/40">
              No invite codes yet. Generate one above.
            </div>
          ) : (
            <div className="bg-moonlit-surface rounded-xl overflow-hidden">
              {inviteCodes.map((code, i) => {
                const active = code.is_active && !code.used_by;
                return (
                  <div key={code.code}>
                    <div className="flex items-center gap-3 px-4 py-3">
                      <span className="text-[16px] font-bold font-mono text-harbor-gold">{code.code}</span>
                      <div className="flex-1" />
                      <div className={`w-[7px] h-[7px] rounded-full ${
                        active ? 'bg-green-400' : code.used_by ? 'bg-gray-400' : 'bg-red-400'
                      }`} />
                      <span className="text-[12px] text-white/40">
                        {active ? 'Active' : code.used_by ? 'Used' : 'Revoked'}
                      </span>
                      {active && (
                        <button
                          type="button"
                          onClick={() => handleRevoke(code.code)}
                          className="text-red-400 text-[12px] font-medium hover:underline ml-2"
                        >
                          Revoke
                        </button>
                      )}
                    </div>
                    {i < inviteCodes.length - 1 && <div className="h-px bg-white/[0.06]" />}
                  </div>
                );
              })}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

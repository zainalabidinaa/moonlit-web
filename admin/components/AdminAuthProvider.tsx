'use client';

import { createContext, useContext, useEffect, useState, ReactNode } from 'react';
import { supabase } from '../lib/supabase';

interface AdminAuthContextType {
  user: any;
  isLoading: boolean;
  signIn: (email: string, password: string) => Promise<void>;
  signOut: () => Promise<void>;
}

const AdminAuthContext = createContext<AdminAuthContextType | null>(null);

export function AdminAuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<any>(null);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    supabase.auth.getSession().then(async ({ data }) => {
      if (data.session?.user) {
        const isAdmin = await checkAdminRole(data.session.user.id);
        setUser(isAdmin ? data.session.user : null);
        if (!isAdmin) await supabase.auth.signOut();
      }
      setIsLoading(false);
    });

    const { data: listener } = supabase.auth.onAuthStateChange(async (_e, session) => {
      if (session?.user) {
        const isAdmin = await checkAdminRole(session.user.id);
        setUser(isAdmin ? session.user : null);
        if (!isAdmin) await supabase.auth.signOut();
      } else {
        setUser(null);
      }
    });

    return () => listener.subscription.unsubscribe();
  }, []);

  async function checkAdminRole(userId: string): Promise<boolean> {
    const { data } = await supabase
      .from('profiles')
      .select('role')
      .eq('user_id', userId)
      .eq('role', 'admin')
      .limit(1)
      .single();
    return !!data;
  }

  async function handleSignIn(email: string, password: string) {
    const { data, error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) throw error;
    if (data.user) {
      const isAdmin = await checkAdminRole(data.user.id);
      if (!isAdmin) {
        await supabase.auth.signOut();
        throw new Error('Access denied — admin role required');
      }
      setUser(data.user);
    }
  }

  async function handleSignOut() {
    await supabase.auth.signOut();
    setUser(null);
  }

  return (
    <AdminAuthContext.Provider value={{ user, isLoading, signIn: handleSignIn, signOut: handleSignOut }}>
      {children}
    </AdminAuthContext.Provider>
  );
}

export function useAdminAuth() {
  const ctx = useContext(AdminAuthContext);
  if (!ctx) throw new Error('useAdminAuth must be used within AdminAuthProvider');
  return ctx;
}

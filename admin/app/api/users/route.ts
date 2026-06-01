import { createClient } from '@supabase/supabase-js';
import { NextResponse } from 'next/server';

export async function GET() {
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!serviceKey) {
    return NextResponse.json({ error: 'Service role key not configured' }, { status: 500 });
  }

  const admin = createClient(
    'https://hvfsntdyowapjxobtyli.supabase.co',
    serviceKey,
    { auth: { autoRefreshToken: false, persistSession: false } }
  );

  const { data, error } = await admin.auth.admin.listUsers();
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });

  return NextResponse.json(data.users.map(u => ({
    id: u.id,
    email: u.email,
    created_at: u.created_at,
  })));
}

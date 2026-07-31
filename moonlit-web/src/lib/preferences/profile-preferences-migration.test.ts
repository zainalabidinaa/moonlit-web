import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const migrationPath = resolve(process.cwd(), '../supabase/migrations/20260731_profile_preferences.sql');

describe('profile_preferences migration', () => {
  it('defines the versioned per-profile value contract and owner-only RLS', async () => {
    const sql = (await readFile(migrationPath, 'utf8')).toLowerCase();

    expect(sql).toContain('create table if not exists public.profile_preferences');
    expect(sql).toMatch(/profile_id\s+uuid\s+not null\s+references\s+public\.profiles\s*\(id\)/);
    expect(sql).toMatch(/namespace\s+text\s+not null/);
    expect(sql).toMatch(/schema_version\s+integer\s+not null/);
    expect(sql).toMatch(/value\s+jsonb\s+not null/);
    expect(sql).toMatch(/updated_at\s+timestamptz\s+not null/);
    expect(sql).toContain('primary key (profile_id, namespace)');
    expect(sql).toContain('enable row level security');
    expect(sql).toMatch(/for all[\s\S]*profiles\.user_id\s*=\s*auth\.uid\(\)[\s\S]*with check/);
  });
});

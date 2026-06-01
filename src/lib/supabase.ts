import { createClient } from '@supabase/supabase-js';

const supabaseUrl = 'https://hvfsntdyowapjxobtyli.supabase.co';
const supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh2ZnNudGR5b3dhcGp4b2J0eWxpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODAxNzg0OTUsImV4cCI6MjA5NTc1NDQ5NX0.YraHrXjD-l_CmzEbs7jRW34i83HIlKcOh76xbfOn6sQ';

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
  }
});

export const TMDB_API_KEY = '1e818317d3086727eceecf0571621527';

export const DEFAULT_ADDONS = [
  'https://aiometadata.elfhosted.com/stremio/d67da46b-f48e-4efa-a9e2-21ac1a6c3a4a/manifest.json',
  'https://aiostreams.elfhosted.com/stremio/7d3fcfe4-393e-430c-aea7-47235eef5df5/eyJpIjoiV3RpV2xVZi96N2VrMVpXSmtrQWtuQT09IiwiZSI6Ikg5TjRKelR5bzMzNCsyY2dtTmcwV1BxNXRoMWxUVktLYVlkTmlqTi9kZjBwN1NERUo3b1JyUjhNckpvWmlKcEEiLCJ0IjoiYSJ9/manifest.json',
  'https://v3-cinemeta.strem.io/manifest.json',
  'https://opensubtitlesv3-pro.dexter21767.com/eyJsYW5ncyI6WyJlbmdsaXNoIl0sInNvdXJjZSI6ImFsbCIsImFpVHJhbnNsYXRlZCI6ZmFsc2UsImF1dG9BZGp1c3RtZW50IjpmYWxzZX0=/manifest.json',
  'https://opensubtitles-v3.strem.io/manifest.json',
];

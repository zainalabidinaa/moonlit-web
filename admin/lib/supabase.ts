import { createClient } from '@supabase/supabase-js';

export const supabase = createClient(
  'https://hvfsntdyowapjxobtyli.supabase.co',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh2ZnNudGR5b3dhcGp4b2J0eWxpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODAxNzg0OTUsImV4cCI6MjA5NTc1NDQ5NX0.YraHrXjD-l_CmzEbs7jRW34i83HIlKcOh76xbfOn6sQ',
  { auth: { persistSession: true, autoRefreshToken: true } }
);

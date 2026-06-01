# Luna Admin Panel — Design Spec

**Date:** 2026-05-31  
**Status:** Approved

---

## Overview

A standalone admin panel for Luna, deployed as a separate Vercel project from the same GitHub repo (`zainalabidinaa/luna-web`). Uses the same Supabase project for data. Accessible only to users with `role = 'admin'` in the profiles table.

---

## Architecture

### Repo structure
```
LunaWeb/
├── src/                  # Existing Luna app (unchanged)
├── admin/                # New admin app
│   ├── app/
│   │   ├── layout.tsx
│   │   ├── page.tsx              # Redirect to /dashboard
│   │   ├── login/page.tsx
│   │   ├── dashboard/page.tsx
│   │   ├── users/page.tsx
│   │   ├── profiles/page.tsx
│   │   ├── addons/page.tsx
│   │   └── invites/page.tsx
│   ├── components/
│   │   ├── AdminShell.tsx        # Sidebar + topbar layout wrapper
│   │   └── AdminAuth.tsx         # Auth guard context
│   └── lib/
│       └── admin-api.ts          # Supabase queries (uses service role key)
├── package.json          # Shared
└── ...
```

### Vercel setup
- **Luna app:** root directory = `.` (existing, unchanged)
- **Admin app:** root directory = `admin/`, deployed as a second Vercel project on the same repo

### Auth
- Admin logs in with email/password via Supabase (same credentials as Luna)
- After login, checks `profiles.role = 'admin'` — if not admin, rejects and signs out
- Session stored in Supabase auth (same client)
- No separate admin credentials needed

---

## Pages

### Dashboard
- 4 stat cards: Total Users, Total Profiles, Active Invites, Watch Events
- Recent users table (last 10 by created_at)

### Users
- Table: email, profile count, joined date, role badge
- Search by email (client-side filter)
- Click row → expand to see user's profiles inline

### Profiles
- Table: name, owner email, role, addon count, library count
- Delete profile action (with confirmation)

### Addons
- Table of DEFAULT_ADDONS with name, resource types, status
- Edit button → modal to add/remove URLs from DEFAULT_ADDONS stored in a `config` table

### Invite Codes
- Table: code, max uses, used by, created date, status badge
- Generate button (with max uses input)
- Revoke button per active code

---

## Data Layer

All queries in `admin/lib/admin-api.ts` using the existing Supabase anon client (same `src/lib/supabase.ts` credentials). Queries needed:

- `getAllUsers()` — join `auth.users` via profiles table
- `getAllProfiles()` — profiles with user email via join
- `getAddonUsage()` — count installed_addons per addon URL
- `getAdminStats()` — counts across users, profiles, watch_progress, invite_codes
- `getInviteCodes()` — existing function
- `generateInviteCode()` — existing function
- `revokeInviteCode()` — existing function
- `deleteProfile()` — existing function

---

## UI Design

- **Theme:** Same Luna dark palette (`#080810` bg, `#a78bfa` accent, white text)
- **Layout:** Fixed sidebar (200px) + scrollable main content area
- **Sidebar nav sections:** Overview (Dashboard) / Manage (Users, Profiles, Addons) / Access (Invite Codes)
- **Typography:** System font stack, same as Luna
- **No external UI library** — plain Tailwind CSS, consistent with Luna

---

## Tech Stack

- Next.js 14 (same version as Luna)
- Tailwind CSS (shared config)
- TypeScript
- Supabase JS client (shared credentials)

---

## Deployment

1. Build `admin/` as a separate Next.js app with its own `package.json` and `next.config.js`
2. Create a new Vercel project pointing at the same GitHub repo with root directory = `admin`
3. URL: `luna-admin.vercel.app` (or similar)

---

## Out of Scope

- Per-user watch history analytics (future)
- Bulk user actions (future)
- Admin audit log (future)
- Dark/light theme toggle

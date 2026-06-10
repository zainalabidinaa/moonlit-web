# Luna Portal — Design Spec
*Date: 2026-06-10*

## Overview

A standalone web portal for Luna that handles consumer-facing purchasing/signup and per-user account management, plus an admin layer for catalog CMS, user management, and invite codes. Separate from the existing `/admin` Next.js panel.

---

## Stack

| Concern | Choice |
|---------|--------|
| Framework | Vite 5 + React 18 + TypeScript |
| Styling | Tailwind CSS 3 |
| Routing | React Router v6 |
| Backend | Supabase (existing project) |
| Payments | Stripe Checkout + Customer Portal |
| Webhook handler | Supabase Edge Function |
| Deployment | Vercel (or Netlify) |

**Theme:** Light — `bg: #f2f6fc`, white surface cards, `accent: #6d28d9`, dark text `#0f172a`. Matches the luna-portal-concept.html design.

---

## Project Structure

```
Luna/luna-portal/
├── src/
│   ├── lib/
│   │   ├── supabase.ts          # Supabase client (same project as admin)
│   │   └── stripe.ts            # Stripe.js loader helper
│   ├── context/
│   │   └── AuthContext.tsx      # session, user, role, activeProfile, profiles
│   ├── routes/
│   │   ├── public/
│   │   │   ├── PricingPage.tsx
│   │   │   ├── SignupPage.tsx
│   │   │   └── LoginPage.tsx
│   │   ├── user/
│   │   │   ├── ProfilesPage.tsx
│   │   │   ├── AddonsPage.tsx
│   │   │   └── BillingPage.tsx
│   │   └── admin/
│   │       ├── CatalogPage.tsx
│   │       ├── UsersPage.tsx
│   │       └── InvitesPage.tsx
│   ├── components/
│   │   ├── Button.tsx
│   │   ├── Card.tsx
│   │   ├── Modal.tsx
│   │   ├── Badge.tsx
│   │   ├── DragHandle.tsx
│   │   ├── AvatarPicker.tsx
│   │   ├── PlanBadge.tsx
│   │   └── StepWizard.tsx
│   └── App.tsx                  # Router + route guards
├── supabase/
│   └── functions/
│       ├── stripe-webhook/      # Handles checkout.session.completed
│       └── admin-users/         # Returns all profiles (service role)
├── vite.config.ts
├── tailwind.config.ts
└── package.json
```

---

## User Tiers

| Role value | Tier name | Access | Addon management |
|------------|-----------|--------|-----------------|
| `admin` | Admin | Everything | Full |
| `friends_family` | Friends & Family | User screens | Read-only (inherits admin's) |
| `premium` | Premium | User screens | Locked (pre-configured) |
| `premium_plus` | Premium+ | User screens | Self-managed |

Role is stored as `profiles.role` (TEXT). Addon inheritance: `profiles.uses_primary_addons = true` for F&F means the client reads the admin user's `installed_addons` instead of the user's own.

---

## Auth Flow

### Route Guards

- `<PublicRoute>` — accessible without session; redirects logged-in users to `/profiles`
- `<UserRoute>` — requires active session; redirects to `/login` if none
- `<AdminRoute>` — requires session + `role === 'admin'`; redirects non-admins to `/profiles`

### AuthContext shape

```ts
interface AuthContextValue {
  session: Session | null;
  user: User | null;
  role: 'admin' | 'friends_family' | 'premium' | 'premium_plus' | null;
  profiles: Profile[];
  activeProfile: Profile | null;
  setActiveProfile: (p: Profile) => void;
  loading: boolean;
}
```

Role is resolved by fetching `profiles.role` for the first profile belonging to `auth.uid()`.

### Signup — Invite Code Path (F&F)

1. User navigates to `/signup`, selects "I have an invite code" tab
2. Enters code → client calls `validate_invite_code(code)` RPC
3. If valid: user fills email + password → `supabase.auth.signUp()`
4. On success: insert `profiles` row with `role = 'friends_family'`, `uses_primary_addons = true`
5. Mark invite code used: update `invite_codes.used_by` and `used_at`
6. Redirect to `/profiles`

### Signup — Stripe Path (Premium / Premium+)

1. User selects plan on `/pricing` → routed to `/signup?plan=premium` or `?plan=premium_plus`
2. Client calls Supabase Edge Function `create-checkout-session` with plan
3. Edge Function creates Stripe Checkout Session, returns URL
4. Browser redirects to Stripe Checkout (hosted)
5. On success, Stripe fires `checkout.session.completed` webhook
6. `stripe-webhook` Edge Function:
   - Creates Supabase auth user via `admin.createUser()`
   - Inserts `profiles` row with correct role
   - Sends magic-link email for password setup
7. User clicks magic link → lands on `/profiles`

---

## Screens

### PricingPage (`/pricing`)
- Full-width hero with light blue-white gradient, Luna logo, tagline
- 3 plan cards: Friends & Family (invite-only, no price shown), Premium (monthly price), Premium+ (monthly price)
- Feature comparison table below cards
- F&F card CTA: "Request Access" → redirects to `/signup` with the invite-code tab pre-selected
- Premium/Premium+ CTA: "Get Started" → `/signup?plan=…`
- Nav: Login link top-right

### SignupPage (`/signup`)
- Two tabs: **"Have an invite code"** / **"Subscribe"**
- Invite tab: code input field + email/password fields + submit
- Subscribe tab: shows selected plan summary + "Continue to payment" → Stripe Checkout
- Link back to `/login`

### LoginPage (`/login`)
- Email + password form
- "Forgot password" → Supabase password reset email
- Link to `/signup`

### ProfilesPage (`/profiles`) — UserRoute
- Netflix-style grid of sub-profiles (avatars + names)
- "+ Add Profile" card (max 5 profiles per account)
- Edit mode: pencil icon per profile → opens edit modal (name, avatar color/id, PIN toggle)
- Delete profile (with confirmation)
- Clicking a profile sets `activeProfile` in context → navigates to `/account`

### AddonsPage (`/addons`) — UserRoute
- **Admin / Premium+:** full list with add URL input, enable/disable toggle, drag-to-reorder, remove button
- **F&F:** read-only list labeled "Using [Admin Name]'s addons"
- **Premium:** read-only locked list labeled "Managed by Luna"
- Add addon: text input for addon URL → validates format → inserts to `installed_addons`

### BillingPage (`/billing`) — UserRoute
- Current plan badge (role-derived)
- F&F: "Access granted by invitation" — no billing info
- Premium/Premium+: next billing date, last 4 of card, "Manage Billing" button → Stripe Customer Portal redirect
- "Cancel subscription" link inside Customer Portal (not in-app)

### CatalogPage (`/admin/catalog`) — AdminRoute
- List of collections with drag handle, name, emoji, status badge, item count
- Drag-to-reorder using HTML5 Drag and Drop API (saves `sort_order` to `collections` table)
- "+ New Collection" button
- Row actions: Edit (opens 4-step modal), Duplicate, Delete
- **4-step collection editor modal:**
  - **Step 1 — Basics:** name, emoji, description, visibility toggle, pin-to-top toggle
  - **Step 2 — Content:** detects `hasGroups`. If flat: source list with add/remove/reorder. If grouped: 3-column layout (group list | source editor for selected group | preview)
  - **Step 3 — Artwork:** backdrop URL, tile shape selector, cover image upload, hero backdrop, hero video URL, focus GIF URL
  - **Step 4 — Review:** read-only summary of all settings, Save button

### UsersPage (`/admin/users`) — AdminRoute
- Table: email, role badge, created date, profile count, status
- Data fetched via `admin-users` Edge Function (service role, bypasses RLS)
- Inline role change dropdown (updates `profiles.role`)
- Suspend toggle (sets Supabase auth user `banned` state via Edge Function)

### InvitesPage (`/admin/invites`) — AdminRoute
- "Generate Code" button with tier selector (F&F only — Premium/Premium+ use Stripe)
- Generated code displayed with copy button
- Table of all codes: code, tier, status (active/used), created date, used-by email

---

## Edge Functions

### `stripe-webhook`
- Validates Stripe signature
- Handles `checkout.session.completed`: creates auth user, inserts profile row, sends magic link
- Handles `customer.subscription.deleted`: marks profile as suspended (or downgrades role)

### `admin-users`
- Requires caller to be admin (checks `profiles.role` via service role)
- Returns all `profiles` rows joined with `auth.users` email

### `create-checkout-session`
- Accepts `plan: 'premium' | 'premium_plus'`
- Creates Stripe Checkout Session with correct Price ID
- Returns `{ url }` for client redirect

---

## What Uses Existing Schema (No Migrations Needed)

- `profiles` — reads/writes role, uses_primary_addons, name, avatar
- `installed_addons` — reads/writes for addon management
- `invite_codes` — reads/writes for invite generation and redemption
- `collections`, `folders`, `folder_catalogs`, `folder_sources` — reads/writes for catalog CMS

---

## Out of Scope (v2)

- Analytics/usage dashboard
- Email notification preferences
- Two-factor authentication
- Admin activity audit log

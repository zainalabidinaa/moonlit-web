# Nested Collection Folders Design

**Date:** 2026-07-13  
**Status:** Approved for planning

## Goal

Allow a portal-managed folder to contain both child folders and media sources. The
portal order is authoritative and is rendered consistently by the portal, web app,
iOS app, and macOS app.

Example hierarchy:

```text
Genre
└── Horror
    ├── Horror Franchises
    ├── Horror Mood & Vibe
    ├── Popular Horror (media source)
    ├── International Horror
    └── Horror Decades
```

## Data Model

- Add a nullable `parent_folder_id` to `folders`. A `NULL` value denotes a
  collection-root folder; a value denotes a child of that folder.
- A folder's parent must be in the same collection. The database and portal reject
  self-parenting, cycles, and cross-collection moves.
- A folder remains able to own `folder_catalogs` and `folder_sources`, regardless
  of whether it has children.
- Add a shared ordering record (or equivalent ordered child model) keyed by
  `parent_folder_id`. It references either a child folder or one of the parent's
  media-source/catalog entries and owns a single `sort_order`.
- Existing folders migrate with `parent_folder_id = NULL`. Existing source ordering
  is imported into the new ordered-child representation, preserving current output.

## Organizer Contract

- The Supabase organizer endpoint emits the complete folder tree and each folder's
  unified ordered children.
- The existing bundled organizer format is extended compatibly so clients can read
  new hierarchy fields while treating missing fields as today's flat layout.
- Supabase remains the source of truth. Existing organizer caching is retained, but
  every background refresh can replace the cached hierarchy with the latest portal
  state.

## Portal

- A collection starts with its root folders.
- Each folder can create a child folder, attach/edit media sources, move a child,
  and reorder all children together.
- The folder editor shows a single draggable child list where folder and source
  entries can be interleaved.
- A move/reorder is saved atomically. Invalid parent selections and cyclic moves are
  blocked before save and validated server-side.

## Clients

- Root collection rows continue to show collection-root folders.
- Opening a folder renders its unified child list in portal order:
  - folder children navigate to their own folder page;
  - source entries render the existing media rail/card presentation.
- A mixed folder does not need to choose between navigation and media; it supports
  both.
- iOS, macOS, and web share the same resolver/builder rules so ordering and
  visibility match.

## Failure Handling

- If an ordered-child reference is missing, duplicated, malformed, or unavailable,
  clients skip only that entry and render the remaining valid children.
- A malformed remote organizer response falls back to the current valid cached or
  bundled organizer, as it does today.
- The portal surfaces a save error and leaves its local ordering unchanged when the
  transaction fails.

## Verification

- Migration tests: existing flat folders remain root folders and preserve order.
- Resolver tests: nested lookup, mixed source/folder order, and absent references.
- Integrity tests: reject self-parenting, cycles, and cross-collection moves.
- Portal tests: add child, move child, reorder mixed entries, and persist/reload.
- App/web tests: identical organizer fixture yields identical visible root and
  nested child ordering.

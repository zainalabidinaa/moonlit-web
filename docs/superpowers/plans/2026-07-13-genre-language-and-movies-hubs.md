# Genre, Language, and Movies Hubs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface every organizer-backed curated rail in the proper genre, language, or Movies hub without cross-genre leakage.

**Architecture:** Extend the pure `GenreCatalog` resolver with named curated rails, fetch them through `CatalogRepository`, and render them in the existing hub view. Extract language editorial rail definitions to MoonlitCore so they are testable and independent of SwiftUI. Build the Movies curation from organizer categories while leaving specialized content in the dedicated hub.

**Tech Stack:** Swift 6, SwiftUI, XCTest, MoonlitCore organizer/catalog services.

## Global Constraints

- Preserve unrelated worktree changes.
- Use stable rail identifiers and preserve organizer order.
- Keep `Martial Arts` isolated from `Action`.
- Do not add third-party dependencies.

---

### Task 1: Resolve named curated genre rails

**Files:**
- Modify: `Packages/MoonlitCore/Sources/MoonlitCore/Services/GenreCatalog.swift`
- Modify: `Packages/MoonlitCore/Tests/MoonlitCoreTests/GenreCatalogTests.swift`

**Interfaces:**
- Produces `GenreCatalog.BrowseRail` instances with a title and one source per curated catalog.
- Consumes `OrganizedCollections`, `DBFolderCatalog`, and organizer source titles.

- [ ] **Step 1: Write failing tests** for Action named rails and no Martial Arts leakage.
- [ ] **Step 2: Run the focused test** and verify the assertions fail because curated lists are collapsed into `Browse`.
- [ ] **Step 3: Implement ordered standard and curated rail resolution.**
- [ ] **Step 4: Run the focused test** and verify it passes.

### Task 2: Fetch and render curated genre rails

**Files:**
- Modify: `Packages/MoonlitCore/Sources/MoonlitCore/Services/CatalogRepository.swift`
- Modify: `Apps/MoonlitMac/Sources/Screens/MacGenreHubView.swift`

**Interfaces:**
- Consumes `GenreCatalog.browseRails(for:in:)`.
- Produces `HubContent.browse` with standard and curated rails, preserving title/subtitle metadata.

- [ ] **Step 1: Write failing catalog resolver tests** for rail metadata preservation.
- [ ] **Step 2: Run the focused test** and verify it fails.
- [ ] **Step 3: Fetch every resolver rail independently and render its supplied editorial subtitle.**
- [ ] **Step 4: Run the focused tests** and verify they pass.

### Task 3: Build the Movies editorial section

**Files:**
- Modify: `Packages/MoonlitCore/Sources/MoonlitCore/Services/GenreCatalog.swift`
- Modify: `Packages/MoonlitCore/Tests/MoonlitCoreTests/GenreCatalogTests.swift`
- Modify: `Apps/MoonlitMac/Sources/Screens/MacMediaBrowseView.swift`

**Interfaces:**
- Produces `GenreCatalog.movieCuratedRails(in:)` limited to broad movie/editorial lists.
- Keeps specialized lists in their genre hub.

- [ ] **Step 1: Write failing tests** for broad cinema rows and Martial Arts exclusion.
- [ ] **Step 2: Run the focused test** and verify it fails.
- [ ] **Step 3: Implement the resolver and render the resulting rows after default discovery.**
- [ ] **Step 4: Run the focused tests** and verify they pass.

### Task 4: Centralize language editorial profiles

**Files:**
- Create: `Packages/MoonlitCore/Sources/MoonlitCore/Services/LanguageCatalog.swift`
- Create: `Packages/MoonlitCore/Tests/MoonlitCoreTests/LanguageCatalogTests.swift`
- Modify: `Apps/MoonlitMac/Sources/Screens/MacLanguageHubView.swift`

**Interfaces:**
- Produces `LanguageCatalog.railDefinitions(for:)` for known ISO codes and an empty specific profile for unknown languages.
- `MacLanguageHubView` converts definitions to TMDB requests without changing its existing fallback behavior.

- [ ] **Step 1: Write failing tests** for Korean, Arabic, Japanese, and unknown profiles.
- [ ] **Step 2: Run the focused test** and verify it fails because `LanguageCatalog` is missing.
- [ ] **Step 3: Implement language profiles and replace the view-local map.**
- [ ] **Step 4: Run focused tests** and verify they pass.

### Task 5: Verify the integrated feature

**Files:**
- Test: `Packages/MoonlitCore/Tests/MoonlitCoreTests/GenreCatalogTests.swift`
- Test: `Packages/MoonlitCore/Tests/MoonlitCoreTests/LanguageCatalogTests.swift`
- Test: `Apps/MoonlitMac/Tests/MoonlitMacResourceTests.swift`

- [ ] **Step 1: Run MoonlitCore tests.**
- [ ] **Step 2: Build and run MoonlitMac tests.**
- [ ] **Step 3: Inspect the final diff** to ensure only intended files changed.

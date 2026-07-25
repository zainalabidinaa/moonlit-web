# Fix Trending Shows Quality & Coming Soon Sorting

File: `Packages/MoonlitCore/Sources/MoonlitCore/Services/CatalogRepository.swift`

## Change 1: Fix `deduplicated()` to prefer items with release dates (line ~1043)

**Problem:** When `mdblist.26816` and `trakt.anticipated.movies` both return the same movie, deduplication keeps first-seen (mdblist). If mdblist lacks a release date but trakt has it, the undated version wins and gets pushed to the end of the chronological sort.

**Change:** Replace the simple `filter`-based dedup with a loop that, on collision, keeps the version with a non-empty `rawReleaseDate` if only one has it.

```swift
/// Stable dedup by id, preserving first-seen order.
/// When two items share the same id, the one with a non-empty release date wins,
/// so that undated mdblist entries don't replace properly-dated trakt entries on
/// the "Coming Soon" rails.
nonisolated static func deduplicated(_ items: [MetaPreview]) -> [MetaPreview] {
    var result: [MetaPreview] = []
    for item in items {
        if let idx = result.firstIndex(where: { $0.id == item.id }) {
            let existingHasDate = !(result[idx].rawReleaseDate ?? "").isEmpty
            let newHasDate = !(item.rawReleaseDate ?? "").isEmpty
            if newHasDate && !existingHasDate {
                result[idx] = item
            }
        } else {
            result.append(item)
        }
    }
    return result
}
```

## Change 2: Add `filteredByMinimumVoteCount()` (after `sortedByReleaseDateAscending`, line ~1059)

```swift
nonisolated static func filteredByMinimumVoteCount(_ items: [MetaPreview], min: Int) -> [MetaPreview] {
    items.filter { ($0.voteCount ?? 0) >= min }
}
```

## Change 3: Apply trending filter in `loadFromCollections()` (after line 534)

After the "coming soon" sort block, add a "trending" filter block:

```swift
if work.folder.name.localizedCaseInsensitiveContains("trending") {
    items = Self.filteredByMinimumVoteCount(items, min: 50)
}
```

Full section (lines 532-535 become):

```swift
                    var items = Self.deduplicated(buckets.keys.sorted().flatMap { buckets[$0] ?? [] })
                    if work.folder.name.localizedCaseInsensitiveContains("coming soon") {
                        items = Self.sortedByReleaseDateAscending(items)
                    }
                    if work.folder.name.localizedCaseInsensitiveContains("trending") {
                        items = Self.filteredByMinimumVoteCount(items, min: 50)
                    }
```

## Change 4: Add `filterByVoteCount` to `fetchFolderItems()` (lines 1013-1041)

Add the parameter and apply it alongside the release date sort:

```swift
    private func fetchFolderItems(
        normalizedSources: [DBFolderCatalog],
        rawSources: [DBFolderSource],
        fallbackURL: String,
        addons: [AddonManifest],
        skip: Int,
        sortByReleaseDate: Bool = false,
        filterByVoteCount: Bool = false
    ) async -> [MetaPreview] {
```

And change the return (line ~1040):

```swift
        let merged = Self.deduplicated(buckets.keys.sorted().flatMap { buckets[$0] ?? [] })
        var result = sortByReleaseDate ? Self.sortedByReleaseDateAscending(merged) : merged
        if filterByVoteCount {
            result = Self.filteredByMinimumVoteCount(result, min: 50)
        }
        return result
```

## Change 5: Update call site in `loadOnDemandFolder()` (lines 851-858)

Add the new parameter:

```swift
        let items = await fetchFolderItems(
            normalizedSources: normalizedSources,
            rawSources: rawSources,
            fallbackURL: fallbackURL,
            addons: addons,
            skip: 0,
            sortByReleaseDate: folder.name.localizedCaseInsensitiveContains("coming soon"),
            filterByVoteCount: folder.name.localizedCaseInsensitiveContains("trending")
        )
```

## Verification

Run existing tests:

```bash
swift test --filter CatalogOrderingTests
```

The test `testDeduplicatesByIdPreservingFirstSeenOrder` uses items that all have dates, so dedup behavior is unchanged for same-date duplicates. The existing `testSortsSoonestReleaseFirst` and `testTiesKeepSourceOrderMdblistBeforeTrakt` are unaffected.

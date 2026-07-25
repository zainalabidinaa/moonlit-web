# Genre, Language, and Movies Hubs Design

## Goal

Make catalog metadata visible in the correct browse surface: curated genre lists in their dedicated genre hub, language-specific discovery in the language hub, and broad cinema lists in Movies.

## Decisions

- Genre hubs render the standard discovery rails, then every catalog source explicitly attached to that genre folder as an individually named curated rail. They retain subgenre, franchise, decade, and collection tiles.
- Martial Arts is a standalone genre. Its Bruce Lee, Jackie Chan, Hollywood Martial Arts, and Top 250 rails must not appear under Action.
- Movies renders general discovery, curated cinema rows, decade/group tiles, and film-collection tiles. Specialized genre identity lists stay in their genre hubs.
- Language hubs retain TMDB discovery as their reliable base and use a centralized language profile for regional/editorial rails. AIOMetadata contributes a featured rail only when a source carries a usable language signal.
- Adult-oriented Romance sources, including Mega Erotic, belong to Romance. Profile gating is intentionally outside this change because the existing catalog profile policy is not represented in hub data.

## Architecture

`GenreCatalog` becomes the pure resolver for both baseline genre browse rails and named curated genre rails. It derives titles from organizer source titles when present, otherwise from a catalog-title lookup for bundled IDs. `CatalogRepository` fetches each resolved rail independently. `MacGenreHubView` displays the returned rail section with its supplied subtitle.

`MacMediaBrowseView` receives a Movies-only curated section composed from organizer folders/categories; it keeps its current TMDB discovery top section and collection tiles. `MacLanguageHubView` keeps its current TMDB-backed implementation but moves language editorial definitions to a dedicated, testable core resolver.

## Validation

- Unit tests prove curated sources resolve one rail each, standard sources still merge by category, and Martial Arts never leaks into Action.
- Unit tests prove explicit language profiles are selected and unknown languages use the general profile.
- Build and run the MoonlitCore test target and the MoonlitMac test target.

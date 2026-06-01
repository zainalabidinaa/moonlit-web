# LunaWebV2 Player Repair Design

## Goal
Restore reliable stream playback in LunaWebV2 and align the player controls, loading state, subtitles/audio panel, Continue Watching labels, and sources panel with the requested Netflix/Stremio references.

## Scope
- Fix direct/debrid stream playback by selecting the correct media source type before Vidstack loads.
- Keep HLS behavior and proxy-header support for HLS streams.
- Add the OpenSubtitles v3 Pro addon as the preferred subtitle source while keeping the public OpenSubtitles addon as fallback.
- Make the speaker icon mute/unmute, keep a visible volume slider, and make the subtitles icon open an Audio + Subtitles panel.
- Replace spinner-first source loading with a Stremio-like source/logo loading overlay.
- Repair Continue Watching series labels so old entries with IDs like `tt9813792:1:2` display a readable series title plus episode number.
- Redesign the sources panel into a compact Stremio-style right rail.

## Architecture
Keep the changes localized to LunaWebV2. Extract small pure helpers for stream URL type detection, stream matching, and Continue Watching title formatting so the highest-risk playback/title behavior is testable without rendering Vidstack. The visual changes remain inside the existing player and route components to avoid broad restructuring.

## UI Direction
The control bar should follow the Netflix screenshots: larger bottom controls, visible volume slider, and a large Audio + Subtitles panel. The sources/loading UI should follow Stremio: compact dark right panel, provider/source labels, quality/size metadata, and a subtle progress/pulse instead of a dominant spinner.

## Testing
Add Vitest coverage for helper behavior:
- HLS URLs resolve to `application/x-mpegurl`.
- Direct video/debrid URLs resolve to `video/mp4`/generic direct video instead of HLS.
- Cached stream lookup matches `externalUrl` as well as `url`.
- Series Continue Watching labels produce readable episode titles from `tt...:season:episode` IDs.

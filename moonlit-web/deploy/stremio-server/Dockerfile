# Remux/transcode server for Moonlit — the official Stremio streaming server.
# Remuxes MKV → HLS and transcodes incompatible audio (E-AC3 → AAC) on the fly
# so any debrid stream plays in the browser.
#
# Railway/Render build this Dockerfile. It's just the official image with the
# CORS gate opened (Moonlit calls it cross-origin from the Vercel domain).
FROM stremio/server:latest

ENV NO_CORS=1

# Stremio server listens on 11470 (http). Railway/Render terminate TLS in front.
EXPOSE 11470

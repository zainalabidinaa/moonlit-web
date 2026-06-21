# Moonlit Remux Server (Stremio streaming server)

This is the piece that makes **any** stream play in the browser. Browsers can't
play the MKV container (most high-quality debrid streams are MKV), so we run the
official Stremio streaming server, which remuxes MKV → HLS and transcodes
incompatible audio (E-AC3 → AAC) on the fly. Moonlit routes incompatible streams
through it; streams that already play in the browser skip it entirely.

Image: [`stremio/server`](https://hub.docker.com/r/stremio/server) · listens on **11470** (http).
Moonlit is HTTPS, so the server **must** be served over HTTPS — Railway and Render
both terminate TLS for you automatically.

---

## Option A — Railway (recommended for ease)

1. Push this repo to GitHub (already done).
2. [railway.app](https://railway.app) → **New Project** → **Deploy from GitHub repo** → pick `moonlit-web`.
3. Railway reads `deploy/stremio-server/railway.json` and builds the Dockerfile.
   - If it builds the wrong service, set **Root Directory** = `deploy/stremio-server`.
4. **Settings → Networking → Generate Domain.** Set the **target port to `11470`**.
5. Copy the URL, e.g. `https://moonlit-stremio-server.up.railway.app`.
6. Open Moonlit → **Settings → Streaming server** → paste the URL → **Test connection**.

## Option B — Render

1. [render.com](https://render.com) → **New + → Blueprint** → pick this repo.
   It reads `deploy/stremio-server/render.yaml`.
   (Or **New + → Web Service → Existing image** → `stremio/server:latest`.)
2. If the port isn't detected: service → **Settings → Docker → Port = `11470`**.
3. Add env var `NO_CORS=1` (the blueprint already sets it).
4. Copy the URL, e.g. `https://moonlit-stremio-server.onrender.com`.
   - Free tier cold-starts (~30–50s on first play after idle). Use **Starter** ($7/mo) to keep it warm.
5. Open Moonlit → **Settings → Streaming server** → paste the URL → **Test connection**.

---

## Verify the server works

```bash
# Should return JSON with server settings/version
curl https://<your-server-url>/settings

# Probe a real stream (should return track/format info, not an error)
curl "https://<your-server-url>/hlsv2/probe?mediaURL=https%3A%2F%2Fcomet.elfhosted.com%2Fplayback%2F...%3Fname%3DFrom"
```

Once `Test connection` is green in Moonlit Settings, play the title that was stuck
before — the Network tab should show a request to `/hlsv2/.../master.m3u8` and
the video plays with audio.

## Cost note

Every **remuxed** stream proxies the full file through this server (a 3.6 GB movie
= 3.6 GB egress). Streams that already play in the browser bypass it, so cost
scales only with how much incompatible (MKV/E-AC3/HEVC) content you watch. Watch
egress billing on Railway/Render; if it gets heavy, move to a VPS with included
bandwidth (Hetzner) — same Docker image, just add Caddy for HTTPS.

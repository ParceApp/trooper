# Trooper Architecture Flow: Minimalist Animation & Video Renderer

Dieses Modul visualisiert und animiert den reaktiven Datenfluss und die SWR-Cache-Architektur von Trooper im minimalistischen Stil des Bloc-READMEs:

```text
┌──────────────┐          .get()          ┌──────────────┐        fetch()         ┌──────────────┐
│  Flutter UI  │ ───────────────────────> │   Trooper    │ ─────────────────────> │  Remote API  │
│ (Widget)     │ <─────────────────────── │ (SWR Engine) │ <───────────────────── │ (REST / GQL) │
└──────────────┘       StatefulData       └──────────────┘         200 OK         └──────────────┘
```

---

## 1. Visualisierte Kernphasen

Die Animation führt durch 3 kompakte, selbsterklärende Schritte:

1. **Phase 1: Cold Start (Cache Miss & Initial Fetch)**:
   - Die UI sendet `.get()`.
   - Trooper stellt `MISS` im L1-Memory-Cache fest und emittiert sofort `DataLoading()`.
   - Trooper fordert die Daten von der `Remote API` an (`fetch()`).
   - Die API antwortet (`200 OK`).
   - Trooper speichert die Daten im L1-Cache (TTL: 5m) und emittiert `DataLoaded(Data)` zur UI.

2. **Phase 2: Subsequent Request (Instant L1 Cache Hit in 0ms)**:
   - Die UI ruft `.get()` erneut auf.
   - Trooper bedient die Anfrage sofort aus dem L1-Memory-Cache: ⚡ `0ms Hit`.
   - Die `Remote API` bleibt vollkommen unberührt (0 Netzwerkaufrufe).

3. **Phase 3: Stale-While-Revalidate (Zero-Flicker Background Update)**:
   - Die TTL läuft ab: Der L1-Cache-Eintrag wird `STALE`.
   - Bei der nächsten Anfrage liefert Trooper der UI **sofort** den Zustand `DataRefreshing(Data)`.
   - **Zero-Flicker-Garantie**: Weil `DataRefreshing<T>` von `DataLoaded<T>` erbt, bleibt der vorherige Datenbestand auf dem Bildschirm voll erhalten (kein Lade-Spinner, kein Layout-Shift).
   - Im Hintergrund holt Trooper die frischen Daten von der `Remote API`.
   - Sobald die Antwort da ist, aktualisiert Trooper die UI lautlos auf `DataLoaded(Fresh v2)`.

---

## 2. Dateien

- [`index.html`](file:///Users/hannes/Developer/trooper/docs/animation/index.html): Standalone-Bannerwebseite (880x280) im Dark-Mode Glassmorphism-Design.
- [`style.css`](file:///Users/hannes/Developer/trooper/docs/animation/style.css): Minimalistisches Styling mit Leuchtpartikeln und Richtungsmarkierungen.
- [`app.js`](file:///Users/hannes/Developer/trooper/docs/animation/app.js): Zeitgesteuerte 3-Phasen-Animations-Engine.
- [`render.js`](file:///Users/hannes/Developer/trooper/docs/animation/render.js): Automatisierter Headless-Chrome & FFmpeg-Renderer.
- [`trooper_architecture_flow.mp4`](file:///Users/hannes/Developer/trooper/docs/animation/trooper_architecture_flow.mp4): Gerendertes MP4-Video (ca. 950 KB).
- [`trooper_architecture_flow.gif`](file:///Users/hannes/Developer/trooper/docs/animation/trooper_architecture_flow.gif): Optimiertes animiertes GIF (ca. 1.7 MB, perfekt für GitHub README).

---

## 3. Ausführung & Rendering

### Webseite lokal im Browser öffnen
```bash
open docs/animation/index.html
```

### Video und GIF neu rendern
```bash
cd docs/animation
npm run render
```

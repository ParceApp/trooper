# Trooper Architecture Flow: Animation & Video Renderer

Dieses Modul visualisiert und animiert den reaktiven Datenfluss, das Caching und die Concurrency-Architektur des Trooper-Frameworks.

---

## 1. Visualisierte Phasen (Architektur-Flow)

Die Animation simuliert in einem zusammenhängenden Kreislauf 4 Kernaspekte von Trooper:

1. **Phase 1: Cold Start & Cache Miss**:
   - Die UI fordert Daten an: `userProfile.get((id: 42))`.
   - `TrooperController` leitet die Anfrage an `TrooperQuery` weiter.
   - L1-Cache liefert `MISS`.
   - UI wechselt auf `DataLoading` (Skeleton Shimmer).
   - `TrooperQueryQueue` sendet die Netzwerkanfrage an die REST-API.
   - Nach erfolgreichem Empfang wird das Ergebnis im L1 `CacheStore` (TTL: 5m) gespeichert und asynchron im L2 `StorageBackend` via `StorageEnvelope` persistiert.
   - UI erhält `DataLoaded` (Grüner Status, Daten sichtbar).

2. **Phase 2: Instant Cache Hit (0ms / Zero Network)**:
   - Die UI fragt dieselben Daten erneut ab.
   - Der Aufruf wird sofort und ohne Netzwerkanfrage direkt aus dem L1-Memory-Cache bedient.
   - UI zeigt den Blitz-Status `⚡ 0ms (L1 Hit)`.

3. **Phase 3: SWR Revalidation (Zero-Flicker Background Update)**:
   - Die TTL läuft ab: Der L1-Cache-Eintrag wird `STALE` (Amber).
   - Bei der nächsten Anfrage erhält die UI **sofort** den Zustand `DataRefreshing<T>`.
   - **Zero-Flicker-Garantie**: Weil `DataRefreshing<T>` von `DataLoaded<T>` erbt, bleibt der vorherige Datenbestand auf der UI vollständig sichtbar.
   - Im Hintergrund läuft der Revalidierungs-Fetch zur API.
   - Nach erfolgreichem Hintergrundabruf wird der Cache erneuert und die UI lautlos auf die frischen Daten aktualisiert.

4. **Phase 4: Concurrency Coalescing (Stampede Protection)**:
   - 3 UI-Komponenten rufen zeitgleich dieselbe Abfrage auf (Cache Stampede).
   - `TrooperQueryQueue` bündelt alle 3 Aufrufer in **eine einzige** laufende Netzwerk-Anfrage.
   - Die API sieht nur 1 Request.
   - Das Ergebnis wird zeitgleich an alle 3 Aufrufer verteilt (66% Netzwerklast eingespart).

---

## 2. Dateien

- [`index.html`](file:///Users/hannes/Developer/trooper/docs/animation/index.html): Standalone-Webseite (HTML5) mit interaktiver Steuerung (Play/Pause, Step, Speed, Restart).
- [`style.css`](file:///Users/hannes/Developer/trooper/docs/animation/style.css): Modernes Dark-Mode Glassmorphism-Design mit CSS-Variablen und Glow-Effekten.
- [`app.js`](file:///Users/hannes/Developer/trooper/docs/animation/app.js): Zeitgesteuerte Animations-Engine mit Partikelfluss über SVG-Pfade und Live-Telemetrie.
- [`render.js`](file:///Users/hannes/Developer/trooper/docs/animation/render.js): Automatisierter Headless-Chrome & FFmpeg-Renderer.
- [`trooper_architecture_flow.mp4`](file:///Users/hannes/Developer/trooper/docs/animation/trooper_architecture_flow.mp4): Gerendertes Full-HD / 720p H.264 Video.
- [`trooper_architecture_flow.gif`](file:///Users/hannes/Developer/trooper/docs/animation/trooper_architecture_flow.gif): Optimiertes animiertes GIF (mit FFmpeg Palettegen).

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

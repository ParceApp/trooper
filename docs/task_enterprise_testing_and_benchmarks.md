# Aufgabe: Enterprise-Ready Testing, Edge-Case-Absicherung & Benchmarking

### Status: Umgesetzt und abgeschlossen

---

## 1. Zielsetzung & Problemstellung
Als Architektur- und State-Management-Framework fuer mittlere bis grosse Enterprise-Anwendungen benoetigt Trooper eine robuste, regressionssichere und performante Test- und Benchmark-Suite.

Im Verzeichnis [`packages/trooper`](file:///Users/hannes/Developer/trooper/packages/trooper) wurde eine umfassende Test- und Benchmark-Architektur aufgebaut:
1. **Enterprise-Ready Unit- & Integration-Tests** fuer alle Kernkomponenten.
2. **Kritische Edge-Case- & Concurrency-Szenarien** (Cache-Stampedes, Out-of-Order-Events, Token-Cancellations, Memory-Leaks).
3. **Benchmark-Suite** zur quantitativen Messung von Durchsatz, Latenz und Speicherverbrauch.

---

## 2. Testarchitektur & Test-Infrastruktur

### A. Test-Harness & Mocks ([`packages/trooper/test/fixtures/`](file:///Users/hannes/Developer/trooper/packages/trooper/test/fixtures/))
- [x] **`MockStorageBackend`**: Schneller In-Memory-Storage mit optionaler kuenstlicher Latenz und simulierten I/O-Fehlern.
- [x] **`TestApiClient`**: Simulierter REST/GraphQL-Endpunkt mit Zaehlern fuer Netzwerk-Hits, konfigurierbarer Verzoegerung und Fehlerinjektion.
- [x] **`MockStreamSource`**: Kontrollierbare Upstream-Streams (WebSocket-Simulation) fuer Push-Events, Verbindungsabbrueche und Reconnects.
- [x] **`FakeAsync`-Integration**: Deterministisches Testen von TTL-Ablauf, Sweeps und Delays ohne echte `sleep`-Zeiten.

---

## 3. Test-Module & Anwendungsfaelle

### Modul 1: `TrooperQuery` & SWR Caching ([`test/core/trooper_query_test.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/test/core/trooper_query_test.dart))
- [x] **Cache-Hit**: Zweiter Aufruf liefert synchron/sofort aus L1-Cache, 0 Netzwerkaufrufe.
- [x] **SWR (Stale-While-Revalidate)**:
  - Nach TTL-Ablauf liefert `get()` sofort alte Daten mit `DataRefreshing`.
  - Hintergrund-Fetch wird automatisch angestossen und emittiert bei Erfolg frische `DataLoaded`-Daten.
  - UI behaelt Daten waehrend des gesamten Revalidierungsvorgangs (Zero-Flicker-Garantie).
- [x] **Request-Deduplication (Coalescing)**:
  - 50 simultane Aufrufe teilen sich exakt einen einzigen Netzwerkaufruf.
  - Alle 50 Caller erhalten das identische Ergebnis.
- [x] **Konflikt-Strategien (`QueryConflictPolicy`)**:
  - `cancel`: Vorheriger Request wird via Token abgebrochen, alter Caller erhaelt `TrooperCancelledException`.
  - `forward`: Vorheriger Request wird abgebrochen, alter Caller wartet nahtlos auf das Ergebnis des neuen Requests.
  - `parallel`: Beide Requests laufen parallel, geschuetzt durch Sequence-IDs gegen Out-of-Order-Ueberschreibungen.
- [x] **L2-Storage & `StorageEnvelope`**:
  - Persistierung und Wiederherstellung nach simuliertem App-Neustart.
  - Pruefung auf Frische: Frische Daten werden sofort geladen.
  - Pruefung auf Ablauf: Bei `keepStaleWhileRevalidate` sofort als `DataRefreshing` emittiert; bei `discardStaleOnRefresh` verworfen.

### Modul 2: `KeyedTrooperQuery` ([`test/core/keyed_trooper_query_test.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/test/core/keyed_trooper_query_test.dart))
- [x] **Key-Isolation**: Aktionen auf Key `A` beeinflussen den Cache und Stream von Key `B` nicht.
- [x] **Batch-Lesen (`getMany`)**: Paralleles Laden mehrerer Keys mit aggregierter Rueckgabe.
- [x] **Bound Accessor (`operator []`)**: Subscript-Zugriff liefert vollwertigen, funktionsfaehigen `Accessor`.
- [x] **Loeschen & Invalidieren**: `removeKey` und `invalidateKey` leeren Cache, Storage und Stream fuer den spezifischen Key.

### Modul 3: `LocalTrooper` & `KeyedLocalTrooper` ([`test/core/local_trooper_test.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/test/core/local_trooper_test.dart))
- [x] **Synchrones Update**: `set` und `update` aktualisieren den In-Memory-Zustand sofort und emittieren auf den Stream.
- [x] **Reset**: Zuruecksetzen auf `initialValue`.
- [x] **L2-Synchronisation**: Asynchrones Schreiben in den Storage bei Aenderungen; Initialisierung aus Storage bei App-Start.

### Modul 4: `StreamTrooper` & `KeyedStreamTrooper` ([`test/core/stream_trooper_test.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/test/core/stream_trooper_test.dart))
- [x] **Automatischer Lifecycle (`keepAlive: false`)**:
  - Verbindung oeffnet sich beim ersten `watch()`-Listener.
  - Verbindung trennt sich automatisch, sobald der letzte Listener unsubscribet.
- [x] **`keepAlive: true`**: Verbindung bleibt auch ohne aktive UI-Listener bestehen.
- [x] **Query-artiges Verhalten (`get`)**:
  - `get()` liest frische Daten aus L1/L2 oder wartet auf den naechsten Upstream-Frame.
  - Manuelle `set()`-Aufrufe persistieren in L2 via `StorageEnvelope`.
- [x] **Fehlerbehandlung & Reconnect**: Automatischer Verbindungsaufbau nach Verbindungsverlust.

### Modul 5: `TrooperMutation` ([`test/core/trooper_mutation_test.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/test/core/trooper_mutation_test.dart))
- [x] **FIFO-Queueing**: Schnelle aufeinanderfolgende Aufrufe werden sequentiell in exakter Reihenfolge abgearbeitet.
- [x] **Automatische Invalidation**: `invalidateOnSuccess` invalidiert verknuepfte Queries oder Controller nach erfolgreicher Ausfuehrung.
- [x] **Fehler-Isolation**: Fehler in Mutation 1 brechen die Ausfuehrung ab, blockieren jedoch nicht nachfolgende Mutationen in der Queue.

### Modul 6: `TrooperController` ([`test/controller/trooper_controller_test.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/test/controller/trooper_controller_test.dart))
- [x] **Hierarchischer Lifecycle**:
  - `initialize()` initialisiert alle gemanagten Children.
  - `pause()` und `resume()` pausieren/reaktivieren Cache-Sweeps und Stream-Verbindungen.
  - `recover()` triggert automatische Wiederherstellung aller fehlerhaften Children.
  - `dispose()` schliesst alle Children, Streams und Queues sauber.
- [x] **Service-Sharing**: Shared CacheStore, Shared QueryQueue und Shared TelemetryHub werden vererbt, aber bei individuellem Child-Dispose nicht versehentlich zerstoert.
- [x] **Deklarative Verknuepfungen**: `extraInvalidatables` und `extraLifecycleChildren` werden bei Lifecycle-Events mit angesteuert.

### Modul 7: Concurrency & Primitives ([`test/concurrency/`](file:///Users/hannes/Developer/trooper/packages/trooper/test/concurrency/))
- [x] **`TrooperCancelToken`**: Listener-Registrierung, idempotente Cancellation, Callback-Teardown.
- [x] **`TrooperQueryQueue`**: Request-Coalescing, Priority, Namespace-Cancellation.
- [x] **`TrooperMutationQueue`**: FIFO-Garantie, Concurrency-Safety.
- [x] **`CacheStore`**: TTL-Eviction, Proactive-Sweep, LRU/Map-Stabilitaet.
- [x] **`StorageEnvelope`**: Robustheit gegen korrupte JSON-Payloads (`tryDecode` gibt null zurueck).

---

## 4. Kritische Edge-Case- & Stress-Tests

- [x] **Cache Stampede**: 500 gleichzeitige asynchrone Tasks greifen auf denselben abgelaufenen QueryKey zu. Es darf nur genau ein Netzwerk-Request abgesetzt werden.
- [x] **Out-of-Order Network Arrival**: Langsame Requests mit altem Zeitstempel duerfen schnellere neuere Ergebnisse nicht ueberschreiben.
- [x] **Disposal waehrend in-flight Requests**: Ein Controller wird disposed, waehrend 20 Queries noch Daten laden. Es duerfen keine `Unhandled Exception` oder Speicherlecks auftreten.
- [x] **I/O Storage Failure**: Das `StorageBackend` wirft `FileSystemException` (Festplatte voll). Das System faellt gracefully auf reines In-Memory-Caching zurueck, ohne abzustuerzen.
- [x] **Listener Churn**: 1000 wiederholte `listen()`- und `cancel()`-Vorgaenge in kurzen Abstaenden. StreamController und Memory duerfen nicht leaken.

---

## 5. Benchmarking Suite ([`packages/trooper/benchmark/`](file:///Users/hannes/Developer/trooper/packages/trooper/benchmark/))

- [x] **L1 Cache-Hit Durchsatz**: Messung von Operationen pro Sekunde bei reinem Memory-Cache-Lesen (Ergebnis: > 28.000.000 Ops/sec).
- [x] **Request-Coalescing Overhead**: Zeitverlust durch Queueing und Completer-Verwaltung bei hoher Last (Ergebnis: ~7.15 µs Overhead pro Caller).
- [x] **StatefulStream Durchsatz**: Zeit von der Event-Emission bis zur Ausfuehrung im Listener bei 10.000 Events (Ergebnis: > 700.000 Events/sec).
- [x] **Speicher-Footprint**: RAM-Verbrauch bei 10.000 aktiven Keys in `KeyedTrooperQuery` (Ergebnis: ~9.59 MB total, ~1006 Bytes/Key).
- [x] **Ausfuehrbares Benchmark-Skript**: CLI-Skript `dart run benchmark/trooper_benchmark.dart` mit formatierter Tabellenausgabe.

---

## 6. Akzeptanzkriterien
1. **100% Pass-Rate**: Alle Tests laufen deterministisch durch (`dart test`), ohne Flakiness und ohne Timeouts.
2. **0 Unhandled Async Errors**: Keine ungefangenen Exceptions in isolierten Zonen oder unhandled Futures.
3. **Reproduzierbare Benchmarks**: Das Benchmark-Skript laeuft fehlerfrei durch und gibt standardisierte Kennzahlen aus.

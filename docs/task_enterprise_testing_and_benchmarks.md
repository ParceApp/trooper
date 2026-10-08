# Aufgabe: Enterprise-Ready Testing, Edge-Case-Absicherung & Benchmarking

### Status: Offen

---

## 1. Zielsetzung & Problemstellung
Als Architektur- und State-Management-Framework für mittlere bis große Enterprise-Anwendungen benötigt Trooper eine robuste, regressionssichere und performante Test- und Benchmark-Suite.

Aktuell existieren im Verzeichnis [`packages/trooper`](file:///Users/hannes/Developer/trooper/packages/trooper) noch keine Testdateien.

Ziel dieser Aufgabe ist der Aufbau einer umfassenden Testarchitektur:
1. **Enterprise-Ready Unit- & Integration-Tests** für alle Kernkomponenten.
2. **Kritische Edge-Case- & Concurrency-Szenarien** (Cache-Stampedes, Out-of-Order-Events, Token-Cancellations, Memory-Leaks).
3. **Benchmark-Suite** zur quantitativen Messung von Durchsatz, Latenz und Speicherverbrauch.

---

## 2. Testarchitektur & Test-Infrastruktur

### A. Test-Harness & Mocks ([`packages/trooper/test/fixtures/`](file:///Users/hannes/Developer/trooper/packages/trooper/test/fixtures/))
- [ ] **`MockStorageBackend`**: Schneller In-Memory-Storage mit optionaler künstlicher Latenz und simulierten I/O-Fehlern.
- [ ] **`TestApiClient`**: Simulierter REST/GraphQL-Endpunkt mit Zählern für Netzwerk-Hits, konfigurierbarer Verzögerung und Fehlerinjektion.
- [ ] **`MockStreamSource`**: Kontrollierbare Upstream-Streams (WebSocket-Simulation) für Push-Events, Verbindungsabbrüche und Reconnects.
- [ ] **`FakeAsync`-Integration**: Deterministisches Testen von TTL-Ablauf, Sweeps und Delays ohne echte `sleep`-Zeiten.

---

## 3. Test-Module & Anwendungsfälle

### Modul 1: `TrooperQuery` & SWR Caching ([`test/core/trooper_query_test.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/test/core/trooper_query_test.dart))
- [ ] **Cache-Hit**: Zweiter Aufruf liefert synchron/sofort aus L1-Cache, 0 Netzwerkaufrufe.
- [ ] **SWR (Stale-While-Revalidate)**:
  - Nach TTL-Ablauf liefert `get()` sofort alte Daten mit `DataRefreshing`.
  - Hintergrund-Fetch wird automatisch angestoßen und emittiert bei Erfolg frische `DataLoaded`-Daten.
  - UI behält Daten während des gesamten Revalidierungsvorgangs (Zero-Flicker-Garantie).
- [ ] **Request-Deduplication (Coalescing)**:
  - 50 simultane Aufrufe teilen sich exakt einen einzigen Netzwerkaufruf.
  - Alle 50 Caller erhalten das identische Ergebnis.
- [ ] **Konflikt-Strategien (`QueryConflictPolicy`)**:
  - `cancel`: Vorheriger Request wird via Token abgebrochen, alter Caller erhält `TrooperCancelledException`.
  - `forward`: Vorheriger Request wird abgebrochen, alter Caller wartet nahtlos auf das Ergebnis des neuen Requests.
  - `parallel`: Beide Requests laufen parallel, geschützt durch Sequence-IDs gegen Out-of-Order-Überschreibungen.
- [ ] **L2-Storage & `StorageEnvelope`**:
  - Persistierung und Wiederherstellung nach simuliertem App-Neustart.
  - Prüfung auf Frische: Frische Daten werden sofort geladen.
  - Prüfung auf Ablauf: Bei `keepStaleWhileRevalidate` sofort als `DataRefreshing` emittiert; bei `discardStaleOnRefresh` verworfen.

### Modul 2: `KeyedTrooperQuery` ([`test/core/keyed_trooper_query_test.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/test/core/keyed_trooper_query_test.dart))
- [ ] **Key-Isolation**: Aktionen auf Key `A` beeinflussen den Cache und Stream von Key `B` nicht.
- [ ] **Batch-Lesen (`getMany`)**: Paralleles Laden mehrerer Keys mit aggregierter Rückgabe.
- [ ] **Bound Accessor (`operator []`)**: Subscript-Zugriff liefert vollwertigen, funktionsfähigen `Accessor`.
- [ ] **Löschen & Invalidieren**: `removeKey` und `invalidateKey` leeren Cache, Storage und Stream für den spezifischen Key.

### Modul 3: `LocalTrooper` & `KeyedLocalTrooper` ([`test/core/local_trooper_test.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/test/core/local_trooper_test.dart))
- [ ] **Synchrones Update**: `set` und `update` aktualisieren den In-Memory-Zustand sofort und emittieren auf den Stream.
- [ ] **Reset**: Zurücksetzen auf `initialValue`.
- [ ] **L2-Synchronisation**: Asynchrones Schreiben in den Storage bei Änderungen; Initialisierung aus Storage bei App-Start.

### Modul 4: `StreamTrooper` & `KeyedStreamTrooper` ([`test/core/stream_trooper_test.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/test/core/stream_trooper_test.dart))
- [ ] **Automatischer Lifecycle (`keepAlive: false`)**:
  - Verbindung öffnet sich beim ersten `watch()`-Listener.
  - Verbindung trennt sich automatisch, sobald der letzte Listener unsubscribet.
- [ ] **`keepAlive: true`**: Verbindung bleibt auch ohne aktive UI-Listener bestehen.
- [ ] **Query-artiges Verhalten (`get`)**:
  - `get()` liest frische Daten aus L1/L2 oder wartet auf den nächsten Upstream-Frame.
  - Manuelle `set()`-Aufrufe persistieren in L2 via `StorageEnvelope`.
- [ ] **Fehlerbehandlung & Reconnect**: Automatischer Verbindungsaufbau nach Verbindungsverlust.

### Modul 5: `TrooperMutation` ([`test/core/trooper_mutation_test.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/test/core/trooper_mutation_test.dart))
- [ ] **FIFO-Queueing**: Schnelle aufeinanderfolgende Aufrufe werden sequentiell in exakter Reihenfolge abgearbeitet.
- [ ] **Automatische Invalidation**: `invalidateOnSuccess` invalidiert verknüpfte Queries oder Controller nach erfolgreicher Ausführung.
- [ ] **Fehler-Isolation**: Fehler in Mutation 1 brechen die Ausführung ab, blockieren jedoch nicht nachfolgende Mutationen in der Queue.

### Modul 6: `TrooperController` ([`test/controller/trooper_controller_test.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/test/controller/trooper_controller_test.dart))
- [ ] **Hierarchischer Lifecycle**:
  - `initialize()` initialisiert alle gemanagten Children.
  - `pause()` und `resume()` pausieren/reaktivieren Cache-Sweeps und Stream-Verbindungen.
  - `recover()` triggert automatische Wiederherstellung aller fehlerhaften Children.
  - `dispose()` schließt alle Children, Streams und Queues sauber.
- [ ] **Service-Sharing**: Shared CacheStore, Shared QueryQueue und Shared TelemetryHub werden vererbt, aber bei individuellem Child-Dispose nicht versehentlich zerstört.
- [ ] **Deklarative Verknüpfungen**: `extraInvalidatables` und `extraLifecycleChildren` werden bei Lifecycle-Events mit angesteuert.

### Modul 7: Concurrency & Primitives ([`test/concurrency/`](file:///Users/hannes/Developer/trooper/packages/trooper/test/concurrency/))
- [ ] **`TrooperCancelToken`**: Listener-Registrierung, idempotente Cancellation, Callback-Teardown.
- [ ] **`TrooperQueryQueue`**: Request-Coalescing, Priority, Namespace-Cancellation.
- [ ] **`TrooperMutationQueue`**: FIFO-Garantie, Concurrency-Safety.
- [ ] **`CacheStore`**: TTL-Eviction, Proactive-Sweep, LRU/Map-Stabilität.
- [ ] **`StorageEnvelope`**: Robustheit gegen korrupte JSON-Payloads (`tryDecode` gibt null zurück).

---

## 4. Kritische Edge-Case- & Stress-Tests

- [ ] **Cache Stampede**: 500 gleichzeitige asynchrone Tasks greifen auf denselben abgelaufenen QueryKey zu. Es darf nur genau ein Netzwerk-Request abgesetzt werden.
- [ ] **Out-of-Order Network Arrival**: Langsame Requests mit altem Zeitstempel dürfen schnellere neuere Ergebnisse nicht überschreiben.
- [ ] **Disposal während in-flight Requests**: Ein Controller wird disposed, während 20 Queries noch Daten laden. Es dürfen keine `Unhandled Exception` oder Speicherlecks auftreten.
- [ ] **I/O Storage Failure**: Das `StorageBackend` wirft `FileSystemException` (Festplatte voll). Das System fällt gracefully auf reines In-Memory-Caching zurück, ohne abzustürzen.
- [ ] **Listener Churn**: 1000 wiederholte `listen()`- und `cancel()`-Vorgänge in kurzen Abständen. StreamController und Memory dürfen nicht leaken.

---

## 5. Benchmarking Suite ([`packages/trooper/benchmark/`](file:///Users/hannes/Developer/trooper/packages/trooper/benchmark/))

- [ ] **L1 Cache-Hit Durchsatz**: Messung von Operationen pro Sekunde bei reinem Memory-Cache-Lesen (Ziel: > 1.000.000 Ops/sec).
- [ ] **Request-Coalescing Overhead**: Zeitverlust durch Queueing und Completer-Verwaltung bei hoher Last (Ziel: < 0.05ms Overhead pro Aufruf).
- [ ] **StatefulStream Durchsatz**: Zeit von der Event-Emission bis zur Ausführung im Listener bei 10.000 Events.
- [ ] **Speicher-Footprint**: RAM-Verbrauch bei 10.000 aktiven Keys in `KeyedTrooperQuery` (inkl. TTL und Metadaten).
- [ ] **Ausführbares Benchmark-Skript**: CLI-Skript `dart run benchmark/trooper_benchmark.dart` mit formatierter Tabellenausgabe.

---

## 6. Akzeptanzkriterien
1. **100% Pass-Rate**: Alle Tests laufen deterministisch durch (`dart test`), ohne Flakiness und ohne Timeouts.
2. **0 Unhandled Async Errors**: Keine ungefangenen Exceptions in isolierten Zonen oder unhandled Futures.
3. **Reproduzierbare Benchmarks**: Das Benchmark-Skript läuft fehlerfrei durch und gibt standardisierte Kennzahlen aus.

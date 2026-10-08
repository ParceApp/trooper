# Aufgabe: Vereinheitlichung von hasCache & Cache-Konsistenz über alle Trooper

### Status: Umgesetzt und abgeschlossen

---

## 1. Problemstellung & Ausgangslage

In [`TrooperConfig`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/config/trooper_config.dart#L55) steuert `hasCache` (`timeToLive > Duration.zero`), ob Caching aktiv ist oder ob die Abfrage ungespeichert (`TrooperConfig.noCache()`) laufen soll.

Aktuell wird diese Bedingung jedoch über die verschiedenen Trooper-Klassen hinweg **asymmetrisch und inkonsistent** gehandhabt:

1. **Remote Queries ([`TrooperQuery`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/trooper_query.dart) & [`KeyedTrooperQuery`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/keyed_trooper_query.dart))**:
   - Prüfen `if (config.hasCache)` vor dem Lesen (`get`/`getKey`) und nach dem Fetch (`_executeFetch`).
   - Bei `hasCache == false` wird der L1-Memory-Cache weder gelesen noch befüllt. Dies verhindert Cache-Verschmutzung.

2. **Lokale Trooper ([`LocalTrooper`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/local_trooper.dart) vs [`KeyedLocalTrooper`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/keyed_local_trooper.dart))**:
   - [`KeyedLocalTrooper.getKey`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/keyed_local_trooper.dart#L287) prüft `if (!forceRefresh && config.hasCache)`.
   - [`LocalTrooper.get`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/local_trooper.dart#L160) prüft `config.hasCache` überhaupt nicht.
   - Beide schreiben in `set` bzw. `setKey` bedingungslos in `cache.put`, selbst wenn `hasCache == false` konfiguriert wurde.

3. **Stream Trooper ([`StreamTrooper`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/stream_trooper.dart) & [`KeyedStreamTrooper`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/keyed_stream_trooper.dart))**:
   - Beim initialen `get()` bzw. `getKey()` wird `if (config.hasCache)` abgefragt.
   - Sobald aber ein Event über den Upstream-Stream empfangen wird, rufen beide bedingungslos `cache.put(...)` auf, ohne `config.hasCache` zu prüfen.

4. **Manuelle `set`- und `setKey`-Methoden**:
   - In [`Trooper.set`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/trooper.dart#L151) und [`KeyedTrooperQuery.setKey`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/keyed_trooper_query.dart#L361) wird immer in den Cache geschrieben, da dies als manuelles Überschreiben/Seeden gewertet wird.

---

## 2. Ziel & Bereinigungsplan

### A. Semantische Definition von `hasCache` je Trooper-Kategorie
Es muss für jede Kategorie klar festgelegt und dokumentiert werden, was `hasCache == false` (z. B. `noCache()`) bedeutet:

| Kategorie | Typen | Verhalten bei `hasCache == false` |
|---|---|---|
| **Remote Queries** | `TrooperQuery`, `KeyedTrooperQuery` | **Strikter No-Cache**: Weder aus dem Cache lesen noch nach dem Fetch hineinschreiben. Jeder Aufruf geht direkt an die Datenquelle. |
| **Stream Trooper** | `StreamTrooper`, `KeyedStreamTrooper` | **Strikter No-Cache**: Eingehende Stream-Frames aktualisieren nur den `streamController` (und emit-States), werden aber nicht in den L1 `CacheStore` gelegt, damit spätere `get()`-Aufrufe nicht auf veraltete Frames treffen. |
| **Lokale Trooper** | `LocalTrooper`, `KeyedLocalTrooper` | **In-Memory-Zustand**: Lokaler Zustand lebt im Speicher. `LocalTrooper` und `KeyedLocalTrooper` behandeln In-Memory-Zustand als primäre Quelle der Wahrheit. |
| **Manuelles `set` / `setKey`** | Alle Trooper | Manuelle Updates schreiben nur dann in den Cache, wenn `config.hasCache` aktiv ist, und emittieren direkt auf den Stream. |

### B. Konkrete Bereinigungsschritte
1. **Angleichung Single vs. Keyed bei LocalTrooper**:
   - Lokaler Zustand in `LocalTrooper` und `KeyedLocalTrooper` vereinheitlicht: In-Memory-Zustand ist die primäre Datenquelle.
2. **Angleichung bei StreamTrooper**:
   - In `StreamTrooper` und `KeyedStreamTrooper` prüft das Upstream-Handling `if (config.hasCache)` vor `cache.put(...)`.
3. **Angleichung bei manuellen Updates (`set` / `setKey`)**:
   - `set()` und `setKey()` prüfen `if (config.hasCache)` vor `cache.put(...)`.
4. **Dokumentation & Konfiguration**:
   - In [`TrooperConfig`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/config/trooper_config.dart) ist die Auswirkung von `hasCache` bzw. `noCache` auf alle Trooper-Varianten vollständig dokumentiert.

---

## 3. Betroffene Dateien

- [x] [`TrooperQuery`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/trooper_query.dart)
- [x] [`KeyedTrooperQuery`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/keyed_trooper_query.dart)
- [x] [`LocalTrooper`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/local_trooper.dart)
- [x] [`KeyedLocalTrooper`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/keyed_local_trooper.dart)
- [x] [`StreamTrooper`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/stream_trooper.dart)
- [x] [`KeyedStreamTrooper`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/keyed_stream_trooper.dart)
- [x] [`Trooper`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/trooper.dart)
- [x] [`TrooperConfig`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/config/trooper_config.dart)

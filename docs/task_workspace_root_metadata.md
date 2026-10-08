# Aufgabe: Repository-Root Metadaten & Workspace-Dokumentation

### Status: Offen

---

## 1. Zielsetzung & Problemstellung
Das Repository ist als Dart-Workspace (`trooper_workspace`) strukturiert. Während das Package selbst unter [`packages/trooper`](file:///Users/hannes/Developer/trooper/packages/trooper) liegt, enthalten die Dateien im Repository-Root:
- [`README.md`](file:///Users/hannes/Developer/trooper/README.md)
- [`CHANGELOG.md`](file:///Users/hannes/Developer/trooper/CHANGELOG.md)

aktuell noch unberührte Dart-Standard-Templates mit Platzhaltern (`TODO: Put a short description...`).

Ziel dieser Aufgabe ist die Aufwertung des Repository-Roots zu einer professionellen, ansprechenden Monorepo-Übersicht für Entwickler und Mitwirkende auf GitHub.

---

## 2. Detaillierter Maßnahmenkatalog

### A. Root-Dokumentation ([`README.md`](file:///Users/hannes/Developer/trooper/README.md))
- [ ] **Monorepo-Überblick**:
  - Erklärung der Workspace-Architektur und Vision von Trooper.
  - Verlinkung auf das Core-Package [`packages/trooper`](file:///Users/hannes/Developer/trooper/packages/trooper).
  - Ausblick auf geplante Ökosystem-Packages (`trooper_flutter`, `trooper_bloc`).
- [ ] **Entwickler-Workflow (Workspace-Befehle)**:
  - Workspace-Dependencies auflösen: `dart pub get`
  - Workspace-weite statische Analyse: `dart analyze`
  - Alle Tests ausführen: `dart test`
  - Code formatieren: `dart format .`
- [ ] **Architektur-Diagramm**:
  - Visuelle Darstellung der Schichten: Inbound Ports -> Application Layer (`TrooperController`) -> Trooper Engine (`TrooperQuery`, `LocalTrooper`, `StreamTrooper`, `MutationQueue`, `CacheStore`).
- [ ] **Beitrags- & Lizenzhinweise**:
  - Contributing-Richtlinien und Link zur [`LICENSE`](file:///Users/hannes/Developer/trooper/LICENSE).

### B. Root-Changelog ([`CHANGELOG.md`](file:///Users/hannes/Developer/trooper/CHANGELOG.md))
- [ ] Umwandlung in ein klares Monorepo-Changelog, das Workspace-Updates und die Veröffentlichung der enthaltenen Packages versioniert dokumentiert.

### C. Workspace-Konfiguration & Hygiene
- [ ] [`pubspec.yaml`](file:///Users/hannes/Developer/trooper/pubspec.yaml) im Root prüfen: Workspace-Members und SDK-Constraints verifizieren.
- [ ] [`analysis_options.yaml`](file:///Users/hannes/Developer/trooper/analysis_options.yaml) im Root prüfen: Saubere Linter-Regeln für alle Workspace-Pakete sicherstellen.
- [ ] [`.gitignore`](file:///Users/hannes/Developer/trooper/.gitignore) prüfen: Ausschluss von `.dart_tool`, `.packages`, IDE-Caches und temporären Build-Artefakten.

---

## 3. Akzeptanzkriterien
1. **Keine TODO-Platzhalter**: Keine Template-Reste in Root-Dateien.
2. **Klare Navigation**: Besucher auf GitHub finden sofort den Einstieg in das Framework, die Dokumentation und den Quellcode.
3. **Workspace-Konformität**: Alle Workspace-Befehle (`dart analyze`, `dart pub get`) laufen fehlerfrei im Root.

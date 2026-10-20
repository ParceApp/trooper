# Changelog

All notable changes to the Trooper monorepo are documented in this file. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and both packages follow
[Semantic Versioning](https://semver.org/).

Details per package:

- [`packages/trooper/CHANGELOG.md`](packages/trooper/CHANGELOG.md)
- [`packages/trooper_bloc/CHANGELOG.md`](packages/trooper_bloc/CHANGELOG.md)

## [Unreleased]

## [1.0.0] - 2026-10-19

First release of `trooper` 1.0.0 and `trooper_bloc` 1.0.0 with a stable public API.

### Added

- **`trooper`**: reactive data-flow and caching framework for Dart: queries, local state,
  push streams and mutations (each also keyed by entity), `TrooperController`, L1/L2 caching
  with stale-while-revalidate, request coalescing, conflict policies, retries with jitter,
  timeouts, cooperative cancellation, pagination (`LoadMore`) and telemetry.
- **`trooper_bloc`**: `Tloc` and `Tubit` that derive BLoC/Cubit state from Trooper sources
  with snapshot locking and microtask batching, presentation `Effects`, and `FakeAccessor`
  for tests.
- **Release tooling**: deprecation policy (README section "Versioning & Deprecation") and the
  `API baseline` CI job (`.github/workflows/api-baseline.yml`), which fails when the public
  API differs from `docs/api/`.

# Deprecation policy

This policy applies to the public API of `trooper` and `trooper_bloc` from 1.0.0 on. The
public API is everything exported from `package:trooper/trooper.dart`,
`package:trooper_bloc/trooper_bloc.dart` and `package:trooper_bloc/testing.dart`, except
members annotated `@internal`. Its current state is recorded in
[`docs/api/`](api/README.md).

## Rules

1. **Deprecate before removing.** A public symbol (class, member, top-level function,
   parameter, typedef, extension) is removed or changed incompatibly only in a major release,
   and only after it was marked `@Deprecated` in at least one minor release of the previous
   major version. There is no removal without a release that announced it.
2. **Name the replacement.** The deprecation message says what to use instead and in which
   version the symbol goes away:

   ```dart
   @Deprecated('Use clearAll() instead. Will be removed in 2.0.0.')
   void resetAll() => clearAll();
   ```

   If there is no replacement, the message says so and explains why the symbol goes away.
3. **Keep it working.** A deprecated symbol behaves as before until it is removed. It may
   delegate to its replacement.
4. **List it in the CHANGELOG.** The release that deprecates a symbol lists it under a
   `### Deprecated` heading in the package CHANGELOG, with the replacement. The major release
   that removes it lists it again under `### Removed` (or in a migration table).
5. **Both packages together.** `trooper_bloc` re-exports `trooper` and shares its major
   version, so a symbol deprecated in `trooper` is deprecated for `trooper_bloc` users too,
   and is removed from both in the same major release. The `trooper_bloc` CHANGELOG points
   to the `trooper` deprecations.

## What does not need a deprecation period

- Members annotated `@internal`, and code under `lib/src/` that is not exported.
- New subtypes of `TrooperEvent` and `TrooperException` (both are `abstract final` and can
  grow in minor releases; switches over them need a default case).
- New members on `final` classes and on classes meant to be extended (`TrooperController`,
  `Tloc`, `Tubit`, `TlocEvent`).
- Fixes for behavior that contradicts the documentation. These are listed in the CHANGELOG
  under `### Fixed`.

## Checking a release

The API baseline check (see [`docs/api/README.md`](api/README.md)) shows every API change
in a pull request. Deprecating a symbol changes its `isDeprecated` flag in the baseline;
removing one is only allowed in a major release whose CHANGELOG lists the removal.

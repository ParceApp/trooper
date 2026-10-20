# Public API baseline

`trooper.json` and `trooper_bloc.json` are the public API of both packages as frozen for
1.0, extracted with [`dart_apitool`](https://pub.dev/packages/dart_apitool) 0.23.2.

## Regenerate

```bash
dart pub global activate dart_apitool 0.23.2
```

```bash
tool/api/extract.sh
```

The script writes both files and replaces the temporary package path the extractor records,
so the output is reproducible.

## Check a change for API differences

Run `tool/api/extract.sh`, then:

```bash
git diff --exit-code docs/api/
```

A non-empty diff is an API change. Removing or changing a symbol is a breaking change and
needs a major release; adding one needs a minor release. Commit the regenerated files
together with the change. Symbols are removed only after a deprecation period, see
[Versioning & Deprecation](../README.md#versioning--deprecation).

## CI

The `API baseline` workflow ([`.github/workflows/api-baseline.yml`](../../.github/workflows/api-baseline.yml))
runs on every pull request and on pushes to `main`. It installs Flutter 3.47.6 (needed for
`trooper_bloc`), activates `dart_apitool` 0.23.2, runs `tool/api/extract.sh` and fails if
`git diff --exit-code docs/api/` finds a difference. The job fails for every API change,
additions included; an intended change passes once the regenerated baseline is committed in
the same pull request, so reviewers see the API change in the diff of `docs/api/`.

Keep the Flutter and `dart_apitool` versions in the workflow, in `tool/api/extract.sh` and
in this file in sync. A new extractor version can change the output format; regenerate the
baseline in the same commit that bumps it.

Once 1.0.0 is on pub.dev, `dart_apitool` can also compare against the published release and
check the version bump:

```bash
dart pub global run dart_apitool:main diff --old pub://trooper/1.0.0 --new packages/trooper
```

## Known gaps

- `QueryKey` is an extension type, which `dart_apitool` 0.23.2 does not collect (it prints
  "elements that are marked to belong to an interface but the interface is not collected").
  Changes to `QueryKey` have to be reviewed by hand.
- Members annotated `@internal` are left out. They are not part of the public API, even
  where Dart forces them to be public (for example `Trooper.streamController`).
- `trooper_bloc.json` lists only the symbols `trooper_bloc` declares itself; the re-exported
  `trooper` API is covered by `trooper.json`.

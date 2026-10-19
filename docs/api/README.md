# Public API baseline

`trooper.json` and `trooper_bloc.json` are the public API of both packages as frozen for
1.0, extracted with [`dart_apitool`](https://pub.dev/packages/dart_apitool) 0.23.2. The
decisions behind this API are in [`docs/audit/api-freeze-decisions.md`](../audit/api-freeze-decisions.md).

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
together with the change.

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

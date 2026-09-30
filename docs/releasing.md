# Releasing

Archiving, exporting and submitting — including the steps that fail quietly when they go wrong.

# Releasing

## Submitting the iOS app

The iOS app carries the watch app inside it, so one archive covers both. `xcodebuild` builds and signs it; `asc` uploads it, stages the version and submits it. 2.5 went out this way.

```bash
# Release archive for the phone and the watch it embeds.
xcodebuild archive -project Vaultic.xcodeproj -scheme Vaultic \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath .asc/artifacts/Autheris.xcarchive -allowProvisioningUpdates

# App Store export. The ExportOptions.plist at the root is the *Mac* one and
# produces a .pkg; iOS needs ExportOptions-iOS.plist, which produces an .ipa.
asc xcode export --archive-path .asc/artifacts/Autheris.xcarchive \
  --export-options ExportOptions-iOS.plist --ipa-path .asc/artifacts/Autheris.ipa

asc builds upload --app 6760686327 --ipa .asc/artifacts/Autheris.ipa \
  --version 2.5 --build-number 20 --wait

# A freshly uploaded build is refused a review submission until this is set.
asc builds update --build "<build id>" --uses-non-exempt-encryption false

asc release stage --app 6760686327 --version 2.5 --build "<build id>" \
  --metadata-dir ./metadata --confirm
asc release run --app 6760686327 --version 2.5 --build "<build id>" \
  --metadata-dir ./metadata --confirm
```

`.asc/artifacts/` and `.asc/release/checkpoints/` are gitignored tool state, and are where `asc` expects both to live. `asc status --app 6760686327` answers "where is this release now" in one line.

Four of these steps fail quietly or confusingly:

- **`--metadata-dir` is the metadata *root*.** `asc release stage` resolves `version/<version>/` itself; pointing it at `./metadata/version/2.5` fails in `apply_metadata` with `flag: help requested` — but only *after* `ensure_version` has already created the version, so the run looks half-done rather than failed. Worse, it writes a checkpoint recording the bad `metadataDir`, and every later run then refuses to start with *"checkpoint does not match current run arguments"* until that file is deleted.
- **A new build has no export answer.** Submission fails with *"You must provide a value for the attribute `usesNonExemptEncryption`"* until `asc builds update --uses-non-exempt-encryption` is set. Build 19 — the live 2.4 — reports `false`, and 2.5's build 20 matches it; read the previous build with `asc builds info --build <id>` rather than answering the question fresh, because it is a compliance position rather than a build detail.
- **`asc xcode version view` cannot read this project.** It reports an empty version and `modern: false`, because `MARKETING_VERSION` lives per build configuration rather than at project level. Bump the six settings directly, then confirm `CFBundleShortVersionString` in the built app before uploading anything.
- **A metadata push must be previewed.** `asc metadata push --app ... --version <v> --dir ./metadata --dry-run` lists exactly what will change. A release that only adds What's New should plan *adds and nothing else*; any `changes` or `deletes` means the local listing has drifted from the live one.

Rehearse the submission with `asc release run ... --dry-run`, which prints all five steps and mutates nothing.

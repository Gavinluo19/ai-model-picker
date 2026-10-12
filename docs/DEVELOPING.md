# Development and release

The app uses Swift/AppKit, Carbon hotkeys, Keychain and Accessibility. No Node or local web server is required. Apple command-line developer tools are required to compile; system Python 3 is used by the package scripts.

```sh
bash scripts/test.sh
bash scripts/build.sh
bash scripts/package.sh
bash scripts/source-package.sh
```

- `Sources/App.swift`: native presentation, settings, user actions and operation identity checks.
- `Rules.swift`, `Offline.swift`, `Routing.swift`: data-only Markdown policy, deterministic matching and validated recommendations.
- `Services.swift`: optional JEV HTTP contract, Keychain and minimal local event logging.
- `Desktop.swift`: prototype client discovery/preparation with identity, focus, empty-draft and readback checks.
- `Updates.swift`, `Prices.swift`, `DataTable.swift`: public metadata, FX, merge/caching and price display.
- `Shortcuts.swift`, `TextInput.swift`: custom hotkey recording and attributed input/wrapping.
- `Resources`: dated shareable policy, price/catalog snapshots and generated icons.

Tests do not use live model services or user keys. Native-component/hotkey tests require a functioning macOS session. Hosted runner behavior must be evaluated before enabling the sample workflow; a hosted build is not adapter acceptance. Do not infer support for a new app version from a passing parser test.

## Signing

Without configuration, build.sh uses ad hoc signing. To create a distributable binary, supply a valid Developer ID Application identity via `TASKROUTER_SIGN_IDENTITY`. `scripts/notarize.sh` also requires `TASKROUTER_NOTARY_PROFILE`, a Keychain profile configured by the developer. Running that script uploads the package to Apple. No signing credentials are shipped, and notarization is not part of this alpha.

The package script copies bytes/modes into a temporary stage to avoid Finder/iCloud metadata invalidating a generated bundle. It does not strip quarantine attributes or disable Gatekeeper.

## Publish only the public project

Exclude `.build`, caches, private acceptance notes, transcripts, customer materials and personal configuration. Source-package.sh lists allowed roots explicitly. Never publish the parent workspace. Keep account-specific test tasks anonymized.

For a new prerelease: run tests/build/package, inspect the source archive, scan for private paths and credentials, record checksums, write exact limitations, then create an explicitly marked GitHub prerelease. Validate uploaded checksums and links. Any live-service or GUI evidence should be recorded separately with environment/version details.

## Rule and adapter changes

Verify task behavior with held-out anonymized cases. Do not copy benchmark claims into rules as measured product outcomes. Match exact models/provider IDs; maintain paid-option and custom-model guards. New adapters must preserve user drafts and user-controlled sending. Document required menus, app IDs, tested versions and manual fallback.

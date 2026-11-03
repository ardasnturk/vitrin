# Releasing

The npm tarball and the GitHub Release come from CI; the Mac app's DMG is built on a Mac that holds the Developer ID
certificate, and attached to the same release.

1. Bump the version: `package.json` and the packages, `plugins/vitrin/.claude-plugin/plugin.json`,
   `.claude-plugin/marketplace.json`, `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `apps/VitrinMac/project.yml`,
   the site, and `CHANGELOG.md`. Run `pnpm release:checksum`.
2. Commit, then build the DMG:

   ```bash
   apps/VitrinMac/scripts/build-mac.sh
   apps/VitrinMac/scripts/prepare-release.sh
   ```

   `build-mac.sh` archives, signs with Developer ID, notarizes and staples the app, builds the designed DMG with
   `dmgbuild`, then notarizes and staples the DMG too. `prepare-release.sh` writes the version and checksum into
   `Casks/vitrin.rb`.
3. Commit the cask, push `main`, and push the tag `v<version>`. The Release workflow builds, tests and creates the
   GitHub Release.
4. When it finishes, attach the DMG:

   ```bash
   apps/VitrinMac/scripts/prepare-release.sh --upload
   ```

The DMG background is drawn by `scripts/dmg/make-background.py`; keep its icon centres in sync with
`scripts/dmg/settings.py`.

One-time setup: `pipx install dmgbuild`, and store the notary credentials with
`xcrun notarytool store-credentials pilothouse-notary --apple-id <apple-id> --team-id 5JMD3VSD7N --password <app-specific-password>`.

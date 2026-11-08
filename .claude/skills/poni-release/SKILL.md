---
name: poni-release
description: Ship a Poni release the way the repo does it: version bump, DMG, tag on the feature commit, GitHub Release with Poni.dmg, then a "Formula: vX" commit. Use when the user asks to release, publish, or bump the version.
---

# Releasing Poni

Users get updates two ways, and both must be fed:
- **DMG installs** auto-update from GitHub Releases. `Updater.swift` takes the release's `.dmg` asset
  and checks it against GitHub's `sha256` digest before replacing the app.
- **Homebrew** builds from source at the tag named in `Formula/poni.rb` (and the old-name
  `Formula/baterai-safer.rb`).

Commits and releases go straight to `main` (the repo's convention; no PRs).

## Steps

1. **Pick the version.** Patch (0.9.0 → 0.9.1) for fixes and small additions, minor for redesigns or
   big features. Releases are titled `vX · <ringkasan singkat>`, notes in Indonesian.
2. **Check before building**:
   ```sh
   git status --short            # clean
   swift build 2>&1 | grep error: ; .build/debug/baterai-safer selftest   # asserts only run in debug
   ```
3. **Push the feature commits**: `git push origin main`.
4. **Build the DMG** (it builds release itself and stamps the version into Info.plist):
   ```sh
   pkill -f '.build/Poni.app'; scripts/dmg.sh X.Y.Z
   defaults read "$PWD/.build/Poni.app/Contents/Info.plist" CFBundleShortVersionString   # X.Y.Z
   ls .build/Poni.app/Contents/Resources                                                 # en.lproj id.lproj present
   ```
5. **Tag the feature commit, not the formula commit**, and publish:
   ```sh
   git tag vX.Y.Z <feature-commit>
   git push origin vX.Y.Z
   gh release create vX.Y.Z .build/Poni.dmg --title "vX.Y.Z · …" --notes "…

   Pengguna v<prev> dapat update ini otomatis."
   ```
6. **Point the formulas at the tag** and push:
   ```sh
   REV=$(git rev-parse vX.Y.Z^{commit})
   sed -i '' -E "s/tag: \"v[0-9.]+\", revision: \"[0-9a-f]+\"/tag: \"vX.Y.Z\", revision: \"$REV\"/" Formula/poni.rb Formula/baterai-safer.rb
   git commit -qam "Formula: vX.Y.Z" && git push origin main
   ```
7. **Verify**:
   ```sh
   gh release view vX.Y.Z --json isDraft,assets -q '"draft=\(.isDraft)", (.assets[] | .name + " " + .digest)'
   shasum -a 256 .build/Poni.dmg   # must equal the digest
   git status -sb                  # in sync with origin/main
   ```
8. Reopen the installed app (`open /Applications/Poni.app`) so it picks up the update.

## When a step is blocked

Claude Code's permission classifier has refused `gh release create` / pushes as "public surface"
in some sessions. Don't work around it: build the DMG and the formula commit locally, write the
remaining commands into a script in the scratchpad, and ask the user to run it with
`! sh <script>` (one line; multi-line `!` commands get cut when pasted). Then verify with step 7.

## Gotchas

- `scripts/bundle.sh` copies whatever is in `.build/release`; always build release before bundling
  for a local test (a stale binary once shipped an infinite loop).
- The DMG carries a hidden `Baterai Safer.app` copy so v0.6.10 can still auto-update; keep it.
- Signing is ad-hoc until the Developer ID plan in `docs/signing-plan.md` is done.

# Running this fork locally

This fork adds features that aren't in the Homebrew release (`brew install --cask sol`), so you build it from source. The build is ad-hoc signed — it runs on your own Mac only and needs no Apple developer account.

## Prerequisites

- macOS on Apple silicon
- Xcode (full app, not just Command Line Tools), opened once to accept the license
- [mise](https://mise.jdx.dev)

If you have the Homebrew version of Sol, remove it first. Both apps share the bundle ID `com.ospfranco.sol` and the install path `/Applications/Sol.app`, so they would overwrite each other:

```sh
brew uninstall --cask sol
```

## One-time setup

1. Clone the fork and install toolchains and dependencies:

   ```sh
   git clone git@github.com:d0hn/sol.git
   cd sol
   mise plugin add cocoapods
   mise settings experimental=true
   mise install    # installs bun + ruby, then runs bun install, bundle install, pod install
   ```

2. Create three local-only files. They are not committed because they hold machine-specific or upstream-account settings.

   `src/env.ts` — the app imports a Sentry DSN from here; leave it empty to disable error reporting:

   ```ts
   export const SentryDSN = ''
   ```

   `macos/local-signing.xcconfig` — signs the app ad-hoc instead of with the upstream author's Apple team:

   ```
   CODE_SIGN_IDENTITY = -
   CODE_SIGN_IDENTITY[sdk=macosx*] = -
   DEVELOPMENT_TEAM =
   CODE_SIGN_STYLE = Manual
   PROVISIONING_PROFILE_SPECIFIER =
   ```

   `mise.local.toml` — points Xcode at that file, skips the upstream Sentry upload, and adds an install task:

   ```toml
   [env]
   XCODE_XCCONFIG_FILE = "{{config_root}}/macos/local-signing.xcconfig"
   SENTRY_DISABLE_AUTO_UPLOAD = "true"

   [tasks.app]
   description = "Build standalone Release Sol, install to /Applications, launch"
   run = """
   set -e
   cd macos
   xcodebuild -workspace sol.xcworkspace -scheme release -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath build/local-release build -quiet
   osascript -e 'quit app "sol"' 2>/dev/null || true
   rm -rf /Applications/sol.app
   cp -R build/local-release/Build/Products/Release/sol.app /Applications/
   open /Applications/sol.app
   """
   ```

   Then trust it and keep these files out of git:

   ```sh
   mise trust mise.local.toml
   printf "mise.local.toml\nmacos/local-signing.xcconfig\n" >> .git/info/exclude
   ```

3. Turn off auto-updates. The release build checks the upstream update feed; accepting an update would replace your build with stock Sol:

   ```sh
   defaults write com.ospfranco.sol SUEnableAutomaticChecks -bool NO
   ```

## Install and run

```sh
mise run app
```

This builds the Release version, installs it to `/Applications/sol.app` and launches it. From then on, start Sol like any other app (Spotlight, Launchpad, login item). Rerun `mise run app` after pulling or changing code.

On first launch, grant the permissions Sol asks for — Accessibility (window management, hotkeys) and Calendar.

## Develop with live reload

Use two terminals in the repo root:

```sh
mise exec -- bun start    # terminal 1: Metro, the JS dev server; keep it running
mise exec -- bun macos    # terminal 2: builds and launches the debug app
```

JS changes reload on save; press `⌘R` in the app to force a reload. Changes under `macos/` (Swift/Objective-C) need `bun macos` again.

The debug app is called `sol-debug` and has its own bundle ID, so macOS asks for its permissions separately. Settings are shared with the installed app: both read `~/.config/sol/`.

## Troubleshooting

**`No signing certificate "Mac Development" found`** — Xcode isn't using `local-signing.xcconfig`. Check that `mise env` prints `XCODE_XCCONFIG_FILE`, and run commands through mise (`mise exec -- …` or an activated mise shell).

**`An organization ID or slug is required (provide with --org)`** — the Sentry upload step ran. `SENTRY_DISABLE_AUTO_UPLOAD` isn't set; same fix as above.

**`Unable to resolve module ./env`** — `src/env.ts` is missing.

**`Build input file cannot be found: .../macos/build/generated/...`** — generated code was deleted. Regenerate it with `mise exec -- bun pods`.

**Window resizing or hotkeys stop working after a rebuild** — ad-hoc builds can lose Accessibility permission when rebuilt. Remove Sol in System Settings → Privacy & Security → Accessibility and add it again, or reset both permissions with `bun permissions:reset`.

**Debug app shows a red error screen** — Metro isn't running. Start it with `mise exec -- bun start`, then press `⌘R` in the app.

## Keeping up with upstream

```sh
git remote add upstream https://github.com/ospfranco/sol.git   # once
git fetch upstream
git merge upstream/main
```

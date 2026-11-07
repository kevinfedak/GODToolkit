# GOD Toolkit

A native macOS companion for converting personally owned Xbox 360 ISO backups to Games on Demand (GOD) packages and optionally transferring the result to an RGH-enabled console over FTP.

The app is an original SwiftUI interface. It uses the MIT-licensed [`iso2god-rs`](https://github.com/iliazeus/iso2god-rs) command-line converter as a bundled helper in release builds; its source is built separately by GitHub Actions and is not copied into this repository. This project is not affiliated with Microsoft or the authors of the referenced Iso2God application.

## Responsible use

Use only disc images made from games you legally own and are authorized to back up. This tool does not provide game images, decrypt protected media, remove DRM, generate signatures, or circumvent console security. It converts a user-selected ISO into a GOD package and can transfer that output to a console configured by its owner.

## Requirements

- macOS 13 or later
- Xcode 15 or later to build locally
- Rust/Cargo only when building the `iso2god` helper locally
- An FTP service enabled on your own RGH console for transfers

## Build in Xcode

Open `GODToolkit.xcodeproj`, select the `GODToolkit` scheme, then build or run. For local conversion, install a compatible `iso2god` binary and place it at `GODToolkit/Resources/iso2god` (or set `ISO2GOD_PATH` in the environment before launching). Release builds download and compile the helper through the workflow.

## Convert and transfer

1. Choose a user-provided `.iso` file.
2. Choose an output folder and start conversion.
3. Optionally enter the console's FTP host, port, username, and password, and choose a destination path. Upload is opt-in and starts only after conversion completes.

FTP credentials are held only in memory for the current app session. FTP is unencrypted; use a trusted local network. The app does not save credentials or contact a third-party service.

## Release

Pushing a `v*` tag runs `.github/workflows/release.yml` on a macOS runner, builds a universal `.app`, packages it as a DMG, generates a third-party license report from the same helper checkout, and publishes the DMG, ZIP, and report to a GitHub Release. The report is bundled inside the app as `THIRD-PARTY-LICENSES.html`. The app is unsigned; macOS may require the user to approve opening it. Developer ID signing and notarization can be added by configuring repository secrets.

## Credits

Made with Codex. The interface and packaging in this repository are original. Conversion is provided by the separate MIT-licensed `iso2god-rs` project.

## License

The original interface and workflow files are provided under the MIT License. See `LICENSE`. The bundled `iso2god` helper is separately licensed under MIT; its license is included in the app resources.

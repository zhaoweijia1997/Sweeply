<p align="center"><img src="docs/icon.png" width="128" alt="Sweeply icon"></p>

# Sweeply

**English** · [简体中文](README.zh-CN.md)

A small, honest junk cleaner for macOS. Sweeply finds caches, logs and developer
leftovers you can safely remove, shows you exactly what they are, and never deletes
anything until you choose to.

<p align="center">
  <img src="docs/screenshots/main-en-light.png" width="720" alt="Sweeply showing developer caches and their sizes">
</p>

> **Status: early preview (0.3).** Scans, moves what you pick to the Trash, and shows your SSD's health.

## What it finds

**Developer tools**
- Xcode build data (DerivedData), Xcode caches, device support files, archives
- iOS Simulator caches
- Gradle caches (Android Studio)
- Homebrew downloads
- pip, npm, Yarn, CocoaPods and Swift Package Manager caches

**App caches & logs**
- Caches apps keep in `~/Library/Caches` (the system's own caches and those of running apps are skipped)
- Log files in `~/Library/Logs`

**Disk Health** (new in 0.3)
- How much has been written to your Mac's built-in SSD, how worn the drive thinks it
  is, its temperature, spare blocks and error counts — read straight from the drive.

<p align="center">
  <img src="docs/screenshots/disk-en-light.png" width="620" alt="Sweeply's Disk Health tab">
</p>

Each category explains what it is and whether it comes back. Expand it to see every
folder, reveal it in Finder, or untick the ones you want to keep.

## Safety first

- **Nothing is deleted without you.** Sweeply only scans until you pick what to clean.
- **Everything goes to the Trash**, so you can put it back until you empty it.
- **Only your Mac's own disk.** External drives are never scanned or touched.
- **System caches and running apps are left alone.**
- **Checked twice.** Right before moving, each item is checked again: still in its
  category's folder, still on this Mac's disk, and its app still not running.
- **Works offline.** No accounts, no analytics, no network requests.

## Languages

English, 简体中文, 繁體中文, 日本語, Русский, Español, हिन्दी — switch any time from the
globe menu in the window, no restart needed.

Translations other than English and Chinese would love a review from native speakers.
See [CONTRIBUTING.md](CONTRIBUTING.md).

## Install

1. Download `Sweeply-<version>.dmg` from [Releases](../../releases).
2. Open it and drag **Sweeply** into **Applications**.
3. The first time you open it, macOS says it can't verify the developer, because
   Sweeply isn't notarized by Apple yet. Open **System Settings → Privacy & Security**,
   scroll down and click **Open Anyway**. You only need to do this once.

Requires macOS 14 Sonoma or later, on Apple silicon or Intel.

## Build from source

Requires Xcode (the Command Line Tools alone lack SwiftUI's macro plugins).

```bash
./build.sh             # builds build.noindex/Sweeply.app (universal)
./build.sh --install   # also copies it to /Applications
./build.sh --dmg       # also makes a .dmg for a release
python3 tools/check_localizations.py   # checks every translation
```

`Sweeply.app/Contents/MacOS/Sweeply --disk-health` prints what the Disk Health tab reads
(handy for bug reports). `Sweeply.app/Contents/MacOS/Sweeply --snapshot <folder>` renders the window in every
language, light and dark, using made-up results — handy for checking layouts and for
screenshots.

## Roadmap

- [x] Move selected items to the Trash (0.2)
- [ ] Remove simulators for iOS versions you no longer have installed
- [ ] Old installers in Downloads
- [x] App icon

## Support Sweeply

Sweeply is free and always will be. If it saved you some space, you can buy the
developer a coffee — WeChat Pay or Alipay in China, PayPal anywhere. Thank you!

<p align="center">
  <img src="docs/donate/wechat.png" height="260" alt="WeChat Pay QR code">
  <img src="docs/donate/alipay.png" height="260" alt="Alipay QR code">
  <img src="docs/donate/paypal.png" height="260" alt="PayPal QR code">
</p>

## Contact

Bugs and ideas: [open an issue](../../issues). Email: zhaoweijia1997@gmail.com

## License

[MIT](LICENSE)

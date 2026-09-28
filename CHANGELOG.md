# Changelog

## 0.3.1 — 2026-09-28

- Fix: Disk Health showed "isn't available" after the first read (for example after
  pressing Refresh). The SMART plug-in wasn't released with `IODestroyPlugInInterface`,
  so every later read in the same session failed. (0.3.0 put the blame on background
  threads; that was wrong.)
- A Refresh button on the "isn't available" screen, too.

## 0.3.0 — 2026-09-28

- **Disk Health** tab: total data written and read, the drive's own wear estimate
  ("life used"), spare blocks, temperature, power-on time, power cycles, unsafe
  shutdowns and media errors, with a plain-language verdict. Read-only, straight from
  the built-in SSD's NVMe SMART log; external drives are never read.

## 0.2.0 — 2026-09-28

- **Move to Trash.** Tick categories — or single folders inside them — and move them to
  the Trash after a confirmation. Nothing is ever deleted outright.
- Each item is checked again right before it moves: still inside its category's folder,
  on the same disk as your home folder, and (for app caches) its app still not running.
  Anything that fails a check or can't be moved is left in place and reported.
- A summary after cleaning, with a reminder to empty the Trash and a button to open it.
- App icon (drawn by `tools/make-icon.swift`).

## 0.1.0 — preview, not released as a download

First preview: scan only.

- Scans developer leftovers (Xcode, Simulator, Gradle, Homebrew, package manager caches)
  and app caches & logs, and shows each category's size and folders.
- Skips system caches, caches of running apps, and external drives.
- English, 简体中文, 繁體中文, 日本語, Русский, Español and हिन्दी, switchable live.
- `--snapshot` renders the window in every language for layout checks and screenshots.

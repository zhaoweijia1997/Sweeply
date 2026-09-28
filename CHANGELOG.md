# Changelog

## 0.2.0 — unreleased

- **Move to Trash.** Tick categories — or single folders inside them — and move them to
  the Trash after a confirmation. Nothing is ever deleted outright.
- Each item is checked again right before it moves: still inside its category's folder,
  on the same disk as your home folder, and (for app caches) its app still not running.
  Anything that fails a check or can't be moved is left in place and reported.
- A summary after cleaning, with a reminder to empty the Trash and a button to open it.

## 0.1.0 — unreleased

First preview: scan only.

- Scans developer leftovers (Xcode, Simulator, Gradle, Homebrew, package manager caches)
  and app caches & logs, and shows each category's size and folders.
- Skips system caches, caches of running apps, and external drives.
- English, 简体中文, 繁體中文, 日本語, Русский, Español and हिन्दी, switchable live.
- `--snapshot` renders the window in every language for layout checks and screenshots.

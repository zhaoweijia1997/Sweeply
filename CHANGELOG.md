# Changelog

## 0.8.0 — 2026-10-08

- **Used space over time** on the Disk Health tab: how much of the startup disk was in use at
  the end of each of the last 30 days and how much that changed, to spot something that keeps
  eating space. Sweeply notes it together with the writes: whenever it's open, at most once an
  hour (all day in the background with the menu bar icon). macOS keeps no such history, so it
  starts the first time Sweeply notes it, and it's kept across updates in
  ~/Library/Application Support/Sweeply. Shown even when the drive's health can't be read.

## 0.7.0 — 2026-10-08

- **Left behind by deleted apps** (new on the Clean Up tab): login items and background
  services (launch agents and daemons in `~/Library/LaunchAgents`, `/Library/LaunchAgents`
  and `/Library/LaunchDaemons`) whose program no longer exists, with the app they came with
  and how many times macOS has tried to start them. A deleted app's service can be restarted
  every few seconds for weeks. Audio drivers from the same developer are listed too, unticked,
  when none of its apps is installed any more.
- An item only counts when what it starts is certainly gone: not when macOS privacy
  protection keeps Sweeply from looking, not on an external drive, and never Apple's own.
  Each one is checked again right before it's removed.
- Removing stops each item, then moves it to the Trash. Those in system folders ask for your
  password once, in macOS's own dialog; cancelling leaves them as they were.
- `--leftovers` lists what the check finds on this Mac, read-only.

## 0.6.0 — 2026-09-28

- **Display brightness**: a slider for each display on the Devices tab and in the menu
  bar panel. Apple displays use the system's brightness control; other monitors are
  controlled over DDC/CI (Apple silicon), like the dedicated monitor utilities do. While
  dragging, only the latest value is sent, so slow monitors don't get flooded.

## 0.5.0 — 2026-09-28

- **Background mode with a menu bar icon** (Settings, off by default): closing the
  window keeps Sweeply running as a little broom in the menu bar, without a Dock icon,
  so writes per day keep being recorded. The icon can also show the CPU temperature or
  usage. Its panel shows CPU, memory, temperature, fans, free space and today's writes.
- **Open at login** (Settings): starts quietly in the menu bar. Uses the system's login
  items, or a per-user launch agent when the system won't register the app.
- **Settings** window (⌘,), also from the gear in the main window.
- New cleanup categories, **not selected by default**: **Xcode simulators** (shown by
  device and iOS version; running ones are skipped) and **installers in Downloads**
  (.dmg, .pkg, .xip, with when they were downloaded).

## 0.4.0 — 2026-09-28

- **System** tab: CPU usage per core, memory used and memory pressure (split like
  Activity Monitor), swap, startup disk space, uptime.
- **Temperature & fans**: hottest and average CPU core, SSD temperature, and each fan's
  speed.
- **Devices** tab: displays, external drives (name, size, free space, format, USB /
  Thunderbolt / disk image), USB and Thunderbolt devices. No serial numbers, and nothing
  on an external drive is read.
- **Writes per day** on the Disk Health tab: Sweeply notes the drive's lifetime total
  whenever it's open (at most hourly) and charts the last 30 days. Kept on this Mac only.
- `Sweeply --report` prints every reading twice, without identifiers, for bug reports.

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

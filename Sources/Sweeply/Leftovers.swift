import AppKit
import Foundation

/// Something a deleted app left behind that macOS keeps trying to start: a login item or
/// background service (launch agent or daemon) whose program no longer exists, or an audio
/// driver from the same developer when none of that developer's apps is installed any more.
struct Leftover: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        /// ~/Library/LaunchAgents: starts when you log in.
        case loginItem
        /// /Library/LaunchAgents: starts when anyone logs in.
        case loginItemForAllUsers
        /// /Library/LaunchDaemons: runs in the background for the whole Mac.
        case backgroundService
        /// An audio device's driver (Audio/Plug-Ins/HAL).
        case audioDriver
    }

    let kind: Kind
    /// The launch item's label, or the driver's bundle identifier.
    let identifier: String
    /// The app it came with, as far as its paths tell ("Example Remote").
    let appName: String
    /// What it starts, which no longer exists. Launch items only.
    var missingProgram: String? = nil
    /// How many times macOS has started it since the Mac (or, for login items, the session)
    /// started, if macOS has it loaded.
    var runs: Int? = nil
    /// In a system folder: removing it takes an administrator's password.
    let needsPassword: Bool
}

/// Finds leftovers. Read-only, like `Scanner`: nothing here moves or changes anything.
enum LeftoverScanner {
    /// Where launch items, audio drivers and apps are. Tests point these at a scratch folder.
    struct Places: Sendable {
        var home: URL
        /// ~/Library/LaunchAgents
        var loginItems: URL
        /// /Library/LaunchAgents
        var loginItemsForAllUsers: URL
        /// /Library/LaunchDaemons
        var backgroundServices: URL
        /// ~/Library/Audio/Plug-Ins/HAL
        var userAudioDrivers: URL
        /// /Library/Audio/Plug-Ins/HAL
        var audioDrivers: URL
        /// Where installed apps are looked for, one folder deep.
        var applications: [URL]

        static func standard(home: URL) -> Places {
            Places(
                home: home,
                loginItems: home.appending(path: "Library/LaunchAgents"),
                loginItemsForAllUsers: URL(fileURLWithPath: "/Library/LaunchAgents"),
                backgroundServices: URL(fileURLWithPath: "/Library/LaunchDaemons"),
                userAudioDrivers: home.appending(path: "Library/Audio/Plug-Ins/HAL"),
                audioDrivers: URL(fileURLWithPath: "/Library/Audio/Plug-Ins/HAL"),
                applications: [URL(fileURLWithPath: "/Applications"), home.appending(path: "Applications")])
        }

        /// The folder an item of this kind lives in.
        func folders(for kind: Leftover.Kind) -> [URL] {
            switch kind {
            case .loginItem: [loginItems]
            case .loginItemForAllUsers: [loginItemsForAllUsers]
            case .backgroundService: [backgroundServices]
            case .audioDriver: [userAudioDrivers, audioDrivers]
            }
        }
    }

    /// How many times launchd has started a job, or nil if it isn't loaded.
    typealias RunCount = @Sendable (_ domain: String, _ label: String) -> Int?

    /// `launchctl print <domain>/<label>` shows "runs = 151105" for a loaded job. Reading it
    /// needs no password.
    static let launchctlRuns: RunCount = { domain, label in
        let output = Launchctl.run(["print", "\(domain)/\(label)"])
        guard let line = output.split(separator: "\n").first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("runs = ") })
        else { return nil }
        return Int(line.split(separator: "=").last?.trimmingCharacters(in: .whitespaces) ?? "")
    }

    /// The launch domain a job of this kind is loaded in.
    static func domain(for kind: Leftover.Kind) -> String {
        kind == .backgroundService ? "system" : "gui/\(getuid())"
    }

    static func scan(_ places: Places, runs: RunCount = launchctlRuns) -> CategoryResult {
        var items: [FoundItem] = []
        // Developers of the apps whose launch items are left over, for finding their drivers.
        var vendors: [String: String] = [:]
        let launchFolders: [(URL, Leftover.Kind)] = [
            (places.loginItems, .loginItem),
            (places.loginItemsForAllUsers, .loginItemForAllUsers),
            (places.backgroundServices, .backgroundService),
        ]
        for (folder, kind) in launchFolders {
            for url in children(of: folder) where url.pathExtension == "plist" {
                guard let job = LaunchJob(url: url, home: places.home), job.isLeftover else { continue }
                let leftover = Leftover(
                    kind: kind, identifier: job.label, appName: job.appName, missingProgram: job.program,
                    runs: runs(domain(for: kind), job.label), needsPassword: kind != .loginItem)
                items.append(FoundItem(url: url, size: Scanner.allocatedSize(of: url), label: leftover.appName, leftover: leftover))
                for identifier in [job.label] + job.associatedBundleIDs {
                    if let vendor = vendor(of: identifier) { vendors[vendor] = vendors[vendor] ?? job.appName }
                }
            }
        }
        items.sort { ($0.leftover?.runs ?? 0, $1.name) > ($1.leftover?.runs ?? 0, $0.name) }

        if !vendors.isEmpty {
            let installed = installedVendors(in: places.applications)
            for (folder, needsPassword) in [(places.userAudioDrivers, false), (places.audioDrivers, true)] {
                for url in children(of: folder) where url.pathExtension == "driver" {
                    guard let identifier = bundleIdentifier(of: url), !identifier.hasPrefix("com.apple."),
                          let vendor = vendor(of: identifier), let appName = vendors[vendor],
                          !installed.contains(vendor) else { continue }
                    let leftover = Leftover(kind: .audioDriver, identifier: identifier, appName: appName, needsPassword: needsPassword)
                    items.append(FoundItem(url: url, size: Scanner.allocatedSize(of: url), label: url.deletingPathExtension().lastPathComponent,
                                           leftover: leftover))
                }
            }
        }
        return CategoryResult(items: items)
    }

    /// Checked again right before an item is removed: still where it was found, and still a
    /// leftover. For drivers, that the developer still has no app installed.
    static func isStillLeftover(_ item: FoundItem, places: Places) -> Bool {
        guard let leftover = item.leftover else { return false }
        let url = item.url.standardizedFileURL
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().path
        guard places.folders(for: leftover.kind).map({ $0.resolvingSymlinksInPath().path }).contains(parent),
              isThere(url) else { return false }
        switch leftover.kind {
        case .audioDriver:
            guard let identifier = bundleIdentifier(of: url), identifier == leftover.identifier,
                  let vendor = vendor(of: identifier) else { return false }
            return !installedVendors(in: places.applications).contains(vendor)
        default:
            guard let job = LaunchJob(url: url, home: places.home) else { return false }
            return job.label == leftover.identifier && job.isLeftover
        }
    }

    // MARK: Helpers

    /// Whether something is at this path, a symbolic link included. Asks the file system each
    /// time: a URL's resource values are cached, so they still answer for a file that has moved.
    static func isThere(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }

    /// Certainly not there: the lookup fails with "no such file", not with "not permitted"
    /// (what macOS privacy protection answers for folders Sweeply may not look into).
    static func isGone(_ path: String) -> Bool {
        var info = stat()
        guard stat(path, &info) != 0 else { return false }
        return errno == ENOENT || errno == ENOTDIR
    }

    /// The developer part of a bundle identifier or label: "com.example" in "com.example.app.helper".
    static func vendor(of identifier: String) -> String? {
        let parts = identifier.lowercased().split(separator: ".")
        return parts.count >= 3 ? parts.prefix(2).joined(separator: ".") : nil
    }

    /// Developers with an app in these folders or one folder further down.
    static func installedVendors(in folders: [URL]) -> Set<String> {
        var vendors = Set<String>()
        func add(_ app: URL) {
            if let identifier = bundleIdentifier(of: app), let vendor = vendor(of: identifier) { vendors.insert(vendor) }
        }
        for folder in folders {
            for item in children(of: folder) {
                if item.pathExtension == "app" {
                    add(item)
                } else if (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    children(of: item).filter { $0.pathExtension == "app" }.forEach(add)
                }
            }
        }
        return vendors
    }

    static func bundleIdentifier(of bundle: URL) -> String? {
        NSDictionary(contentsOf: bundle.appending(path: "Contents/Info.plist"))?["CFBundleIdentifier"] as? String
    }

    static func children(of folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    }
}

/// What a launch item's plist says it starts.
struct LaunchJob {
    let label: String
    /// The program it starts, as an absolute path; nil when that can't be told for certain
    /// (a command line with variables, a name looked up in PATH).
    let program: String?
    let associatedBundleIDs: [String]

    init?(url: URL, home: URL) {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let label = plist["Label"] as? String else { return nil }
        self.label = label
        associatedBundleIDs = plist["AssociatedBundleIdentifiers"] as? [String]
            ?? (plist["AssociatedBundleIdentifiers"] as? String).map { [$0] } ?? []
        program = Self.program(plist, home: home)
    }

    /// Not Apple's, and what it starts is certainly gone: not merely unreadable, and not on a
    /// drive that may just be unplugged.
    var isLeftover: Bool {
        guard !label.hasPrefix("com.apple."), let program, !program.hasPrefix("/Volumes/") else { return false }
        return LeftoverScanner.isGone(program)
    }

    /// The app in the program's path ("Example Remote" for /Applications/Example Remote.app/…),
    /// else a framework's name, else the label without its developer part.
    var appName: String {
        if let program {
            let parts = program.split(separator: "/")
            if let app = parts.first(where: { $0.hasSuffix(".app") }) { return String(app.dropLast(4)) }
            if let framework = parts.first(where: { $0.hasSuffix(".framework") }) { return String(framework.dropLast(10)) }
        }
        let parts = (associatedBundleIDs.first ?? label).split(separator: ".")
        return parts.count >= 3 ? parts.dropFirst(2).joined(separator: ".") : label
    }

    static func program(_ plist: [String: Any], home: URL) -> String? {
        let arguments = plist["ProgramArguments"] as? [String] ?? []
        guard var program = plist["Program"] as? String ?? arguments.first else { return nil }
        let rest = Array(arguments.dropFirst())
        if ["/bin/sh", "/bin/bash", "/bin/zsh", "/bin/dash", "/bin/ksh"].contains(program) {
            // `sh -c "<command line>"`: what runs is the command line's first word.
            guard let flag = rest.firstIndex(of: "-c"), flag + 1 < rest.count,
                  let first = firstWord(of: rest[flag + 1]) else { return nil }
            program = first
        } else if program == "/usr/bin/open" {
            // `open -a /Applications/Some.app`
            guard let app = rest.first(where: { $0.hasPrefix("/") && $0.hasSuffix(".app") }) else { return nil }
            program = app
        }
        if program.hasPrefix("~/") {
            program = home.path + program.dropFirst()
        }
        if !program.hasPrefix("/"), program.contains("/"), let directory = plist["WorkingDirectory"] as? String, directory.hasPrefix("/") {
            program = URL(fileURLWithPath: directory).appending(path: program).standardizedFileURL.path
        }
        return program.hasPrefix("/") ? program : nil
    }

    /// The first word of a shell command line with its quotes removed, skipping `exec`. Nil if
    /// the shell would change it (variables, globs, substitutions) or if it sets a variable.
    static func firstWord(of command: String) -> String? {
        var word = ""
        var quote: Character?
        var escaped = false
        var rest = Substring(command.trimmingCharacters(in: .whitespacesAndNewlines))
        while let character = rest.first {
            rest = rest.dropFirst()
            if escaped {
                word.append(character)
                escaped = false
            } else if let open = quote {
                if character == open {
                    quote = nil
                } else if open == "\"", "$`".contains(character) {
                    return nil
                } else if open == "\"", character == "\\" {
                    escaped = true
                } else {
                    word.append(character)
                }
            } else if character == "\\" {
                escaped = true
            } else if character == "'" || character == "\"" {
                quote = character
            } else if " \t\n;&|".contains(character) {
                break
            } else if "$`*?[](){}<>=".contains(character) {
                return nil
            } else {
                word.append(character)
            }
        }
        guard quote == nil, !escaped, !word.isEmpty else { return nil }
        return word == "exec" ? firstWord(of: String(rest)) : word
    }
}

/// Runs launchctl and returns what it printed.
enum Launchctl {
    static func run(_ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Removing

/// Removes leftovers: stops each one, then moves its file to the Trash. Those in system folders
/// are moved out by an administrator (one password prompt for all of them) into a folder of
/// Sweeply's, and from there to the Trash like everything else. Nothing is deleted outright: if
/// a step fails, the file stays where it was, or in that folder.
enum LeftoverRemover {
    struct Result {
        var removed: [FoundItem] = []
        var notRemoved: [FoundItem] = []
        /// The password prompt was cancelled, so nothing in system folders was touched.
        var passwordCancelled = false
    }

    enum AdminError: Error {
        case cancelled
        case failed(String)
    }

    /// Runs a shell script as an administrator, after asking for the password with `prompt`.
    /// Tests pass a stand-in that runs it as themselves on scratch folders.
    typealias RunAsAdmin = @MainActor (_ script: String, _ prompt: String) throws -> Void
    /// Stops a launch job in a domain ("gui/501"); failures are fine (it may not be loaded).
    typealias Bootout = @Sendable (_ domain: String, _ label: String) -> Void

    static let launchctlBootout: Bootout = { domain, label in
        _ = Launchctl.run(["bootout", "\(domain)/\(label)"])
    }

    /// macOS's own password dialog, through AppleScript's `do shell script`. It has to run on
    /// the main thread; the window waits while the dialog is open.
    static let administrator: RunAsAdmin = { script, prompt in
        try runAppleScript(script, prompt: prompt, asAdministrator: true)
    }

    /// `do shell script`, as an administrator or (in tests) as yourself.
    @MainActor
    static func runAppleScript(_ script: String, prompt: String, asAdministrator: Bool) throws {
        var source = "do shell script \"\(appleScriptString(script))\""
        if asAdministrator {
            source += " with prompt \"\(appleScriptString(prompt))\" with administrator privileges"
        }
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            if error[NSAppleScript.errorNumber] as? Int == -128 { throw AdminError.cancelled }
            throw AdminError.failed(error[NSAppleScript.errorMessage] as? String ?? "")
        }
    }

    @MainActor
    static func remove(
        _ items: [FoundItem],
        places: LeftoverScanner.Places,
        bootout: Bootout = launchctlBootout,
        runAsAdmin: RunAsAdmin = administrator,
        moveToTrash: Cleaner.MoveToTrash = Cleaner.systemTrash
    ) -> Result {
        var result = Result()
        var mine: [FoundItem] = []
        var system: [FoundItem] = []
        for item in items {
            guard let leftover = item.leftover, LeftoverScanner.isStillLeftover(item, places: places) else {
                result.notRemoved.append(item)
                continue
            }
            if leftover.needsPassword { system.append(item) } else { mine.append(item) }
        }

        // In your own folders: stop it, then into the Trash.
        for item in mine {
            if let leftover = item.leftover, leftover.kind != .audioDriver {
                bootout(LeftoverScanner.domain(for: leftover.kind), leftover.identifier)
            }
            do {
                try moveToTrash(item.url)
                result.removed.append(item)
            } catch {
                result.notRemoved.append(item)
            }
        }
        guard !system.isEmpty else { return result }

        // In system folders: an administrator moves them into a folder of ours, numbered so
        // names can't collide, and hands them over to you.
        let stage = FileManager.default.temporaryDirectory.appending(path: "Sweeply leftovers \(UUID().uuidString)")
        do {
            for index in system.indices {
                try FileManager.default.createDirectory(at: stage.appending(path: "\(index)"), withIntermediateDirectories: true)
            }
        } catch {
            result.notRemoved += system
            return result
        }
        do {
            try runAsAdmin(script(for: system, stage: stage), String(localized: "Sweeply wants to remove background items and drivers that deleted apps left in system folders."))
        } catch {
            if case AdminError.cancelled = error { result.passwordCancelled = true }
            result.notRemoved += system
            removeEmptyFolders(stage, count: system.count)
            return result
        }
        for (index, item) in system.enumerated() {
            let staged = stage.appending(path: "\(index)").appending(path: item.url.lastPathComponent)
            guard !LeftoverScanner.isThere(item.url), LeftoverScanner.isThere(staged) else {
                result.notRemoved.append(item)
                continue
            }
            do {
                try moveToTrash(staged)
                result.removed.append(item)
            } catch {
                // Out of the system folder, but not in the Trash: it stays in our folder.
                result.notRemoved.append(item)
            }
        }
        removeEmptyFolders(stage, count: system.count)
        return result
    }

    /// The administrator's part, for the items in system folders: stop each one, move it into
    /// its numbered folder, and make it yours so it can go to your Trash.
    static func script(for items: [FoundItem], stage: URL, uid: uid_t = getuid(), gid: gid_t = getgid()) -> String {
        var lines = ["uid=\(uid); gid=\(gid)"]
        for (index, item) in items.enumerated() {
            guard let leftover = item.leftover else { continue }
            let folder = shellQuoted(stage.appending(path: "\(index)").path)
            switch leftover.kind {
            case .backgroundService:
                lines.append("/bin/launchctl bootout system/\(shellQuoted(leftover.identifier)) >/dev/null 2>&1")
            case .loginItemForAllUsers, .loginItem:
                lines.append("/bin/launchctl bootout gui/$uid/\(shellQuoted(leftover.identifier)) >/dev/null 2>&1")
            case .audioDriver:
                break
            }
            let moved = shellQuoted(stage.appending(path: "\(index)").appending(path: item.url.lastPathComponent).path)
            lines.append("/bin/mv -f \(shellQuoted(item.url.path)) \(folder)/ && /usr/sbin/chown -R \"$uid:$gid\" \(moved)")
        }
        lines.append("exit 0")
        return lines.joined(separator: "\n")
    }

    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func appleScriptString(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// Only empty folders: `rmdir` never removes anything that's still inside.
    private static func removeEmptyFolders(_ stage: URL, count: Int) {
        for index in 0..<count {
            rmdir(stage.appending(path: "\(index)").path)
        }
        rmdir(stage.path)
    }
}

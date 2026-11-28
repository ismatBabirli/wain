import Foundation
import MetricKit

/// Anonymous usage counts and crash reports, sent to PostHog the way the desktop's `analytics.rs`
/// sends them: one POST per event under a random install id, and nothing the reader wrote — no
/// prompt, path, title or error message. Settings → Privacy has a switch for each, both on by
/// default. A build with no `PostHogKey` (every local one) sends nothing.
///
/// Sessions, bots and messages started here are counted by the server that runs them, so the
/// phone reports only that it was opened, and how it crashed.
enum Analytics {
    static let usageKey = "privacy.usage"
    static let crashKey = "privacy.crashReports"
    static let idKey = "privacy.installId"

    /// Filled in by release-ios.yml from the `POSTHOG_KEY` secret, through Info.plist.
    private static let key = (Bundle.main.object(forInfoDictionaryKey: "PostHogKey") as? String).flatMap { $0.isEmpty ? nil : $0 }
    private static let endpoint = URL(string: "https://us.i.posthog.com/i/v0/e/")!
    private static let crashes = CrashReader()
    @MainActor private static var day = ""

    /// At launch: which build is in the wild, and the last run's crash, which MetricKit delivers now.
    @MainActor static func start() {
        MXMetricManager.shared.add(crashes)
        send("app_started")
        activeDay()
    }

    /// At most once per local day per run, at launch and on every return to the front.
    @MainActor static func activeDay() {
        let today = Date().formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
        guard day != today, send("active_day") else { return }
        day = today
    }

    /// Both switches off: the id goes, and switching one back on makes a new one.
    static func forget() { UserDefaults.standard.removeObject(forKey: idKey) }

    private static func allowed(_ key: String) -> Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }

    /// Whether the event went, so a day is claimed only once its event did.
    @MainActor @discardableResult
    static func send(_ event: String, _ props: [String: Any] = [:]) -> Bool {
        guard allowed(event == "$exception" ? crashKey : usageKey) else { return false }
        let all = base.merging(props) { $1 }
        guard let key else {
            #if DEBUG
            print("[analytics] would send \(event) \(all)")
            #endif
            return false
        }
        let body: [String: Any] = ["api_key": key, "event": event, "distinct_id": installId(), "properties": all]
        var request = URLRequest(url: endpoint, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        // A wrong key or region is a 4xx and nothing else, so say so.
        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error { print("[analytics err] \(error.localizedDescription)") }
            if let code = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(code) { print("[analytics err] \(code)") }
        }.resume()
        return true
    }

    @MainActor private static func installId() -> String {
        if let id = UserDefaults.standard.string(forKey: idKey) { return id }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: idKey)
        return id
    }

    private static let base: [String: Any] = {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        #if DEBUG
        let debug = true
        #else
        let debug = false
        #endif
        return [
            "app_version": version,
            "build": info?["CFBundleVersion"] as? String ?? "?",
            "os": "ios",
            "os_version": "\(os.majorVersion).\(os.minorVersion)",
            "is_debug": debug,
            // Not the desktop's "app": a phone is an install of its own, so a person of its own.
            "source": "phone",
            // PostHog reads a missing one as automation, and bot-filtered insights drop the event.
            "$raw_user_agent": "Wain/\(version) (ios)",
        ]
    }()

    /// A MetricKit crash as an `$exception`: its type from the Mach exception and signal, or the
    /// Objective-C exception's name, and the crashed thread's frames in this app's own binary,
    /// outermost first. Frames are offsets into the binary, as MetricKit gives them; the build's
    /// dSYM turns them into names. The termination reason and exception message are free text,
    /// so neither is read.
    static func crash(exception: Int?, signal: Int?, objcName: String?, stack: Data, binary: String,
                      version: String?, build: String?) -> [String: Any] {
        let tree = (try? JSONSerialization.jsonObject(with: stack)) as? [String: Any]
        let threads = tree?["callStacks"] as? [[String: Any]] ?? []
        let thread = threads.first { $0["threadAttributed"] as? Bool == true } ?? threads.first
        // Each frame's caller is its first sub-frame, from the crash outwards.
        var ours: [[String: Any]] = []
        var next = (thread?["callStackRootFrames"] as? [[String: Any]])?.first
        while let f = next {
            if ours.count < 20, f["binaryName"] as? String == binary, let offset = (f["offsetIntoBinaryTextSegment"] as? NSNumber)?.uint64Value {
                ours.append(["platform": "custom", "lang": "swift", "function": String(format: "0x%llx", offset),
                             "filename": binary, "lineno": NSNull(), "colno": NSNull(), "resolved": true, "in_app": true])
            }
            next = (f["subFrames"] as? [[String: Any]])?.first
        }
        let named = objcName.flatMap { n in n.count <= 64 && n.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") } ? n : nil }
        let type = named ?? "\(name(exception, machExceptions, "EXC_")) (\(name(signal, signals, "SIG")))"
        var props: [String: Any] = [
            "kind": "crash",
            "$exception_list": [[
                "type": type,
                "value": (ours.first?["function"] as? String).map { "crash at \(binary)+\($0)" } ?? "crash",
                "mechanism": ["handled": false, "synthetic": false],
                "stacktrace": ["type": "raw", "frames": Array(ours.reversed())],
            ]],
        ]
        // The build that crashed, which an update since may have replaced.
        if let version { props["app_version"] = version }
        if let build { props["build"] = build }
        return props
    }

    private static func name(_ n: Int?, _ table: [Int: String], _ prefix: String) -> String {
        guard let n else { return "\(prefix)?" }
        return table[n] ?? "\(prefix)\(n)"
    }

    private static let machExceptions = [1: "EXC_BAD_ACCESS", 2: "EXC_BAD_INSTRUCTION", 3: "EXC_ARITHMETIC", 5: "EXC_SOFTWARE",
                                         6: "EXC_BREAKPOINT", 10: "EXC_CRASH", 11: "EXC_RESOURCE", 12: "EXC_GUARD"]
    private static let signals = [4: "SIGILL", 5: "SIGTRAP", 6: "SIGABRT", 8: "SIGFPE", 9: "SIGKILL", 10: "SIGBUS",
                                  11: "SIGSEGV", 12: "SIGSYS", 13: "SIGPIPE", 15: "SIGTERM"]
}

/// iOS collects a crash itself, Swift traps and signals alike, which nothing inside the app could
/// catch safely, and MetricKit hands it over once the app opens again.
private final class CrashReader: NSObject, MXMetricManagerSubscriber {
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let binary = Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String ?? "Wain"
        let crashes = payloads.flatMap { $0.crashDiagnostics ?? [] }.map { d in
            Analytics.crash(exception: d.exceptionType?.intValue, signal: d.signal?.intValue,
                            objcName: d.exceptionReason?.exceptionName, stack: d.callStackTree.jsonRepresentation(),
                            binary: binary, version: d.applicationVersion, build: d.metaData.applicationBuildVersion)
        }
        Task { @MainActor in crashes.forEach { Analytics.send("$exception", $0) } }
    }
}

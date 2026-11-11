import UtterCore
import AppKit
import Foundation

/// Where Utter's Whisper pieces live.
enum WhisperPaths {
    /// Whisper runs on MLX, which needs Apple Silicon. Intel Macs use Apple's recognizer.
    static var isSupported: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    /// ~/Library/Application Support/Utter
    static var supportDirectory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Utter", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// The Python environment created by scripts/setup-whisper.sh.
    static var bundledEnvPython: String {
        supportDirectory.appendingPathComponent("whisper-env/bin/python").path
    }

    /// The override from Settings, else Utter's own environment.
    static func python() -> String? {
        let override = Prefs.whisperPython.trimmingCharacters(in: .whitespaces)
        let path = override.isEmpty ? bundledEnvPython : (override as NSString).expandingTildeInPath
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    static func script() -> URL? {
        if let bundled = Bundle.main.url(forResource: "whisper_server", withExtension: "py") { return bundled }
        #if DEBUG
        // Running the bare debug binary from the package: use the repo copy. Debug
        // only, because #filePath embeds the build machine's folder in the binary.
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("sidecar/whisper_server.py")
        return FileManager.default.fileExists(atPath: repo.path) ? repo : nil
        #else
        return nil
        #endif
    }
}

/// Runs sidecar/whisper_server.py as a child process and talks to it over
/// localhost. The model stays loaded between dictations (roughly 2 GB of RAM).
///
/// The server binds a port the OS picks and requires a token generated on each
/// launch, so other programs on the Mac can't use it. It exits on its own if
/// Utter goes away.
@MainActor
final class WhisperSidecar: ObservableObject {
    static let shared = WhisperSidecar()

    enum Status: Equatable {
        case off
        /// scripts/setup-whisper.sh is running (payload: its latest output line).
        case installing(String)
        case starting
        case ready
        case failed(String)
    }

    /// Whether Utter's Whisper environment (or a custom Python) is present.
    var isInstalled: Bool { WhisperPaths.python() != nil }

    @Published private(set) var status: Status = .off
    private var process: Process?
    private var port: Int?
    private var token = ""
    private var startToken = 0

    var isReady: Bool { status == .ready }

    var logURL: URL { WhisperPaths.supportDirectory.appendingPathComponent("whisper.log") }
    private var portFile: URL { WhisperPaths.supportDirectory.appendingPathComponent("whisper.port") }

    func ensureRunning() {
        if let process, process.isRunning { return }
        if case .installing = status { return }
        startToken += 1
        status = .starting
        launch(token: startToken)
    }

    func restart() {
        stop()
        ensureRunning()
    }

    func stop() {
        startToken += 1
        process?.terminate()
        process = nil
        port = nil
        status = .off
    }

    private func launch(token run: Int) {
        guard let python = WhisperPaths.python() else {
            status = .failed("Whisper isn't installed yet.")
            return
        }
        guard let script = WhisperPaths.script() else {
            status = .failed("whisper_server.py is missing from the app bundle.")
            return
        }
        token = UUID().uuidString + UUID().uuidString
        port = nil
        try? FileManager.default.removeItem(at: portFile)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [
            script.path, "--port", "0", "--port-file", portFile.path, "--model", Prefs.whisperModel,
            "--parent-pid", "\(ProcessInfo.processInfo.processIdentifier)",
        ]
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        env["UTTER_WHISPER_TOKEN"] = token
        process.environment = env

        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        if let handle = try? FileHandle(forWritingTo: logURL) {
            process.standardOutput = handle
            process.standardError = handle
        }
        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.process === proc else { return }
                    self.process = nil
                    if case .starting = self.status {
                        self.status = .failed("Whisper exited while starting (code \(proc.terminationStatus)). See whisper.log.")
                    } else if case .ready = self.status {
                        self.status = .failed("Whisper stopped unexpectedly. See whisper.log.")
                    }
                }
            }
        }
        do {
            try process.run()
        } catch {
            status = .failed("Couldn't start Python: \(error.localizedDescription)")
            return
        }
        self.process = process

        Task {
            // The server writes its port once the model is loaded: ~2 s when cached,
            // several minutes when the model is downloaded on first use.
            for _ in 0..<900 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard run == startToken else { return }
                if self.process == nil { return } // termination handler reported it
                if port == nil,
                   let text = try? String(contentsOf: portFile, encoding: .utf8),
                   let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    port = value
                }
                if port != nil, await healthy() {
                    status = .ready
                    return
                }
            }
            status = .failed("Whisper didn't become ready in time. See whisper.log.")
        }
    }

    /// Runs the bundled setup script (~1.2 GB of packages plus the ~1.6 GB model on
    /// first install), showing its progress, then starts Whisper.
    func install() {
        if case .installing = status { return }
        guard WhisperPaths.isSupported else {
            status = .failed("Whisper needs an Apple Silicon Mac. This Mac uses Apple's built-in recognizer.")
            return
        }
        guard let script = Bundle.main.url(forResource: "setup-whisper", withExtension: "sh") else {
            status = .failed("The installer is missing from the app bundle.")
            return
        }
        stop()
        status = .installing("Starting…")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        var lastLine = ""
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            let line = chunk.split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, case .installing = self.status, !line.isEmpty else { return }
                    lastLine = line
                    self.status = .installing(line)
                }
            }
        }
        process.terminationHandler = { [weak self] proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if proc.terminationStatus == 0 {
                        self.status = .off
                        self.ensureRunning()
                    } else {
                        self.status = .failed(lastLine.isEmpty ? "The Whisper installer failed." : lastLine)
                    }
                }
            }
        }
        do {
            try process.run()
        } catch {
            status = .failed("Couldn't run the installer: \(error.localizedDescription)")
        }
    }

    private func request(_ path: String, timeout: TimeInterval) -> URLRequest? {
        guard let port, let url = URL(string: "http://127.0.0.1:\(port)\(path)") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(token, forHTTPHeaderField: "X-Utter-Token")
        return request
    }

    private func healthy() async -> Bool {
        guard let request = request("/health", timeout: 1),
              let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    func transcribe(wav: URL, language: String?, prompt: String?) async throws -> String {
        guard var request = request("/transcribe", timeout: 60) else {
            throw TranscriptionError(message: "Whisper isn't running")
        }
        var body: [String: Any] = ["path": wav.path]
        if let language { body["language"] = language }
        if let prompt, !prompt.isEmpty { body["prompt"] = prompt }
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (response as? HTTPURLResponse)?.statusCode == 200, let text = json["text"] as? String else {
            throw TranscriptionError(message: json["error"] as? String ?? "Whisper returned an unexpected response")
        }
        return text
    }
}

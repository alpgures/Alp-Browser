import Foundation

public actor OCISyncService {
    public static let shared = OCISyncService()

    public enum SyncResult: Sendable {
        case success(String)
        case failure(String)
    }

    public init() {}

    /// Push the full browser state (Spaces, Pinned Tabs, Boosts, Easels, Notes) to the OCI box.
    /// Uses SSH (`ssh oci-box`) to store `~/.arc2-cloud/store.json` reliably even behind OCI VCN firewalls.
    public func pushStore(_ store: PersistedBrowserStore, sshAlias: String = "oci-box") async -> SyncResult {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let payloadData = try encoder.encode(store)

            let result = try await runSSHCommand(
                alias: sshAlias,
                remoteCommand: "mkdir -p ~/.arc2-cloud && cat > ~/.arc2-cloud/arc2_store.json.tmp && mv ~/.arc2-cloud/arc2_store.json.tmp ~/.arc2-cloud/arc2_store.json && echo SYNC_OK",
                stdinData: payloadData
            )

            if result.contains("SYNC_OK") {
                return .success("Synced to \(sshAlias):~/.arc2-cloud/arc2_store.json")
            } else {
                return .failure("Unexpected response from \(sshAlias): \(result)")
            }
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// Pull the stored browser state from the OCI box (`~/.arc2-cloud/arc2_store.json`).
    public func pullStore(sshAlias: String = "oci-box") async throws -> PersistedBrowserStore? {
        let output = try await runSSHCommand(
            alias: sshAlias,
            remoteCommand: "if [ -f ~/.arc2-cloud/arc2_store.json ]; then cat ~/.arc2-cloud/arc2_store.json; fi",
            stdinData: nil
        )
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PersistedBrowserStore.self, from: data)
    }

    /// Check SSH connectivity to `oci-box` and whether Claude Code CLI is installed on the remote box.
    public func checkOCIConnection(sshAlias: String = "oci-box") async -> (connected: Bool, hostname: String, claudeAvailable: Bool) {
        do {
            let output = try await runSSHCommand(
                alias: sshAlias,
                remoteCommand: "hostname && (command -v claude >/dev/null 2>&1 || [ -x ~/.npm-global/bin/claude ] || [ -x ~/.local/bin/claude ] && echo CLAUDE_YES || echo CLAUDE_NO)",
                stdinData: nil
            )
            let lines = output
                .split(separator: "\n")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let host = lines.first ?? sshAlias
            let hasClaude = output.contains("CLAUDE_YES")
            return (true, host, hasClaude)
        } catch {
            return (false, "Offline", false)
        }
    }

    /// Arc Max AI: Ask a question about the current page or summarize via Claude Code on the OCI box.
    public func askArcMax(
        question: String,
        pageTitle: String,
        pageURL: String,
        pageText: String,
        sshAlias: String = "oci-box"
    ) async -> String {
        let snippet = String(pageText.prefix(8000))
        let prompt = """
        You are Arc Max, the concise built-in AI assistant inside Arc Browser.
        Page Title: \(pageTitle)
        Page URL: \(pageURL)

        Page Content Excerpt:
        \(snippet)

        User Request: \(question)
        Respond concisely in clean bullet points or 2-3 short paragraphs.
        """

        if let promptData = prompt.data(using: .utf8) {
            let remoteCmd = """
            export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:/usr/local/bin:$PATH"
            if command -v claude >/dev/null 2>&1; then
                claude -p "$(cat)" 2>/dev/null
            else
                echo "__NO_CLAUDE__"
            fi
            """
            if let remoteReply = try? await runSSHCommand(alias: sshAlias, remoteCommand: remoteCmd, stdinData: promptData) {
                let cleaned = remoteReply.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty && !cleaned.contains("__NO_CLAUDE__") {
                    return cleaned
                }
            }
        }

        // Fast localextractive summary fallback if Claude CLI is busy or unreachable
        return localExtractiveAnswer(question: question, pageTitle: pageTitle, pageText: pageText)
    }

    private func localExtractiveAnswer(question: String, pageTitle: String, pageText: String) -> String {
        let lines = pageText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 35 }

        let keywords = question
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }

        var scored: [(line: String, score: Int)] = []
        for line in lines.prefix(250) {
            let lower = line.lowercased()
            let score = keywords.reduce(0) { acc, kw in
                acc + (lower.contains(kw) ? 2 : 0)
            }
            if score > 0 {
                scored.append((line, score))
            }
        }

        scored.sort { $0.score > $1.score }
        let topMatches = scored.prefix(4).map { "• " + $0.line }
        if !topMatches.isEmpty {
            return "Key matches on **\(pageTitle)**:\n\n" + topMatches.joined(separator: "\n\n")
        }

        let summaryLines = lines.prefix(4).map { "• " + String($0.prefix(200)) }
        if !summaryLines.isEmpty {
            return "Page Highlights (**\(pageTitle)**):\n\n" + summaryLines.joined(separator: "\n\n")
        }
        return "No readable text found on this page yet."
    }

    private func runSSHCommand(alias: String, remoteCommand: String, stdinData: Data?) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                process.arguments = [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=6",
                    alias,
                    remoteCommand
                ]

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                var inPipe: Pipe?
                if stdinData != nil {
                    let pipe = Pipe()
                    process.standardInput = pipe
                    inPipe = pipe
                }

                do {
                    try process.run()
                    if let data = stdinData, let pipe = inPipe {
                        pipe.fileHandleForWriting.write(data)
                        try? pipe.fileHandleForWriting.close()
                    }
                    process.waitUntilExit()
                    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let outString = String(data: outData, encoding: .utf8) ?? ""
                    let errString = String(data: errData, encoding: .utf8) ?? ""
                    if process.terminationStatus == 0 || !outString.isEmpty {
                        continuation.resume(returning: outString)
                    } else {
                        continuation.resume(throwing: NSError(
                            domain: "OCISyncService",
                            code: Int(process.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: errString.isEmpty ? "SSH exited with code \(process.terminationStatus)" : errString]
                        ))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

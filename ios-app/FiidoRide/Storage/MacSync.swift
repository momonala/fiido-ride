import Foundation

/// Asks the Mac's sync listener (`sync/server.py`) to pull the ride database off this phone.
struct MacSync {
    struct Step: Equatable {
        let number: Int
        let total: Int
        let label: String
    }

    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    private static let timeout: TimeInterval = 300

    let url: URL
    let token: String

    /// Nil unless `.env` gave the build a host, port and token.
    static let configured: MacSync? = {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let host = info["FiidoSyncHost"] as? String, !host.isEmpty,
              let port = info["FiidoSyncPort"] as? String, !port.isEmpty,
              let token = info["FiidoSyncToken"] as? String, !token.isEmpty,
              let url = URL(string: "http://\(host):\(port)/sync") else { return nil }
        return MacSync(url: url, token: token)
    }()

    /// Reads the listener's line protocol: "step <n> <total> <label>", then "done …" or "error <message>".
    @MainActor func run(onStep: (Step) -> Void) async throws {
        var request = URLRequest(url: url, timeoutInterval: Self.timeout)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (lines, response) = try await URLSession.shared.bytes(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw Failure(errorDescription: "The Mac refused the sync.")
        }
        for try await line in lines.lines {
            let parts = line.split(separator: " ", maxSplits: 3).map(String.init)
            switch parts.first {
            case "step":
                guard parts.count == 4, let number = Int(parts[1]), let total = Int(parts[2]) else { continue }
                onStep(Step(number: number, total: total, label: parts[3]))
            case "done":
                return
            case "error":
                throw Failure(errorDescription: String(line.dropFirst("error ".count)))
            default:
                continue
            }
        }
        throw Failure(errorDescription: "The Mac stopped answering.")
    }
}

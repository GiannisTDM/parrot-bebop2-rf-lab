import Foundation
import Network

struct RestreamDescriptor: Equatable {
    let requestPort: UInt16
    let videoAddress: String?
    let videoPort: UInt16?
    let response: String
}

final class RestreamProbe {
    var onDebug: ((String) -> Void)?

    private let queue = DispatchQueue(label: "parrotlab.restream-probe")
    private var connection: NWConnection?
    private var activeProbeID: UUID?

    func probe(host: String, ports: [UInt16] = [7711, 6007], completion: @escaping (Result<RestreamDescriptor, Error>) -> Void) {
        cancel()
        let probeID = UUID()
        activeProbeID = probeID
        probe(host: host, remainingPorts: ports, lastError: nil, probeID: probeID, completion: completion)
    }

    func cancel() {
        activeProbeID = nil
        connection?.cancel()
        connection = nil
    }

    private func probe(
        host: String,
        remainingPorts: [UInt16],
        lastError: Error?,
        probeID: UUID,
        completion: @escaping (Result<RestreamDescriptor, Error>) -> Void
    ) {
        guard activeProbeID == probeID else { return }
        guard let port = remainingPorts.first else {
            let error = lastError ?? NSError(
                domain: "ParrotLab.Restream",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No SC2 restream endpoint responded"]
            )
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            probe(host: host, remainingPorts: Array(remainingPorts.dropFirst()), lastError: lastError, probeID: probeID, completion: completion)
            return
        }

        debug("Probing SC2 video endpoint \(host):\(port)")
        let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .tcp)
        self.connection = connection
        var response = Data()
        var completed = false

        func tryNext(_ error: Error) {
            guard !completed, self.activeProbeID == probeID else { return }
            completed = true
            connection.cancel()
            self.connection = nil
            self.probe(
                host: host,
                remainingPorts: Array(remainingPorts.dropFirst()),
                lastError: error,
                probeID: probeID,
                completion: completion
            )
        }

        func finish(_ result: Result<RestreamDescriptor, Error>) {
            guard !completed, self.activeProbeID == probeID else { return }
            completed = true
            connection.cancel()
            self.connection = nil
            self.activeProbeID = nil
            DispatchQueue.main.async { completion(result) }
        }

        func receive() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                if let data { response.append(data) }
                if let error {
                    self.debug("Port \(port) did not respond: \(error.localizedDescription)")
                    tryNext(error)
                    return
                }
                if isComplete || response.range(of: Data("\r\n\r\n".utf8)) != nil {
                    let text = String(data: response, encoding: .utf8) ?? ""
                    guard text.contains("200") || text.contains("m=video") else {
                        let error = NSError(
                            domain: "ParrotLab.Restream",
                            code: Int(port),
                            userInfo: [NSLocalizedDescriptionKey: "Unexpected response from port \(port)"]
                        )
                        tryNext(error)
                        return
                    }
                    let descriptor = RestreamDescriptor(
                        requestPort: port,
                        videoAddress: Self.firstCapture(#"c=IN IP4\s+([^\s\r\n]+)"#, in: text),
                        videoPort: Self.firstCapture(#"m=video\s+(\d+)"#, in: text).flatMap(UInt16.init),
                        response: text
                    )
                    self.debug("SC2 restream endpoint answered on port \(port)")
                    finish(.success(descriptor))
                    return
                }
                receive()
            }
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                let request = "GET /video HTTP/1.1\r\nHost: \(host)\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(request.utf8), completion: .contentProcessed { error in
                    if let error { finish(.failure(error)) }
                    else { receive() }
                })
            case .failed(let error):
                self.debug("Port \(port) failed: \(error.localizedDescription)")
                tryNext(error)
            default:
                break
            }
        }
        connection.start(queue: queue)

        queue.asyncAfter(deadline: .now() + 2.0) {
            guard !completed, self.activeProbeID == probeID else { return }
            self.debug("Port \(port) timed out")
            tryNext(NSError(
                    domain: "ParrotLab.Restream",
                    code: Int(port),
                    userInfo: [NSLocalizedDescriptionKey: "Port \(port) timed out"]
                ))
        }
    }

    static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = expression.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[valueRange])
    }

    private func debug(_ message: String) {
        DispatchQueue.main.async { [weak self] in self?.onDebug?(message) }
    }
}

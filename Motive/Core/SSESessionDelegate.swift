//
//  SSESessionDelegate.swift
//  Motive
//
//  URLSession delegate for real-time SSE data delivery.
//  Extracted from SSEClient.swift for separation of concerns.
//

import Foundation

/// A URLSession delegate that delivers SSE data chunks in real-time via an AsyncStream.
/// This avoids the buffering that can occur with `URLSession.bytes(for:)`.
final class SSESessionDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let dataContinuation: AsyncStream<String>.Continuation
    let dataStream: AsyncStream<String>

    private var responseResolver: ((Result<HTTPURLResponse, Error>) -> Void)?
    private let lock = NSLock()

    override init() {
        var cont: AsyncStream<String>.Continuation!
        self.dataStream = AsyncStream { cont = $0 }
        self.dataContinuation = cont
        super.init()
    }

    /// Wait for the initial HTTP response.
    func waitForResponse() async throws -> HTTPURLResponse {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            self.responseResolver = { result in
                switch result {
                case let .success(response):
                    continuation.resume(returning: response)
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
            lock.unlock()
        }
    }

    /// Called when the initial response headers arrive
    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        lock.lock()
        let resolver = self.responseResolver
        self.responseResolver = nil
        lock.unlock()

        if let httpResponse = response as? HTTPURLResponse {
            resolver?(.success(httpResponse))
        } else {
            resolver?(.failure(SSEClient.SSEError.noResponse))
        }
        completionHandler(.allow)
    }

    /// Called each time data arrives — no buffering, immediate delivery
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if let text = String(data: data, encoding: .utf8) {
            dataContinuation.yield(text)
        }
    }

    /// Called when the stream completes
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        dataContinuation.finish()

        // If response never arrived, resolve with error
        lock.lock()
        let resolver = self.responseResolver
        self.responseResolver = nil
        lock.unlock()

        if let resolver {
            resolver(.failure(error ?? SSEClient.SSEError.noResponse))
        }
    }
}

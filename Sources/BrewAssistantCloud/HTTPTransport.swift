//
//  HTTPTransport.swift
//  BrewAssistantCloud
//

import BrewAssistantCore
import Foundation

/// The network boundary, so tests answer requests without leaving the process.
public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPTransport {
    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request, delegate: nil)
    }
}

enum CloudRequest {
    /// Generous for two small structured replies, short enough that a stalled server surfaces as an error.
    static let timeout: TimeInterval = 60

    static func schemaObject(_ json: String) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(json.utf8))
    }

    static func post(_ url: URL, headers: [String: String], body: [String: Any]) throws -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    /// Maps transport failures and HTTP statuses onto the Assistant's own errors, keeping the server's
    /// message for anything it does not recognise.
    static func send(_ request: URLRequest, with transport: any HTTPTransport, provider: String) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AssistantError.generationFailed("\(provider): \(error.localizedDescription)")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200 ..< 300:
            return data
        case 401, 403:
            throw AssistantError.unauthorized
        case 429:
            throw AssistantError.rateLimited
        default:
            throw AssistantError.generationFailed("\(provider) returned HTTP \(status): \(serverMessage(in: data))")
        }
    }

    private static func serverMessage(in data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
                return message
            }
            if let message = object["message"] as? String {
                return message
            }
        }
        return String(bytes: data.prefix(300), encoding: .utf8) ?? "no readable message"
    }

    static func decode<T: Decodable>(_ type: T.Type, fromJSONText text: String, provider: String) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: Data(text.utf8))
        } catch {
            throw AssistantError.generationFailed("\(provider) returned an answer that was not the expected JSON")
        }
    }
}

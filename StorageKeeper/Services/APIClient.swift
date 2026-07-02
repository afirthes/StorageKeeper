import Foundation

enum APIError: LocalizedError {
    case notConfigured
    case unauthorized
    case locked(String)
    case serverUnavailable
    case invalidURL
    case message(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Сервер не настроен."
        case .unauthorized:
            return "Нужно войти заново."
        case .locked(let message):
            return message
        case .serverUnavailable:
            return "Сервер временно недоступен. Если сейчас идет обновление, подождите несколько секунд и попробуйте снова."
        case .invalidURL:
            return "Некорректный адрес сервера."
        case .message(let message):
            return message
        }
    }
}

struct AuthStatusResponse: Codable {
    var configured: Bool
    var challenge: AuthChallengeResponse
}

struct AuthChallengeResponse: Codable {
    var captchaRequired: Bool
    var captchaId: String?
    var captchaQuestion: String?
    var lockedUntil: Date?
    var lockRemainingSeconds: Int
    var failedAttempts: Int
}

struct AuthResponse: Codable {
    var username: String
    var accessToken: String
    var refreshToken: String
    var expiresInSeconds: Int
}

struct APIMessage: Codable {
    var message: String?
}

struct EmptyResponse: Codable {}

@MainActor
final class APIClient {
    var serverURL: String = ""
    var accessToken: String?

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession = .shared) {
        self.session = session
        decoder = JSONDecoder()
        encoder = JSONEncoder()

        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let dateDecoder = ISO8601DateFormatter()
            dateDecoder.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let fallbackDateDecoder = ISO8601DateFormatter()
            fallbackDateDecoder.formatOptions = [.withInternetDateTime]
            if let date = dateDecoder.date(from: value) ?? fallbackDateDecoder.date(from: value) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid date: \(value)"))
        }
    }

    func get<T: Decodable>(_ path: String) async throws -> T {
        try await send(path: path, method: "GET", body: Optional<EmptyResponse>.none)
    }

    func post<Request: Encodable, Response: Decodable>(_ path: String, body: Request) async throws -> Response {
        try await send(path: path, method: "POST", body: body)
    }

    func put<Request: Encodable, Response: Decodable>(_ path: String, body: Request) async throws -> Response {
        try await send(path: path, method: "PUT", body: body)
    }

    func patch<Request: Encodable, Response: Decodable>(_ path: String, body: Request) async throws -> Response {
        try await send(path: path, method: "PATCH", body: body)
    }

    func delete(_ path: String) async throws {
        let _: EmptyResponse = try await send(path: path, method: "DELETE", body: Optional<EmptyResponse>.none)
    }

    func uploadPhoto(_ data: Data, folder: String) async throws -> PhotoResponse {
        guard var components = URLComponents(url: try url(for: "/photos"), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "folder", value: folder)]
        guard let url = components.url else {
            throw APIError.invalidURL
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        applyAuthorization(to: &request)
        request.httpBody = multipartBody(data: data, boundary: boundary)

        let (responseData, response) = try await session.data(for: request)
        try validate(responseData: responseData, response: response)
        return try decoder.decode(PhotoResponse.self, from: responseData)
    }

    func photoData(for key: String) async throws -> Data {
        guard var components = URLComponents(url: try url(for: "/photos"), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "key", value: key)]
        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        applyAuthorization(to: &request)
        let (data, response) = try await session.data(for: request)
        try validate(responseData: data, response: response)
        return data
    }

    private func send<Request: Encodable, Response: Decodable>(
        path: String,
        method: String,
        body: Request?
    ) async throws -> Response {
        var request = URLRequest(url: try url(for: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthorization(to: &request)

        if let body {
            request.httpBody = try encoder.encode(body)
        }

        let (responseData, response) = try await session.data(for: request)
        try validate(responseData: responseData, response: response)

        if responseData.isEmpty {
            return EmptyResponse() as! Response
        }

        return try decoder.decode(Response.self, from: responseData)
    }

    private func validate(responseData: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.serverUnavailable
        }

        guard !(200...299).contains(http.statusCode) else {
            return
        }

        if http.statusCode == 401 {
            throw APIError.unauthorized
        }

        let text = String(data: responseData, encoding: .utf8) ?? ""
        if http.statusCode == 423 {
            throw APIError.locked(message(from: responseData) ?? "Доступ временно заблокирован.")
        }

        if [502, 503, 504].contains(http.statusCode) || text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<") {
            throw APIError.serverUnavailable
        }

        throw APIError.message(message(from: responseData) ?? "Ошибка сервера: \(http.statusCode)")
    }

    private func message(from data: Data) -> String? {
        guard let decoded = try? decoder.decode(APIMessage.self, from: data),
              let message = decoded.message,
              !message.isEmpty else {
            return nil
        }
        return message
    }

    private func url(for path: String) throws -> URL {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw APIError.notConfigured
        }

        let normalized = trimmed.hasSuffix("/api") ? trimmed : trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api"
        guard URL(string: normalized) != nil else {
            throw APIError.invalidURL
        }

        let separator = normalized.hasSuffix("/") ? "" : "/"
        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: normalized + separator + normalizedPath) else {
            throw APIError.invalidURL
        }
        return url
    }

    private func applyAuthorization(to request: inout URLRequest) {
        if let accessToken, !accessToken.isEmpty {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
    }

    private func multipartBody(data: Data, boundary: String) -> Data {
        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"photo.jpg\"\r\n")
        body.append("Content-Type: image/jpeg\r\n\r\n")
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n")
        return body
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}

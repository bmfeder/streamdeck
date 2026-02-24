import Foundation

/// Response from the authenticate endpoint (no action param).
public struct XtreamAuthResponse: Equatable, Sendable, Decodable {
    public let userInfo: UserInfo
    public let serverInfo: ServerInfo

    public struct UserInfo: Equatable, Sendable, Decodable {
        public let username: String?
        public let password: String?
        public let status: String?
        public let auth: LenientInt
        public let expDate: LenientOptionalInt?
        public let isTrial: LenientInt?
        public let activeCons: LenientInt?
        public let maxConnections: LenientInt?
        public let createdAt: LenientOptionalInt?
        public let allowedOutputFormats: [String]?
    }

    public struct ServerInfo: Equatable, Sendable, Decodable {
        public let url: String?
        public let port: LenientString?
        public let httpsPort: LenientString?
        public let serverProtocol: String?
        public let rtmpPort: LenientString?
        public let timezone: String?
        public let timestampNow: LenientOptionalInt?
        public let timeNow: String?
    }

    /// Whether authentication succeeded.
    public var isAuthenticated: Bool { userInfo.auth.value == 1 }

    /// Whether the account has expired based on exp_date.
    public var isExpired: Bool {
        guard let exp = userInfo.expDate?.value else { return false }
        return Date(timeIntervalSince1970: TimeInterval(exp)) < Date()
    }
}

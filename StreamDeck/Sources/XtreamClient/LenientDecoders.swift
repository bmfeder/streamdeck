import Foundation

// MARK: - LenientInt

/// Decodes a value that may be a JSON number or a JSON string containing a number.
/// Defaults to 0 if the value is null, empty string, or non-numeric.
public struct LenientInt: Equatable, Sendable, Decodable, Hashable {
    public let value: Int

    public init(value: Int) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            self.value = intVal
        } else if let stringVal = try? container.decode(String.self),
                  let parsed = Int(stringVal) {
            self.value = parsed
        } else {
            self.value = 0
        }
    }
}

// MARK: - LenientOptionalInt

/// Like LenientInt but preserves nil when the value is null, empty string, or non-parseable.
public struct LenientOptionalInt: Equatable, Sendable, Decodable, Hashable {
    public let value: Int?

    public init(value: Int?) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = nil
        } else if let intVal = try? container.decode(Int.self) {
            self.value = intVal
        } else if let stringVal = try? container.decode(String.self) {
            self.value = stringVal.isEmpty ? nil : Int(stringVal)
        } else {
            self.value = nil
        }
    }
}

// MARK: - LenientOptionalDouble

/// Decodes a value that may be a JSON number, string number, empty string, or null → Double?.
public struct LenientOptionalDouble: Equatable, Sendable, Decodable, Hashable {
    public let value: Double?

    public init(value: Double?) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = nil
        } else if let doubleVal = try? container.decode(Double.self) {
            self.value = doubleVal
        } else if let stringVal = try? container.decode(String.self) {
            self.value = stringVal.isEmpty ? nil : Double(stringVal)
        } else {
            self.value = nil
        }
    }
}

// MARK: - LenientString

/// Decodes a value that may be a JSON string or a JSON number → always String.
public struct LenientString: Equatable, Sendable, Decodable, Hashable {
    public let value: String

    public init(value: String) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let stringVal = try? container.decode(String.self) {
            self.value = stringVal
        } else if let intVal = try? container.decode(Int.self) {
            self.value = String(intVal)
        } else if let doubleVal = try? container.decode(Double.self) {
            self.value = String(doubleVal)
        } else {
            self.value = ""
        }
    }
}

// MARK: - LenientStringOrArray

/// Handles the backdrop_path quirk: can be a single string OR an array of strings.
public struct LenientStringOrArray: Equatable, Sendable, Decodable, Hashable {
    public let values: [String]

    public init(values: [String]) {
        self.values = values
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let array = try? container.decode([String].self) {
            self.values = array.filter { !$0.isEmpty }
        } else if let single = try? container.decode(String.self), !single.isEmpty {
            self.values = [single]
        } else {
            self.values = []
        }
    }
}

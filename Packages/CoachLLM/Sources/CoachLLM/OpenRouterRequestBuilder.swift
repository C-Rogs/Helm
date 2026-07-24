import Foundation

public struct OpenRouterChatCompletionRequest: Encodable, @unchecked Sendable {
    public struct Message: Encodable, Sendable {
        public let role: String
        public let content: [ContentPart]

        public init(role: String, content: [ContentPart]) {
            self.role = role
            self.content = content
        }
    }

    public struct ContentPart: Encodable, Sendable {
        public let type: String
        public let text: String?
        public let imageURL: ImageURL?

        enum CodingKeys: String, CodingKey {
            case type
            case text
            case imageURL = "image_url"
        }

        public struct ImageURL: Encodable, Sendable {
            public let url: String

            public init(url: String) {
                self.url = url
            }
        }

        public static func text(_ value: String) -> ContentPart {
            ContentPart(type: "text", text: value, imageURL: nil)
        }

        public static func image(jpegBase64: String) -> ContentPart {
            ContentPart(
                type: "image_url",
                text: nil,
                imageURL: ImageURL(url: "data:image/jpeg;base64,\(jpegBase64)")
            )
        }
    }

    public struct ResponseFormat: Encodable, Sendable {
        public let type: String
        public let jsonSchema: JSONSchemaWrapper

        enum CodingKeys: String, CodingKey {
            case type
            case jsonSchema = "json_schema"
        }

        public struct JSONSchemaWrapper: Encodable, @unchecked Sendable {
            public let name: String
            public let strict: Bool
            public let schema: [String: Any]

            public init(name: String, strict: Bool, schema: [String: Any]) {
                self.name = name
                self.strict = strict
                self.schema = schema
            }

            public func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(name, forKey: .name)
                try container.encode(strict, forKey: .strict)
                let data = try JSONSerialization.data(withJSONObject: schema)
                let object = try JSONDecoder().decode(JSONValue.self, from: data)
                try container.encode(object, forKey: .schema)
            }

            enum CodingKeys: String, CodingKey {
                case name
                case strict
                case schema
            }
        }
    }

    public let model: String
    public let messages: [Message]
    public let responseFormat: ResponseFormat?
    public let temperature: Double

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case responseFormat = "response_format"
        case temperature
    }

    public init(
        model: String,
        messages: [Message],
        responseFormat: ResponseFormat? = nil,
        temperature: Double = 0.2
    ) {
        self.model = model
        self.messages = messages
        self.responseFormat = responseFormat
        self.temperature = temperature
    }
}

private enum JSONValue: Codable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

public enum OpenRouterRequestBuilder {
    public static func mealDecompositionPhotoBody(
        systemInstructions: String,
        imageJPEGBase64: String,
        model: MealVisionModel = .openRouterGemma,
        useStructuredOutput: Bool = false
    ) throws -> Data {
        let jsonInstructions = """
        \(systemInstructions)
        Respond with JSON only matching meal_decomposition schema_version \(CoachOutputSchemaVersion.mealDecompositionV1.rawValue).
        """
        let responseFormat: OpenRouterChatCompletionRequest.ResponseFormat? = useStructuredOutput
            ? .init(
                type: "json_schema",
                jsonSchema: .init(
                    name: "meal_decomposition",
                    strict: true,
                    schema: GeminiRequestBuilder.mealDecompositionSchema()
                )
            )
            : nil
        let request = OpenRouterChatCompletionRequest(
            model: model.rawValue,
            messages: [
                .init(role: "user", content: [
                    .text(jsonInstructions),
                    .text("Decompose this meal photo into ingredients and estimated grams."),
                    .image(jpegBase64: imageJPEGBase64)
                ])
            ],
            responseFormat: responseFormat
        )
        return try JSONEncoder().encode(request)
    }
}

public enum OpenRouterResponseParser {
    private struct CompletionResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }

            let message: Message
        }

        let choices: [Choice]
    }

    public static func messageText(from data: Data) throws -> String {
        let response = try JSONDecoder().decode(CompletionResponse.self, from: data)
        guard let text = response.choices.first?.message.content, !text.isEmpty else {
            throw CoachProviderError.requestFailed("OpenRouter returned an empty response.")
        }
        return text
    }
}

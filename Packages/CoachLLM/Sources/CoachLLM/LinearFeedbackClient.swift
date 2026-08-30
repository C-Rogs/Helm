import Foundation

/// In-app TestFlight feedback that creates a Linear issue on CamLab / Helm.
public enum LinearFeedbackKind: String, Sendable, Equatable {
    case bug
    case feature
}

public struct LinearFeedbackDraft: Sendable, Equatable {
    public var kind: LinearFeedbackKind
    public var title: String
    public var details: String
    public var fromName: String
    public var coachHistoryMarkdown: String?

    public init(
        kind: LinearFeedbackKind,
        title: String,
        details: String,
        fromName: String,
        coachHistoryMarkdown: String? = nil
    ) {
        self.kind = kind
        self.title = title
        self.details = details
        self.fromName = fromName
        self.coachHistoryMarkdown = coachHistoryMarkdown
    }
}

public enum LinearFeedbackError: Error, Sendable, Equatable, LocalizedError {
    case missingKey
    case invalidInput(String)
    case transport
    case rejected

    public var errorDescription: String? {
        switch self {
        case .missingKey:
            "Feedback is not wired on this build."
        case .invalidInput(let message):
            message
        case .transport:
            "Didn't send. Try again."
        case .rejected:
            "Didn't send. Try again."
        }
    }
}

public enum LinearFeedbackConfig: Sendable {
    public static let graphQLURL = URL(string: "https://api.linear.app/graphql")!
    public static let teamID = "3d93e7e8-8101-4130-876a-6d5d83ead7d7"
    public static let projectID = "f99ff471-197f-4bff-ae29-9fb02721cfff"
    public static let backlogStateID = "16a85f56-4c62-4183-aad4-33885a2efa38"
    public static let bugLabelID = "cfbdab95-2d7c-4878-9a68-4ca2c887019b"
    public static let featureLabelID = "53c660b1-d638-4d34-b9ee-cdc7b7843f83"
    public static let testFlightLabelID = "c304fb6f-ee8f-4342-8eb3-f1720088f162"
}

public struct LinearFeedbackClient: Sendable {
    public static let maxCoachHistoryCharacters = 12_000

    private let session: URLSession
    private let apiKeyStore: APIKeyStore

    public init(
        session: URLSession = .shared,
        apiKeyStore: APIKeyStore = APIKeyStore()
    ) {
        self.session = session
        self.apiKeyStore = apiKeyStore
    }

    public func submit(_ draft: LinearFeedbackDraft) async throws -> URL? {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let details = draft.details.trimmingCharacters(in: .whitespacesAndNewlines)
        let fromName = draft.fromName.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.count < 3 { throw LinearFeedbackError.invalidInput("Give it a short title.") }
        if details.count < 8 {
            throw LinearFeedbackError.invalidInput("Say what you want in a sentence or two.")
        }
        if fromName.count < 2 {
            throw LinearFeedbackError.invalidInput("Put your name on it.")
        }

        guard let key = try apiKeyStore.load(kind: .linear)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !key.isEmpty
        else {
            throw LinearFeedbackError.missingKey
        }

        let kindLabel = draft.kind == .bug ? "Bug" : "Feature"
        var descriptionParts = [details, "", "---", "Kind: \(kindLabel)", "From: \(fromName)"]
        if let history = draft.coachHistoryMarkdown?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !history.isEmpty
        {
            let clipped = Self.clipCoachHistory(history)
            descriptionParts.append(contentsOf: ["", "## Coach history", clipped])
        }

        let labelIDs = [
            draft.kind == .bug ? LinearFeedbackConfig.bugLabelID : LinearFeedbackConfig.featureLabelID,
            LinearFeedbackConfig.testFlightLabelID
        ]

        let body: [String: Any] = [
            "query": """
            mutation CreateIssue($input: IssueCreateInput!) {
              issueCreate(input: $input) {
                success
                issue { url }
              }
            }
            """,
            "variables": [
                "input": [
                    "teamId": LinearFeedbackConfig.teamID,
                    "projectId": LinearFeedbackConfig.projectID,
                    "stateId": LinearFeedbackConfig.backlogStateID,
                    "labelIds": labelIDs,
                    "title": String(title.prefix(80)),
                    "description": descriptionParts.joined(separator: "\n")
                ]
            ]
        ]

        var request = URLRequest(url: LinearFeedbackConfig.graphQLURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if key.hasPrefix("lin_api_") {
            request.setValue(key, forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LinearFeedbackError.transport
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw LinearFeedbackError.rejected
        }

        let payload = try JSONDecoder().decode(LinearIssueCreateEnvelope.self, from: data)
        if payload.errors?.isEmpty == false || payload.data?.issueCreate?.success != true {
            throw LinearFeedbackError.rejected
        }
        if let urlString = payload.data?.issueCreate?.issue?.url, let url = URL(string: urlString) {
            return url
        }
        return nil
    }

    public static func clipCoachHistory(_ markdown: String) -> String {
        if markdown.count <= maxCoachHistoryCharacters { return markdown }
        let suffix = markdown.suffix(maxCoachHistoryCharacters)
        return "…truncated…\n\n\(suffix)"
    }
}

private struct LinearIssueCreateEnvelope: Decodable {
    struct GraphQLError: Decodable {
        let message: String?
    }

    struct Issue: Decodable {
        let url: String?
    }

    struct IssueCreate: Decodable {
        let success: Bool?
        let issue: Issue?
    }

    struct Data: Decodable {
        let issueCreate: IssueCreate?
    }

    let errors: [GraphQLError]?
    let data: Data?
}

import Diagnostics
import Foundation
import OSLog

public struct OpenFoodFactsProduct: Sendable, Equatable {
    public let barcode: String
    public let productName: String
    public let brand: String?
    public let per100gKcal: Double
    public let per100gProteinG: Double
    public let per100gCarbsG: Double
    public let per100gFatG: Double
    public let rawJSON: String

    public var displayName: String {
        if let brand, !brand.isEmpty {
            return "\(brand) \(productName)"
        }
        return productName
    }
}

public enum OpenFoodFactsError: Error, Sendable, Equatable {
    case invalidResponse
    case productNotFound
    case requestFailed(String)
}

public protocol OpenFoodFactsClient: Sendable {
    var requestCount: Int { get }

    func fetchProduct(barcode: String) async throws -> OpenFoodFactsProduct
    func search(query: String, pageSize: Int) async throws -> [OpenFoodFactsProduct]
}

enum OpenFoodFactsEndpoint {
    static let userAgent = "Helm/1.0 (iOS; Contact: https://openfoodfacts.org)"
    static let host = "uk.openfoodfacts.org"

    static func productURL(barcode: String) -> URL {
        URL(string: "https://\(host)/api/v2/product/\(barcode).json")!
    }

    static func searchURL(query: String, pageSize: Int) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/cgi/search.pl"
        components.queryItems = [
            URLQueryItem(name: "search_terms", value: query),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: String(pageSize)),
            URLQueryItem(name: "fields", value: "code,product_name,brands,nutriments")
        ]
        return components.url!
    }
}

enum OpenFoodFactsParser {
    static func parseProductResponse(data: Data) throws -> OpenFoodFactsProduct {
        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let status = object["status"] as? Int,
            status == 1,
            let product = object["product"] as? [String: Any]
        else {
            throw OpenFoodFactsError.productNotFound
        }

        guard let barcode = (object["code"] as? String) ?? (product["code"] as? String) else {
            throw OpenFoodFactsError.invalidResponse
        }

        return try parseProductDictionary(product, barcode: barcode, rawJSON: data)
    }

    static func parseSearchResponse(data: Data) throws -> [OpenFoodFactsProduct] {
        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let products = object["products"] as? [[String: Any]]
        else {
            throw OpenFoodFactsError.invalidResponse
        }

        return try products.compactMap { product in
            guard let barcode = product["code"] as? String, !barcode.isEmpty else {
                return nil
            }
            return try? parseProductDictionary(product, barcode: barcode, rawJSON: data)
        }
    }

    private static func parseProductDictionary(
        _ product: [String: Any],
        barcode: String,
        rawJSON: Data
    ) throws -> OpenFoodFactsProduct {
        guard
            let name = product["product_name"] as? String,
            !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw OpenFoodFactsError.invalidResponse
        }

        let nutriments = product["nutriments"] as? [String: Any] ?? [:]
        let kcal = doubleValue(nutriments["energy-kcal_100g"])
            ?? doubleValue(nutriments["energy-kcal"])
            ?? energyKcalFromKJ(nutriments["energy_100g"])
            ?? energyKcalFromKJ(nutriments["energy"])
        guard let kcal else {
            throw OpenFoodFactsError.invalidResponse
        }

        let brand = (product["brands"] as? String)?
            .split(separator: ",")
            .first
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        let rawJSONString = String(data: rawJSON, encoding: .utf8) ?? "{}"

        return OpenFoodFactsProduct(
            barcode: barcode,
            productName: name,
            brand: brand,
            per100gKcal: kcal,
            per100gProteinG: doubleValue(nutriments["proteins_100g"]) ?? 0,
            per100gCarbsG: doubleValue(nutriments["carbohydrates_100g"]) ?? 0,
            per100gFatG: doubleValue(nutriments["fat_100g"]) ?? 0,
            rawJSON: rawJSONString
        )
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let number as Double:
            return number
        case let number as Int:
            return Double(number)
        case let string as String:
            return Double(string)
        default:
            return nil
        }
    }

    private static func energyKcalFromKJ(_ value: Any?) -> Double? {
        guard let kilojoules = doubleValue(value) else { return nil }
        return kilojoules / 4.184
    }
}

public final class LiveOpenFoodFactsClient: OpenFoodFactsClient, @unchecked Sendable {
    private let session: URLSession
    private let lock = NSLock()
    private nonisolated(unsafe) var _requestCount = 0
    private let log = helmLogger(category: .healthKitIngest)

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public var requestCount: Int {
        lock.withLock { _requestCount }
    }

    public func fetchProduct(barcode: String) async throws -> OpenFoodFactsProduct {
        incrementRequestCount()
        let url = OpenFoodFactsEndpoint.productURL(barcode: barcode)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(OpenFoodFactsEndpoint.userAgent, forHTTPHeaderField: "User-Agent")

        log.debug("OFF barcode lookup barcode=\(barcode, privacy: .public)")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw OpenFoodFactsError.invalidResponse
            }
            guard (200 ..< 300).contains(http.statusCode) else {
                throw OpenFoodFactsError.requestFailed("HTTP \(http.statusCode)")
            }
            return try OpenFoodFactsParser.parseProductResponse(data: data)
        } catch let error as OpenFoodFactsError {
            throw error
        } catch {
            Task {
                await DiagnosticsLog.shared.capture(
                    error: error,
                    category: .healthKitIngest,
                    message: "OFF barcode lookup failed",
                    context: ["barcode": barcode]
                )
            }
            throw OpenFoodFactsError.requestFailed(String(describing: type(of: error)))
        }
    }

    public func search(query: String, pageSize: Int) async throws -> [OpenFoodFactsProduct] {
        incrementRequestCount()
        let url = OpenFoodFactsEndpoint.searchURL(query: query, pageSize: pageSize)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(OpenFoodFactsEndpoint.userAgent, forHTTPHeaderField: "User-Agent")

        log.debug("OFF text search queryLength=\(query.count, privacy: .public)")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw OpenFoodFactsError.invalidResponse
            }
            guard (200 ..< 300).contains(http.statusCode) else {
                throw OpenFoodFactsError.requestFailed("HTTP \(http.statusCode)")
            }
            return try OpenFoodFactsParser.parseSearchResponse(data: data)
        } catch let error as OpenFoodFactsError {
            throw error
        } catch {
            Task {
                await DiagnosticsLog.shared.capture(
                    error: error,
                    category: .healthKitIngest,
                    message: "OFF text search failed",
                    context: ["queryLength": String(query.count)]
                )
            }
            throw OpenFoodFactsError.requestFailed(String(describing: type(of: error)))
        }
    }

    private func incrementRequestCount() {
        lock.withLock { _requestCount += 1 }
    }
}

public final class FixtureOpenFoodFactsClient: OpenFoodFactsClient, @unchecked Sendable {
    private let bundle: Bundle
    private let lock = NSLock()
    private nonisolated(unsafe) var _requestCount = 0

    public init(bundle: Bundle) {
        self.bundle = bundle
    }

    public var requestCount: Int {
        lock.withLock { _requestCount }
    }

    public func fetchProduct(barcode: String) async throws -> OpenFoodFactsProduct {
        lock.withLock { _requestCount += 1 }
        let fixtureName = barcode == "5050159001234" ? "off_product_grenade" : "off_product_not_found"
        guard let url = bundle.url(forResource: fixtureName, withExtension: "json") else {
            throw OpenFoodFactsError.requestFailed("Missing \(fixtureName).json fixture")
        }
        let data = try Data(contentsOf: url)
        return try OpenFoodFactsParser.parseProductResponse(data: data)
    }

    public func search(query: String, pageSize: Int) async throws -> [OpenFoodFactsProduct] {
        lock.withLock { _requestCount += 1 }
        let normalized = query.lowercased()
        let fixtureName: String
        if normalized.contains("grenade") {
            fixtureName = "off_search_grenade"
        } else {
            fixtureName = "off_search_empty"
        }
        guard let url = bundle.url(forResource: fixtureName, withExtension: "json") else {
            throw OpenFoodFactsError.requestFailed("Missing \(fixtureName).json fixture")
        }
        let data = try Data(contentsOf: url)
        return Array(try OpenFoodFactsParser.parseSearchResponse(data: data).prefix(pageSize))
    }
}

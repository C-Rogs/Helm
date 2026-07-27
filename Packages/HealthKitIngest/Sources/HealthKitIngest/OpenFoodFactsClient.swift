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
    public let servingSizeLabel: String?
    public let servingQuantityGrams: Double?
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
    case rateLimited
    case requestFailed(String)
}

public protocol OpenFoodFactsClient: Sendable {
    var requestCount: Int { get }

    func fetchProduct(barcode: String) async throws -> OpenFoodFactsProduct
    func search(query: String, pageSize: Int) async throws -> [OpenFoodFactsProduct]
}

enum OpenFoodFactsEndpoint {
    static let userAgent = "Helm/1.0 (iOS; Contact: https://openfoodfacts.org)"
    static let productHost = "uk.openfoodfacts.org"
    static let searchHost = "search.openfoodfacts.org"
    static let searchFields = "code,product_name,brands,nutriments,serving_size,serving_quantity,product_quantity"

    static func productURL(barcode: String) -> URL {
        URL(string: "https://\(productHost)/api/v2/product/\(barcode).json")!
    }

    static func searchALiciousURL(query: String, pageSize: Int) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = searchHost
        components.path = "/search"
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "langs", value: "en"),
            URLQueryItem(name: "page_size", value: String(pageSize)),
            URLQueryItem(name: "boost_phrase", value: "true"),
            URLQueryItem(name: "fields", value: searchFields)
        ]
        return components.url!
    }

    static func legacySearchURL(query: String, pageSize: Int) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = productHost
        components.path = "/cgi/search.pl"
        components.queryItems = [
            URLQueryItem(name: "search_terms", value: query),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: String(pageSize)),
            URLQueryItem(name: "fields", value: searchFields)
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

    static func kcalPer100g(fromSnapshotJSON json: String) -> Double? {
        guard
            let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        let product = (object["product"] as? [String: Any]) ?? object
        guard let nutriments = product["nutriments"] as? [String: Any] else {
            return nil
        }
        return energyKcalPer100g(from: nutriments)
    }

    static func parseSearchALiciousResponse(data: Data) throws -> [OpenFoodFactsProduct] {
        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let hits = object["hits"] as? [[String: Any]]
        else {
            throw OpenFoodFactsError.invalidResponse
        }

        return try hits.compactMap { hit in
            guard let barcode = hit["code"] as? String, !barcode.isEmpty else {
                return nil
            }
            let hitData = try JSONSerialization.data(withJSONObject: hit)
            return try? parseProductDictionary(hit, barcode: barcode, rawJSON: hitData)
        }
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
            let productData = try JSONSerialization.data(withJSONObject: product)
            return try? parseProductDictionary(product, barcode: barcode, rawJSON: productData)
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
        let kcal = energyKcalPer100g(from: nutriments)
        guard let kcal else {
            throw OpenFoodFactsError.invalidResponse
        }

        let brand = parseBrand(from: product)

        let servingSizeLabel = (product["serving_size"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let servingQuantityGrams = doubleValue(product["serving_quantity"])
            ?? doubleValue(product["product_quantity"])

        let rawJSONString = String(data: rawJSON, encoding: .utf8) ?? "{}"

        return OpenFoodFactsProduct(
            barcode: barcode,
            productName: name,
            brand: brand,
            per100gKcal: kcal,
            per100gProteinG: doubleValue(nutriments["proteins_100g"]) ?? 0,
            per100gCarbsG: doubleValue(nutriments["carbohydrates_100g"]) ?? 0,
            per100gFatG: doubleValue(nutriments["fat_100g"]) ?? 0,
            servingSizeLabel: servingSizeLabel?.isEmpty == false ? servingSizeLabel : nil,
            servingQuantityGrams: servingQuantityGrams,
            rawJSON: rawJSONString
        )
    }

    private static func parseBrand(from product: [String: Any]) -> String? {
        switch product["brands"] {
        case let brands as String:
            return brands
                .split(separator: ",")
                .first
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .flatMap { $0.isEmpty ? nil : $0 }
        case let brands as [Any]:
            return brands.compactMap { item -> String? in
                guard let brand = item as? String else { return nil }
                let trimmed = brand.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }.first
        default:
            return nil
        }
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

    private static func energyKcalPer100g(from nutriments: [String: Any]) -> Double? {
        let kcalField = doubleValue(nutriments["energy-kcal_100g"])
        let kjField = doubleValue(nutriments["energy-kj_100g"]) ?? doubleValue(nutriments["energy_100g"])

        if let kcal = kcalField, let kj = kjField {
            let kcalFromKJ = kj / 4.184
            if abs(kcal - kj) < abs(kcal - kcalFromKJ) {
                return kcalFromKJ
            }
            return kcal
        }
        if let kcal = kcalField {
            return kcal
        }
        if let kj = kjField {
            return kj / 4.184
        }

        let servingKcal = doubleValue(nutriments["energy-kcal"])
        let servingKJ = doubleValue(nutriments["energy-kj"]) ?? doubleValue(nutriments["energy"])
        if let kcal = servingKcal, let kj = servingKJ {
            let kcalFromKJ = kj / 4.184
            if abs(kcal - kj) < abs(kcal - kcalFromKJ) {
                return kcalFromKJ
            }
            return kcal
        }
        if let kcal = servingKcal {
            return kcal
        }
        return energyKcalFromKJ(nutriments["energy-kj"]) ?? energyKcalFromKJ(nutriments["energy"])
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
                if http.statusCode == 429 {
                    throw OpenFoodFactsError.rateLimited
                }
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
        log.debug("OFF text search queryLength=\(query.count, privacy: .public)")

        do {
            return try await performSearch(
                url: OpenFoodFactsEndpoint.searchALiciousURL(query: query, pageSize: pageSize),
                parse: OpenFoodFactsParser.parseSearchALiciousResponse
            )
        } catch OpenFoodFactsError.rateLimited {
            throw OpenFoodFactsError.rateLimited
        } catch let primaryError {
            log.debug("Search-a-licious failed, trying legacy OFF search")
            Task {
                await DiagnosticsLog.shared.capture(
                    error: primaryError,
                    category: .healthKitIngest,
                    message: "Search-a-licious failed; falling back to legacy OFF search",
                    context: ["queryLength": String(query.count)]
                )
            }

            incrementRequestCount()
            do {
                return try await performSearch(
                    url: OpenFoodFactsEndpoint.legacySearchURL(query: query, pageSize: pageSize),
                    parse: OpenFoodFactsParser.parseSearchResponse
                )
            } catch {
                throw primaryError
            }
        }
    }

    private func performSearch(
        url: URL,
        parse: (Data) throws -> [OpenFoodFactsProduct]
    ) async throws -> [OpenFoodFactsProduct] {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(OpenFoodFactsEndpoint.userAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw OpenFoodFactsError.invalidResponse
            }
            guard (200 ..< 300).contains(http.statusCode) else {
                if http.statusCode == 429 {
                    throw OpenFoodFactsError.rateLimited
                }
                throw OpenFoodFactsError.requestFailed("HTTP \(http.statusCode)")
            }
            return try parse(data)
        } catch let error as OpenFoodFactsError {
            throw error
        } catch {
            Task {
                await DiagnosticsLog.shared.capture(
                    error: error,
                    category: .healthKitIngest,
                    message: "OFF text search failed",
                    context: [:]
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
        let fixtureName: String
        switch barcode {
        case "5050159001234":
            fixtureName = "off_product_grenade"
        case "3033490085558":
            fixtureName = "off_product_danone_getpro"
        default:
            fixtureName = "off_product_not_found"
        }
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
        } else if normalized.contains("getpro") {
            fixtureName = "off_search_getpro"
        } else {
            fixtureName = "off_search_empty"
        }
        guard let url = bundle.url(forResource: fixtureName, withExtension: "json") else {
            throw OpenFoodFactsError.requestFailed("Missing \(fixtureName).json fixture")
        }
        let data = try Data(contentsOf: url)
        return Array(try OpenFoodFactsParser.parseSearchALiciousResponse(data: data).prefix(pageSize))
    }
}

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
    public let macrosKnown: Bool

    public var displayName: String {
        if let brand, !brand.isEmpty, !Self.containsBrand(productName: productName, brand: brand) {
            return "\(brand) \(productName)"
        }
        return productName
    }

    private static func containsBrand(productName: String, brand: String) -> Bool {
        let nameTokens = normalizedTokens(productName)
        let brandTokens = normalizedTokens(brand)
        guard !brandTokens.isEmpty, brandTokens.count <= nameTokens.count else { return false }

        for start in 0 ... (nameTokens.count - brandTokens.count) {
            if Array(nameTokens[start ..< start + brandTokens.count]) == brandTokens {
                return true
            }
        }
        return false
    }

    private static func normalizedTokens(_ value: String) -> [String] {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
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
    static let userAgent = "Signal/1.0 (iOS; Contact: https://openfoodfacts.org)"
    static let productHost = "uk.openfoodfacts.org"
    static let searchHost = "search.openfoodfacts.org"
    static let searchFields = "code,product_name,brands,nutriments,serving_size,serving_quantity,product_quantity"

    static func productURL(barcode: String) -> URL {
        URL(string: "https://\(productHost)/api/v2/product/\(barcode).json")!
    }

    static func searchALiciousURL(query: String, pageSize: Int, ukOnly: Bool = false) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = searchHost
        components.path = "/search"
        let searchQuery = ukOnly
            ? "\(query) countries_tags:\"en:united-kingdom\""
            : query
        components.queryItems = [
            URLQueryItem(name: "q", value: searchQuery),
            URLQueryItem(name: "langs", value: "en"),
            URLQueryItem(name: "page_size", value: String(pageSize)),
            URLQueryItem(name: "boost_phrase", value: "true"),
            URLQueryItem(name: "fields", value: searchFields)
        ]
        return components.url!
    }

    static func legacySearchURL(query: String, pageSize: Int, ukOnly: Bool = false) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = productHost
        components.path = "/cgi/search.pl"
        var queryItems = [
            URLQueryItem(name: "search_terms", value: query),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: String(pageSize)),
            URLQueryItem(name: "fields", value: searchFields)
        ]
        if ukOnly {
            queryItems.append(contentsOf: [
                URLQueryItem(name: "tagtype_0", value: "countries"),
                URLQueryItem(name: "tag_contains_0", value: "contains"),
                URLQueryItem(name: "tag_0", value: "united-kingdom")
            ])
        }
        components.queryItems = queryItems
        return components.url!
    }
}

struct OpenFoodFactsParsedMacros: Equatable {
    var per100gKcal: Double?
    var per100gProteinG: Double?
    var per100gCarbsG: Double?
    var per100gFatG: Double?

    var hasAny: Bool {
        per100gKcal != nil || per100gProteinG != nil || per100gCarbsG != nil || per100gFatG != nil
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

        let parsed = parsedMacros(from: product)
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
            per100gKcal: parsed.per100gKcal ?? 0,
            per100gProteinG: parsed.per100gProteinG ?? 0,
            per100gCarbsG: parsed.per100gCarbsG ?? 0,
            per100gFatG: parsed.per100gFatG ?? 0,
            servingSizeLabel: servingSizeLabel?.isEmpty == false ? servingSizeLabel : nil,
            servingQuantityGrams: servingQuantityGrams,
            rawJSON: rawJSONString,
            macrosKnown: parsed.per100gKcal != nil
        )
    }

    /// Macros recovered from a stored OFF snapshot. Nil fields were absent, so callers keep cached numbers.
    static func macros(fromSnapshotJSON json: String) -> OpenFoodFactsParsedMacros? {
        guard
            let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        let product = (object["product"] as? [String: Any]) ?? object
        let parsed = parsedMacros(from: product)
        guard parsed.hasAny else { return nil }
        return parsed
    }

    private static func parsedMacros(from product: [String: Any]) -> OpenFoodFactsParsedMacros {
        let nutriments = product["nutriments"] as? [String: Any] ?? [:]
        let servingGrams = servingGrams(from: product)
        return OpenFoodFactsParsedMacros(
            per100gKcal: energyKcalPer100g(from: nutriments, servingGrams: servingGrams),
            per100gProteinG: nutrientPer100g(
                nutriments,
                flatField: "proteins_100g",
                nestedKey: "proteins",
                servingKey: "proteins_serving",
                servingGrams: servingGrams
            ),
            per100gCarbsG: nutrientPer100g(
                nutriments,
                flatField: "carbohydrates_100g",
                nestedKey: "carbohydrates",
                servingKey: "carbohydrates_serving",
                servingGrams: servingGrams
            ),
            per100gFatG: nutrientPer100g(
                nutriments,
                flatField: "fat_100g",
                nestedKey: "fat",
                servingKey: "fat_serving",
                servingGrams: servingGrams
            )
        )
    }

    private static func servingGrams(from product: [String: Any]) -> Double? {
        if let quantity = doubleValue(product["serving_quantity"]), quantity > 0 {
            return quantity
        }
        if let label = product["serving_size"] as? String {
            return grams(fromServingLabel: label)
        }
        return nil
    }

    private static func grams(fromServingLabel label: String) -> Double? {
        let pattern = #"(\d+(?:\.\d+)?)\s*g\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(label.startIndex..., in: label)
        guard
            let match = regex.firstMatch(in: label, options: [], range: range),
            let valueRange = Range(match.range(at: 1), in: label)
        else {
            return nil
        }
        return Double(label[valueRange])
    }

    /// Flat `*_100g`, nested `{ "100g": }`, then serving value scaled to 100 g.
    private static func nutrientPer100g(
        _ nutriments: [String: Any],
        flatField: String,
        nestedKey: String,
        servingKey: String,
        servingGrams: Double?
    ) -> Double? {
        if let flat = doubleValue(nutriments[flatField]) {
            return flat
        }
        if let nested = nutriments[nestedKey] as? [String: Any] {
            if let per100 = doubleValue(nested["100g"]) {
                return per100
            }
            if let serving = doubleValue(nested["serving"]),
               let servingGrams, servingGrams > 0 {
                return serving / servingGrams * 100
            }
        }
        if let serving = doubleValue(nutriments[servingKey]),
           let servingGrams, servingGrams > 0 {
            return serving / servingGrams * 100
        }
        return nil
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
        case let number as NSNumber:
            // JSON booleans bridge as NSNumber. Nutriment fields are numeric.
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return nil
            }
            return number.doubleValue
        case let string as String:
            return Double(string)
        default:
            return nil
        }
    }

    private static func energyKcalPer100g(
        from nutriments: [String: Any],
        servingGrams: Double? = nil
    ) -> Double? {
        if let nested = nutriments["energy-kcal"] as? [String: Any],
           let per100 = doubleValue(nested["100g"]) {
            return per100
        }
        if let nested = (nutriments["energy-kj"] as? [String: Any]) ?? (nutriments["energy"] as? [String: Any]),
           let per100 = doubleValue(nested["100g"]) {
            return per100 / 4.184
        }

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
        if let serving = doubleValue(nutriments["energy-kcal_serving"]),
           let servingGrams, servingGrams > 0 {
            return serving / servingGrams * 100
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
        log.debug("OFF text search queryLength=\(query.count, privacy: .public)")

        var products: [OpenFoodFactsProduct] = []
        var firstError: Error?

        do {
            products = try await searchEndpoint(query: query, pageSize: pageSize, ukOnly: true)
        } catch OpenFoodFactsError.rateLimited {
            throw OpenFoodFactsError.rateLimited
        } catch {
            firstError = error
        }

        do {
            let globalProducts = try await searchEndpoint(query: query, pageSize: pageSize, ukOnly: false)
            var seen = Set(products.map(\.barcode))
            products.append(contentsOf: globalProducts.filter { seen.insert($0.barcode).inserted })
        } catch OpenFoodFactsError.rateLimited {
            if products.isEmpty {
                throw OpenFoodFactsError.rateLimited
            }
        } catch {
            if products.isEmpty {
                throw firstError ?? error
            }
        }

        // Keep both pools for caller-side relevance ranking. The resolver caps
        // display results after comparing UK-biased and global matches.
        return products
    }

    private func searchEndpoint(
        query: String,
        pageSize: Int,
        ukOnly: Bool
    ) async throws -> [OpenFoodFactsProduct] {
        incrementRequestCount()
        do {
            return try await performSearch(
                url: OpenFoodFactsEndpoint.searchALiciousURL(
                    query: query,
                    pageSize: pageSize,
                    ukOnly: ukOnly
                ),
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
                    context: [
                        "queryLength": String(query.count),
                        "ukOnly": String(ukOnly)
                    ]
                )
            }

            incrementRequestCount()
            do {
                return try await performSearch(
                    url: OpenFoodFactsEndpoint.legacySearchURL(
                        query: query,
                        pageSize: pageSize,
                        ukOnly: ukOnly
                    ),
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

import Foundation

/// Where the regional report comes from.
protocol AirNowProviding: AnyObject {
    var label: String { get }
    func currentObservation() async throws -> RegionalAQI?
}

/// A fixed, clearly labelled number until there is an API key in Secrets.plist.
final class PlaceholderAirNow: AirNowProviding {
    let label = "Placeholder"

    func currentObservation() async throws -> RegionalAQI? {
        let topOfHour = Calendar.current.dateInterval(of: .hour, for: Date())?.start ?? Date()
        return RegionalAQI(
            aqi: 42, categoryNumber: 1, categoryName: "Good", parameter: "PM2.5",
            reportingArea: "Evansville", stateCode: "IN", observed: topOfHour, isPlaceholder: true
        )
    }
}

enum AirNowError: LocalizedError {
    case badURL
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .badURL: "Could not build the AirNow request."
        case .httpStatus(let code): "AirNow answered with HTTP \(code)."
        }
    }
}

/// The EPA's AirNow API. Free key at docs.airnowapi.org.
///
/// First task from the plan: pull one real response and confirm the endpoint, fields, units and
/// observation time. The field names below follow AirNow's documentation and are unverified until then.
final class AirNowClient: AirNowProviding {
    let label = "AirNow API"

    private let apiKey: String
    private let zipCode: String
    private let distanceMiles: Int
    private let session: URLSession

    init(apiKey: String, zipCode: String = "47708", distanceMiles: Int = 25, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.zipCode = zipCode
        self.distanceMiles = distanceMiles
        self.session = session
    }

    func currentObservation() async throws -> RegionalAQI? {
        let observations = try await fetchObservations()
        return AirNowClient.pick(from: observations)?.regionalAQI
    }

    /// AirNow returns one row per pollutant; overall AQI is the highest valid index.
    static func pick(from observations: [Observation]) -> Observation? {
        observations.filter { $0.aqi >= 0 && (1...6).contains($0.category.number) && $0.observedDate != .distantPast }.max { $0.aqi < $1.aqi }
    }

    func fetchObservations() async throws -> [Observation] {
        var components = URLComponents(string: "https://www.airnowapi.org/aq/observation/zipCode/current/")
        components?.queryItems = [
            URLQueryItem(name: "format", value: "application/json"),
            URLQueryItem(name: "zipCode", value: zipCode),
            URLQueryItem(name: "distance", value: String(distanceMiles)),
            URLQueryItem(name: "API_KEY", value: apiKey),
        ]
        guard let url = components?.url else { throw AirNowError.badURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AirNowError.httpStatus(http.statusCode)
        }
        return try JSONDecoder().decode([Observation].self, from: data)
    }

    /// One row of AirNow's current-observation response. Keys are AirNow's own.
    struct Observation: Decodable, Sendable {
        /// "2026-09-19 " (AirNow includes a trailing space).
        let dateObserved: String
        /// 0–23, in the reporting area's local time.
        let hourObserved: Int
        /// e.g. "EST". AirNow is believed to report standard time year-round; confirm with a real response.
        let localTimeZone: String
        let reportingArea: String
        let stateCode: String
        /// "PM2.5", "O3" or "PM10".
        let parameterName: String
        let aqi: Int
        let category: Category

        struct Category: Decodable, Sendable {
            let number: Int
            let name: String

            enum CodingKeys: String, CodingKey {
                case number = "Number"
                case name = "Name"
            }
        }

        enum CodingKeys: String, CodingKey {
            case dateObserved = "DateObserved"
            case hourObserved = "HourObserved"
            case localTimeZone = "LocalTimeZone"
            case reportingArea = "ReportingArea"
            case stateCode = "StateCode"
            case parameterName = "ParameterName"
            case aqi = "AQI"
            case category = "Category"
        }

        var observedDate: Date {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH"
            formatter.timeZone = TimeZone(abbreviation: localTimeZone) ?? .current
            let text = dateObserved.trimmingCharacters(in: .whitespaces) + " " + String(hourObserved)
            return formatter.date(from: text) ?? .distantPast
        }

        var regionalAQI: RegionalAQI {
            RegionalAQI(
                aqi: aqi, categoryNumber: category.number, categoryName: category.name,
                parameter: parameterName, reportingArea: reportingArea, stateCode: stateCode,
                observed: observedDate, isPlaceholder: false
            )
        }
    }
}

enum AirNowProvider {
    /// AirNow with a configured key, otherwise the explicitly labeled CAMS regional model.
    static func makeDefault(bundle: Bundle = .main) -> AirNowProviding {
        guard let url = bundle.url(forResource: "Secrets", withExtension: "plist"),
              let dictionary = NSDictionary(contentsOf: url) as? [String: Any],
              let key = dictionary["AIRNOW_API_KEY"] as? String,
              !key.isEmpty
        else {
            return OpenMeteoClient()
        }
        let zip = (dictionary["AIRNOW_ZIP"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "47708"
        return AirNowClient(apiKey: key, zipCode: zip)
    }
}

/// Regional CAMS model estimate for the project's configured city, not a local EPA monitor.
/// US AQI is a dimensionless index supplied by Open-Meteo; PM2.5 is a separate µg/m³ value.
final class OpenMeteoClient: AirNowProviding {
    let label = "Open-Meteo · CAMS"
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func currentObservation() async throws -> RegionalAQI? {
        let url = URL(string: "https://air-quality-api.open-meteo.com/v1/air-quality?latitude=37.97&longitude=-87.57&current=us_aqi,pm2_5&timeformat=unixtime&domains=cams_global")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AirNowError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try Self.decode(data)
    }

    static func decode(_ data: Data, now: Date = Date()) throws -> RegionalAQI {
        let result = try JSONDecoder().decode(Response.self, from: data)
        guard result.current_units.time == "unixtime", result.current_units.us_aqi == "USAQI",
              ["μg/m³", "µg/m³"].contains(result.current_units.pm2_5),
              let aqi = result.current.us_aqi, aqi.isFinite, aqi >= 0, aqi <= 10_000,
              result.current.time.isFinite else { throw RegionalError.invalidReport }
        let time = Date(timeIntervalSince1970: result.current.time)
        guard time <= now.addingTimeInterval(3600), now.timeIntervalSince(time) <= 3 * 3600 else {
            throw RegionalError.outdated
        }
        let index = Int(aqi.rounded())
        let category = index <= 50 ? 1 : index <= 100 ? 2 : index <= 150 ? 3 : index <= 200 ? 4 : index <= 300 ? 5 : 6
        let names = ["Good", "Moderate", "Unhealthy for sensitive groups", "Unhealthy", "Very unhealthy", "Hazardous"]
        return RegionalAQI(aqi: index, categoryNumber: category, categoryName: names[category - 1],
            parameter: "Overall US AQI", reportingArea: "Evansville", stateCode: "IN", observed: time,
            isPlaceholder: false, isModeled: true, sourceLabel: "Open-Meteo · CAMS", pm25: result.current.pm2_5.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil })
    }

    struct Response: Decodable {
        struct Current: Decodable { let time: Double; let us_aqi: Double?; let pm2_5: Double? }
        struct Units: Decodable { let time: String; let us_aqi: String; let pm2_5: String }
        let current: Current
        let current_units: Units
    }
}

enum RegionalError: LocalizedError {
    case invalidReport, outdated
    var errorDescription: String? {
        switch self {
        case .invalidReport: "The regional service returned missing data or unexpected units."
        case .outdated: "The regional service has no current report. Try again later."
        }
    }
}

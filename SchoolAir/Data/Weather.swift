import Foundation
import Observation

struct WeatherReport: Sendable {
    struct Current: Sendable {
        let at: Date
        let temperature: Double
        let feelsLike: Double?
        let humidity: Double?
        let wind: Double?
        let code: Int?
        let isDay: Bool
    }
    struct Hour: Identifiable, Sendable {
        let at: Date
        let temperature: Double?
        let rainChance: Double?
        let code: Int?
        let isDay: Bool
        var id: Date { at }
    }
    struct Day: Identifiable, Sendable {
        let at: Date
        let high: Double?
        let low: Double?
        let rainChance: Double?
        let uv: Double?
        let sunrise: Date?
        let sunset: Date?
        let code: Int?
        var id: Date { at }
    }
    let current: Current
    let hours: [Hour]
    let days: [Day]
    static let area = "Evansville, IN"
    static let timeZone = TimeZone(identifier: "America/Chicago")!
    func isStale(at now: Date) -> Bool { now.timeIntervalSince(current.at) > 90 * 60 }
    func nextHours(at now: Date) -> [Hour] { Array(hours.filter { $0.at >= now.addingTimeInterval(-3600) }.prefix(24)) }
    func upcomingDays(at now: Date) -> [Day] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.timeZone
        return days.filter { $0.at >= calendar.startOfDay(for: now) }
    }
}

enum WeatherUnits: String, CaseIterable, Identifiable {
    case fahrenheit, celsius
    var id: String { rawValue }
    var label: String { self == .fahrenheit ? "°F" : "°C" }
    func temperature(_ celsius: Double) -> Double { self == .fahrenheit ? celsius * 9 / 5 + 32 : celsius }
    func temperatureText(_ value: Double?) -> String { value.map { "\(Int(temperature($0).rounded()))°" } ?? "—" }
    func windText(_ kmh: Double?) -> String {
        guard let kmh else { return "—" }
        return self == .fahrenheit ? "\(Int((kmh / 1.609344).rounded())) mph" : "\(Int(kmh.rounded())) km/h"
    }
}

struct WeatherCondition {
    let label: String
    let symbol: String
    static func describe(_ code: Int?, isDay: Bool = true) -> Self {
        switch code {
        case 0: .init(label: "Clear", symbol: isDay ? "sun.max.fill" : "moon.stars.fill")
        case 1: .init(label: "Mostly clear", symbol: isDay ? "sun.max.fill" : "moon.stars.fill")
        case 2: .init(label: "Partly cloudy", symbol: isDay ? "cloud.sun.fill" : "cloud.moon.fill")
        case 3: .init(label: "Cloudy", symbol: "cloud.fill")
        case 45, 48: .init(label: "Fog", symbol: "cloud.fog.fill")
        case 51, 53, 55: .init(label: "Drizzle", symbol: "cloud.drizzle.fill")
        case 56, 57: .init(label: "Freezing drizzle", symbol: "cloud.sleet.fill")
        case 61, 63, 65: .init(label: "Rain", symbol: "cloud.rain.fill")
        case 66, 67: .init(label: "Freezing rain", symbol: "cloud.sleet.fill")
        case 71, 73, 75, 77: .init(label: "Snow", symbol: "cloud.snow.fill")
        case 80, 81, 82: .init(label: "Rain showers", symbol: "cloud.rain.fill")
        case 85, 86: .init(label: "Snow showers", symbol: "cloud.snow.fill")
        case 95, 96, 99: .init(label: "Thunderstorms", symbol: "cloud.bolt.rain.fill")
        default: .init(label: "Conditions unavailable", symbol: "cloud")
        }
    }
}

enum WeatherError: LocalizedError {
    case invalidReport, http(Int), stale
    var errorDescription: String? {
        switch self {
        case .invalidReport: "The forecast response was incomplete. Please try again."
        case .http: "Weather is temporarily unavailable. Pull down to retry."
        case .stale: "The provider hasn't returned a current forecast yet."
        }
    }
}

struct WeatherClient {
    static var url: URL {
        var url = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        url.queryItems = [
            .init(name: "latitude", value: "37.97"), .init(name: "longitude", value: "-87.57"),
            .init(name: "current", value: "temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m"),
            .init(name: "hourly", value: "temperature_2m,precipitation_probability,weather_code,is_day"),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,uv_index_max,precipitation_probability_max"),
            .init(name: "temperature_unit", value: "celsius"), .init(name: "wind_speed_unit", value: "kmh"),
            .init(name: "timezone", value: "America/Chicago"), .init(name: "timeformat", value: "unixtime"),
            .init(name: "forecast_days", value: "7")
        ]
        return url.url!
    }
    func fetch() async throws -> WeatherReport {
        var request = URLRequest(url: Self.url)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { throw WeatherError.http((response as? HTTPURLResponse)?.statusCode ?? 0) }
        return try Self.decode(data, now: Date())
    }
    static func decode(_ data: Data, now: Date) throws -> WeatherReport {
        let p = try JSONDecoder().decode(Payload.self, from: data)
        let c = p.current, h = p.hourly, d = p.daily
        guard p.timezone == "America/Chicago",
              p.current_units["time"] == "unixtime", p.current_units["temperature_2m"] == "°C",
              p.current_units["apparent_temperature"] == "°C", p.current_units["relative_humidity_2m"] == "%",
              p.current_units["wind_speed_10m"] == "km/h",
              p.hourly_units["time"] == "unixtime", p.hourly_units["temperature_2m"] == "°C",
              p.hourly_units["precipitation_probability"] == "%",
              p.daily_units["time"] == "unixtime", p.daily_units["temperature_2m_max"] == "°C",
              p.daily_units["temperature_2m_min"] == "°C", p.daily_units["precipitation_probability_max"] == "%",
              p.daily_units["sunrise"] == "unixtime", p.daily_units["sunset"] == "unixtime",
              !h.time.isEmpty, !d.time.isEmpty,
              [h.temperature_2m.count, h.precipitation_probability.count, h.weather_code.count, h.is_day.count].allSatisfy({ $0 == h.time.count }),
              [d.temperature_2m_max.count, d.temperature_2m_min.count, d.weather_code.count, d.sunrise.count, d.sunset.count, d.uv_index_max.count, d.precipitation_probability_max.count].allSatisfy({ $0 == d.time.count }),
              zip(h.time, h.time.dropFirst()).allSatisfy({ $0 < $1 }),
              zip(d.time, d.time.dropFirst()).allSatisfy({ $0 < $1 }),
              let temperature = valid(c.temperature_2m, in: -100...70) else { throw WeatherError.invalidReport }
        let at = Date(timeIntervalSince1970: c.time)
        guard now.timeIntervalSince(at) <= 90 * 60, now.timeIntervalSince(at) >= -30 * 60 else { throw WeatherError.stale }
        let current = WeatherReport.Current(at: at, temperature: temperature, feelsLike: valid(c.apparent_temperature, in: -150...100),
                                            humidity: valid(c.relative_humidity_2m, in: 0...100), wind: valid(c.wind_speed_10m, in: 0...500),
                                            code: c.weather_code, isDay: c.is_day == 1)
        let hours = h.time.indices.map { i in
            WeatherReport.Hour(at: Date(timeIntervalSince1970: h.time[i]), temperature: valid(h.temperature_2m[i], in: -100...70),
                               rainChance: valid(h.precipitation_probability[i], in: 0...100), code: h.weather_code[i], isDay: h.is_day[i] == 1)
        }
        let days = d.time.indices.map { i in
            WeatherReport.Day(at: Date(timeIntervalSince1970: d.time[i]), high: valid(d.temperature_2m_max[i], in: -100...70),
                              low: valid(d.temperature_2m_min[i], in: -100...70), rainChance: valid(d.precipitation_probability_max[i], in: 0...100),
                              uv: valid(d.uv_index_max[i], in: 0...50), sunrise: d.sunrise[i].map(Date.init(timeIntervalSince1970:)),
                              sunset: d.sunset[i].map(Date.init(timeIntervalSince1970:)), code: d.weather_code[i])
        }
        return WeatherReport(current: current, hours: hours, days: days)
    }
    private static func valid(_ value: Double?, in range: ClosedRange<Double>) -> Double? {
        guard let value, value.isFinite, range.contains(value) else { return nil }; return value
    }
    private struct Payload: Decodable {
        let timezone: String
        let current_units, hourly_units, daily_units: [String: String]
        let current: Current
        let hourly: Hourly
        let daily: Daily
        struct Current: Decodable {
            let time: Double
            let temperature_2m, relative_humidity_2m, apparent_temperature, wind_speed_10m: Double?
            let is_day, weather_code: Int?
        }
        struct Hourly: Decodable {
            let time: [Double]
            let temperature_2m, precipitation_probability: [Double?]
            let weather_code, is_day: [Int?]
        }
        struct Daily: Decodable {
            let time: [Double]
            let temperature_2m_max, temperature_2m_min, sunrise, sunset, uv_index_max, precipitation_probability_max: [Double?]
            let weather_code: [Int?]
        }
    }
}

@MainActor @Observable
final class WeatherStore {
    private(set) var report: WeatherReport?
    private(set) var error: String?
    private(set) var loading = false
    private var fetchedAt: Date?
    private var lastAttempt: Date?
    private let load: () async throws -> WeatherReport
    private let clock: () -> Date
    init(load: @escaping () async throws -> WeatherReport = { try await WeatherClient().fetch() }, clock: @escaping () -> Date = Date.init) {
        self.load = load
        self.clock = clock
    }
    func refresh(force: Bool = false) async {
        guard !loading else { return }
        if !force {
            if let fetchedAt, clock().timeIntervalSince(fetchedAt) < 10 * 60 { return }
            if error != nil, let lastAttempt, clock().timeIntervalSince(lastAttempt) < 60 { return }
        }
        lastAttempt = clock()
        loading = true
        defer { loading = false }
        do {
            let next = try await load()
            guard !Task.isCancelled else { return }
            report = next
            fetchedAt = clock()
            error = nil
        } catch is CancellationError { }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

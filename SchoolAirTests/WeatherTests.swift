import XCTest
@testable import SchoolAir

final class WeatherTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func fixture() -> [String: Any] {
        let t = now.timeIntervalSince1970
        return [
            "timezone": "America/Chicago",
            "current_units": ["time": "unixtime", "temperature_2m": "°C", "apparent_temperature": "°C", "relative_humidity_2m": "%", "wind_speed_10m": "km/h"],
            "hourly_units": ["time": "unixtime", "temperature_2m": "°C", "precipitation_probability": "%"],
            "daily_units": ["time": "unixtime", "temperature_2m_max": "°C", "temperature_2m_min": "°C", "precipitation_probability_max": "%", "sunrise": "unixtime", "sunset": "unixtime"],
            "current": ["time": t, "temperature_2m": 10.0, "apparent_temperature": 8.0, "relative_humidity_2m": 70, "wind_speed_10m": 16.09344, "weather_code": 0, "is_day": 0],
            "hourly": ["time": [t, t+3600], "temperature_2m": [10, 11], "precipitation_probability": [0, 50], "weather_code": [0, 61], "is_day": [0, 1]],
            "daily": ["time": [t], "temperature_2m_max": [15], "temperature_2m_min": [5], "precipitation_probability_max": [50], "uv_index_max": [3.2], "sunrise": [t+3600], "sunset": [t+12*3600], "weather_code": [61]]
        ]
    }
    private func decode(_ fixture: [String: Any]) throws -> WeatherReport {
        try WeatherClient.decode(JSONSerialization.data(withJSONObject: fixture), now: now)
    }
    func testRealContractSeparatesCurrentHourlyAndDailyMeasurements() throws {
        let report = try decode(fixture())
        XCTAssertEqual(report.current.temperature, 10)
        XCTAssertEqual(report.hours[1].rainChance, 50)
        XCTAssertEqual(report.days[0].high, 15)
        XCTAssertEqual(report.days[0].sunrise, now.addingTimeInterval(3600))
    }
    func testMissingOptionalReadingDoesNotBecomeZero() throws {
        var p = fixture(), current = pCurrent(fixture())
        current["relative_humidity_2m"] = NSNull(); p["current"] = current
        XCTAssertNil(try decode(p).current.humidity)
    }
    func testWrongUnitsRejectedInsteadOfMislabelingFahrenheit() {
        var p = fixture(), units = p["current_units"] as! [String: String]
        units["temperature_2m"] = "°F"; p["current_units"] = units
        XCTAssertThrowsError(try decode(p))
    }
    func testMisalignedForecastArraysRejected() {
        var p = fixture(), hours = p["hourly"] as! [String: Any]
        hours["precipitation_probability"] = [50]; p["hourly"] = hours
        XCTAssertThrowsError(try decode(p))
    }
    func testStaleAndFutureCurrentWeatherRejected() {
        for offset in [-7200.0, 3600.0] {
            var p = fixture(), current = pCurrent(p)
            current["time"] = now.timeIntervalSince1970 + offset; p["current"] = current
            XCTAssertThrowsError(try decode(p))
        }
    }
    func testInvalidProbabilityIsUnavailable() throws {
        var p = fixture(), hours = p["hourly"] as! [String: Any]
        hours["precipitation_probability"] = [150, -1]; p["hourly"] = hours
        XCTAssertNil(try decode(p).hours[0].rainChance)
        XCTAssertNil(try decode(p).hours[1].rainChance)
    }
    func testUnitConversionAndNightCondition() {
        XCTAssertEqual(WeatherUnits.fahrenheit.temperature(0), 32)
        XCTAssertEqual(WeatherUnits.fahrenheit.temperature(20), 68)
        XCTAssertEqual(WeatherUnits.fahrenheit.windText(16.09344), "10 mph")
        XCTAssertEqual(WeatherUnits.celsius.temperatureText(nil), "—")
        XCTAssertEqual(WeatherCondition.describe(0, isDay: false).symbol, "moon.stars.fill")
        XCTAssertEqual(WeatherCondition.describe(999).label, "Conditions unavailable")
    }
    func testEndpointRequestsPublicEvansvilleForecastWithoutSavedBoxLocation() {
        let items = URLComponents(url: WeatherClient.url, resolvingAgainstBaseURL: false)!.queryItems!
        let params = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(params["latitude"], "37.97")
        XCTAssertEqual(params["forecast_days"], "7")
        XCTAssertEqual(params["timezone"], "America/Chicago")
        XCTAssertEqual(params["timeformat"], "unixtime")
    }
    @MainActor func testFailedRefreshKeepsPreviousForecastAndBacksOff() async throws {
        let report = try decode(fixture())
        var time = now, attempts = 0
        let store = WeatherStore(load: {
            attempts += 1
            if attempts > 1 { throw WeatherError.http(503) }
            return report
        }, clock: { time })
        await store.refresh()
        await store.refresh()
        XCTAssertEqual(attempts, 1)
        time = time.addingTimeInterval(601)
        await store.refresh()
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(store.report?.current.temperature, 10)
        XCTAssertNotNil(store.error)
        await store.refresh()
        XCTAssertEqual(attempts, 2)
        await store.refresh(force: true)
        XCTAssertEqual(attempts, 3)
    }
    private func pCurrent(_ payload: [String: Any]) -> [String: Any] { payload["current"] as! [String: Any] }
}

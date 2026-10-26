import SwiftUI

struct WeatherView: View {
    @Environment(AirStore.self) private var air
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var weather: WeatherStore
    @AppStorage("weather.temperatureUnit") private var unitRaw = WeatherUnits.fahrenheit.rawValue
    @State private var showAirQuality = false
    @State private var showSource = false
    private var units: WeatherUnits { WeatherUnits(rawValue: unitRaw) ?? .fahrenheit }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let report = weather.report {
                        hero(report)
                        if report.isStale(at: air.now) {
                            Label("Out of date · Pull down to refresh", systemImage: "clock.badge.exclamationmark")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        if let error = weather.error { retry(error) }
                        hourly(report)
                        daily(report)
                        conditions(report)
                    } else if weather.loading {
                        ProgressView("Loading Evansville weather…").padding(.vertical, 60)
                    } else {
                        ContentUnavailableView {
                            Label("Weather unavailable", systemImage: "cloud")
                        } description: {
                            Text(weather.error ?? "Connect to the internet to load the forecast.")
                        } actions: {
                            Button("Try again") { Task { await weather.refresh(force: true) } }
                        }
                    }
                    airQuality
                    Button { showSource = true } label: {
                        Label("Weather sources & details", systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 28).padding(.top, 6)
                .frame(maxWidth: 620).frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Weather")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Temperature unit", selection: $unitRaw) {
                            ForEach(WeatherUnits.allCases) { Text($0.label).tag($0.rawValue) }
                        }
                    } label: { Text(units.label).font(.subheadline.weight(.semibold)) }
                    .accessibilityLabel("Weather temperature units")
                }
            }
            .task { await weather.refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await weather.refresh() } }
            }
            .onChange(of: air.now) { _, _ in
                if scenePhase == .active { Task { await weather.refresh() } }
            }
            .refreshable {
                async let forecast: () = weather.refresh(force: true)
                async let aqi: () = air.refreshRegional()
                _ = await (forecast, aqi)
            }
            .sheet(isPresented: $showAirQuality) { ReadingDetails(kind: "regional").environment(air) }
            .sheet(isPresented: $showSource) { sourceSheet }
        }
    }

    private func hero(_ report: WeatherReport) -> some View {
        let current = report.current
        let condition = WeatherCondition.describe(current.code, isDay: current.isDay)
        let today = report.upcomingDays(at: air.now).first
        return VStack(alignment: .leading, spacing: 14) {
            Text(WeatherReport.area).font(.headline)
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(units.temperatureText(current.temperature))
                        .font(.system(size: 66, weight: .light, design: .rounded)).monospacedDigit()
                    Text(condition.label).font(.title3.weight(.medium))
                }
                Spacer()
                Image(systemName: condition.symbol).symbolRenderingMode(.multicolor)
                    .font(.system(size: 56)).accessibilityHidden(true)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    Text("Feels like \(units.temperatureText(current.feelsLike))")
                    Text("H:\(units.temperatureText(today?.high))  L:\(units.temperatureText(today?.low))")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Feels like \(units.temperatureText(current.feelsLike))")
                    Text("H:\(units.temperatureText(today?.high))  L:\(units.temperatureText(today?.low))")
                }
            }.font(.subheadline)
            Text("Forecast updated \(clock(current.at))").font(.caption).opacity(0.8)
        }
        .foregroundStyle(.white).padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Color(red: 0.10, green: 0.25, blue: 0.48), Color(red: 0.08, green: 0.43, blue: 0.62)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24))
    }

    private func hourly(_ report: WeatherReport) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Next 24 hours", systemImage: "clock").font(.subheadline.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 22) {
                    ForEach(report.nextHours(at: air.now)) { hour in
                        let condition = WeatherCondition.describe(hour.code, isDay: hour.isDay)
                        VStack(spacing: 12) {
                            Text(hour.at.formatted(Date.FormatStyle(timeZone: WeatherReport.timeZone).hour(.defaultDigits(amPM: .abbreviated))))
                                .font(.caption).foregroundStyle(.secondary)
                            Image(systemName: condition.symbol).symbolRenderingMode(.multicolor).font(.title3)
                                .accessibilityLabel(condition.label)
                            Text(units.temperatureText(hour.temperature)).font(.subheadline.weight(.semibold))
                            Text(percent(hour.rainChance)).font(.caption2).foregroundStyle(.blue)
                                .accessibilityLabel("Precipitation chance \(percent(hour.rainChance))")
                        }.frame(minWidth: 40).accessibilityElement(children: .combine)
                    }
                }
            }
        }.weatherCard()
    }

    private func daily(_ report: WeatherReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("7-day forecast", systemImage: "calendar").font(.subheadline.weight(.semibold))
            ForEach(report.upcomingDays(at: air.now)) { day in
                HStack(spacing: 12) {
                    Text(dayName(day.at)).font(.subheadline.weight(.medium)).frame(width: 55, alignment: .leading)
                    Image(systemName: WeatherCondition.describe(day.code).symbol).symbolRenderingMode(.multicolor)
                        .frame(width: 25).accessibilityLabel(WeatherCondition.describe(day.code).label)
                    Text(percent(day.rainChance)).font(.caption).foregroundStyle(.blue)
                        .accessibilityLabel("Precipitation chance \(percent(day.rainChance))")
                    Spacer(minLength: 2)
                    Text(units.temperatureText(day.low)).foregroundStyle(.secondary)
                    Text(units.temperatureText(day.high)).fontWeight(.semibold)
                }
                .font(.subheadline).monospacedDigit().accessibilityElement(children: .combine)
            }
        }.weatherCard()
    }

    private func conditions(_ report: WeatherReport) -> some View {
        let today = report.upcomingDays(at: air.now).first
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            metric("Wind", units.windText(report.current.wind), "wind")
            metric("Humidity", percent(report.current.humidity), "humidity")
            metric("Rain chance today", percent(today?.rainChance), "drop")
            metric("UV peak today", today?.uv.map { String(format: "%.1f", $0) } ?? "—", "sun.max")
            metric("Sunrise", today?.sunrise.map(clock) ?? "—", "sunrise")
            metric("Sunset", today?.sunset.map(clock) ?? "—", "sunset")
        }
    }

    private func metric(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
        }.frame(maxWidth: .infinity, minHeight: 60, alignment: .leading).weatherCard()
    }

    private var airQuality: some View {
        let regional = air.regional
        let stale = regional?.isStale(at: air.now) ?? false
        return Button { showAirQuality = true } label: {
            CompactReadingCard(title: "Regional air quality", value: regional.map { Double($0.aqi) }, unit: "US AQI", digits: 0,
                               band: regional.map { Band(tone: $0.tone, label: $0.categoryName, range: "") },
                               tag: RowTag(text: regional?.isPlaceholder == true ? "Preview" : stale ? "Outdated" : regional?.isModeled == false ? "Reported" : "Estimate",
                                           symbol: "globe.americas", color: stale ? .orange : .secondary),
                               scale: Scales.aqiRange, gradient: Scales.aqi, dimmed: stale,
                               caption: regional.map { "\($0.reportingArea) · \($0.observed.dayClockText)" }
                               ?? (air.regionalError == nil ? "Fetching regional air quality…" : "Report unavailable · Tap for details"))
        }.buttonStyle(.plain)
    }

    private func retry(_ message: String) -> some View {
        Button { Task { await weather.refresh(force: true) } } label: {
            Label(message, systemImage: "arrow.clockwise").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var sourceSheet: some View {
        NavigationStack {
            List {
                Section("Evansville, Indiana") {
                    Text("Weather is a forecast from Open-Meteo’s weather models, updated here about every ten minutes while this tab is open. It is separate from the measurements made by your two sensor boxes.")
                    Text("Rain percentages include the chance of precipitation, including snow. UV is the daily maximum. All forecast times use Evansville’s local time.")
                    Text("The saved portable-box location is not used for weather requests. This forecast stays set to Evansville.")
                }
                Section {
                    Link("Weather data by Open-Meteo", destination: URL(string: "https://open-meteo.com/en/docs")!)
                    Link("Air-quality data: Open-Meteo / CAMS", destination: URL(string: "https://open-meteo.com/en/docs/air-quality-api")!)
                }
            }
            .font(.subheadline).navigationTitle("Weather sources").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showSource = false } } }
        }
    }
    private func percent(_ value: Double?) -> String { value.map { "\(Int($0.rounded()))%" } ?? "—" }
    private func clock(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: WeatherReport.timeZone))
    }
    private func dayName(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = WeatherReport.timeZone
        if calendar.isDate(date, inSameDayAs: air.now) { return "Today" }
        return date.formatted(Date.FormatStyle(timeZone: WeatherReport.timeZone).weekday(.abbreviated))
    }
}

private extension View {
    func weatherCard() -> some View {
        padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }
}

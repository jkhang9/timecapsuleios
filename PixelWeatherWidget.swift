//  PixelWeatherWidget.swift
//  WIDGET EXTENSION TARGET ONLY.
//  Replaces all the Swift files Xcode's widget template generates.
//  The look is designed in the app and read from the shared App Group (StyleStore).

import WidgetKit
import SwiftUI
import CoreLocation

// MARK: - Weather (Open-Meteo: free, no API key)

enum WeatherService {
    private struct Response: Decodable {
        struct Current: Decodable {
            let temperature: Double
            let weatherCode: Int
            let isDay: Int
            enum CodingKeys: String, CodingKey {
                case temperature = "temperature_2m", weatherCode = "weather_code", isDay = "is_day"
            }
        }
        let current: Current
    }

    static func fetch(at c: CLLocationCoordinate2D) async throws -> WeatherSnapshot {
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            URLQueryItem(name: "latitude", value: String(c.latitude)),
            URLQueryItem(name: "longitude", value: String(c.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "temperature_unit", value: Locale.current.measurementSystem == .us ? "fahrenheit" : "celsius"),
        ]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        let r = try JSONDecoder().decode(Response.self, from: data).current
        return WeatherSnapshot(condition: SkyCondition(wmoCode: r.weatherCode), isDay: r.isDay == 1,
                               temperature: Int(r.temperature.rounded()))
    }
}

enum WeatherLoader {
    // Used when location access is off. Change these to your own city.
    static let fallbackCoordinate = CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090)
    static let fallbackName = "CUPERTINO, CA"

    static func load() async -> (WeatherSnapshot?, String) {
        let manager = CLLocationManager()
        let location = manager.isAuthorizedForWidgetUpdates ? manager.location : nil
        let weather = try? await WeatherService.fetch(at: location?.coordinate ?? fallbackCoordinate)

        var name = fallbackName
        if let location, let mark = try? await CLGeocoder().reverseGeocodeLocation(location).first {
            let city = mark.locality ?? mark.name ?? ""
            // US gives "TX"; elsewhere fall back to the 2-letter country code.
            var region = mark.administrativeArea ?? ""
            if region.count > 3 { region = mark.isoCountryCode ?? "" }
            if !city.isEmpty { name = region.isEmpty ? city : "\(city), \(region)" }
        }
        return (weather, name)
    }
}

// MARK: - Timeline

struct PixelWeatherEntry: TimelineEntry {
    let date: Date
    let weather: WeatherSnapshot?
    let place: String
    let style: WindowStyle
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> PixelWeatherEntry {
        PixelWeatherEntry(date: .now, weather: .sample, place: "CUPERTINO, CA", style: StyleStore.style)
    }

    func getSnapshot(in context: Context, completion: @escaping (PixelWeatherEntry) -> Void) {
        if context.isPreview { completion(placeholder(in: context)); return }
        Task { completion(await makeEntries(count: 1)[0]) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PixelWeatherEntry>) -> Void) {
        Task { completion(Timeline(entries: await makeEntries(count: nil), policy: .atEnd)) }
    }

    /// One entry per minute: the clock ticks and the scene animates one frame.
    /// Weather refreshes when the entries run out (hourly, or 15 min after a failed fetch).
    private func makeEntries(count: Int?) async -> [PixelWeatherEntry] {
        let (weather, located) = await WeatherLoader.load()
        let custom = StyleStore.placeName.trimmingCharacters(in: .whitespaces)
        let place = custom.isEmpty ? located : custom
        let style = StyleStore.style
        let start = Calendar.current.dateInterval(of: .minute, for: .now)?.start ?? .now
        let n = count ?? (weather == nil ? 15 : 60)
        return (0..<n).map {
            PixelWeatherEntry(date: start.addingTimeInterval(Double($0) * 60), weather: weather, place: place, style: style)
        }
    }
}

// MARK: - Views

struct PixelWeatherWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: PixelWeatherEntry

    var body: some View {
        PixelWeatherScene(layout: layout, style: entry.style, weather: entry.weather,
                          date: entry.date, place: entry.place,
                          fullColor: renderingMode == .fullColor,
                          pixelSize: family == .systemLarge ? 3 : 2)
    }

    private var layout: SceneLayout {
        switch family {
        case .accessoryCircular: .lockCircular
        case .accessoryRectangular: .lockRectangular
        default: .home
        }
    }
}

struct PixelWeatherWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PixelWeatherWidget", provider: Provider()) { entry in
            PixelWeatherWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(hex: entry.style.backgroundHex) }
        }
        .configurationDisplayName("Pixel Window")
        .description("A cozy pixel window showing today's sky. Design it in the Pixel Window app.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

@main
struct PixelWeatherWidgetBundle: WidgetBundle {
    var body: some Widget { PixelWeatherWidget() }
}

//  ContentView.swift
//  APP TARGET ONLY. Replaces the ContentView.swift Xcode generates.
//  The design studio: tap swatches to style your window. Every change is saved to the
//  shared App Group and the widgets refresh right away.

import SwiftUI
import UIKit
import CoreLocation
import WidgetKit

// MARK: - Location permission

final class LocationPermission: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var status: CLAuthorizationStatus = .notDetermined
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        status = manager.authorizationStatus
    }

    func request() { manager.requestWhenInUseAuthorization() }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways { manager.requestLocation() }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        WidgetCenter.shared.reloadAllTimelines()
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

// MARK: - Swatch row

/// A horizontal row of tappable pixel-art swatches, one per option.
struct OptionRow<Option: PixelOption, Swatch: View>: View {
    let title: String
    @Binding var selection: Option
    @ViewBuilder let swatch: (Option) -> Swatch

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Option.allCases) { option in
                        let selected = selection == option
                        Button { selection = option } label: {
                            VStack(spacing: 6) {
                                swatch(option)
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(selected ? Color.accentColor : .clear, lineWidth: 3))
                                Text(option.title)
                                    .font(.caption2.weight(selected ? .semibold : .regular))
                                    .foregroundStyle(selected ? .primary : .secondary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .frame(width: 76, height: 28, alignment: .top)   // names wrap under their swatch
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
            }
        }
    }
}

// MARK: - Main screen

struct ContentView: View {
    @StateObject private var location = LocationPermission()
    @Environment(\.openURL) private var openURL
    @State private var style = StyleStore.style
    @State private var placeName = StyleStore.placeName
    @State private var condition: SkyCondition = .partlyCloudy
    @State private var isDay = true

    private var weather: WeatherSnapshot { WeatherSnapshot(condition: condition, isDay: isDay, temperature: 72) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    previews

                    OptionRow(title: "Aesthetic", selection: $style.aesthetic) { o in variant { $0.aesthetic = o } }
                    if style.aesthetic.isCharacterGrid {
                        // ASCII & Terminal are a plain weather display — nothing else to configure.
                        Text("Shows just the weather picture, with the time, temperature and place.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        OptionRow(title: "Wallpaper", selection: $style.wallpaper) { o in variant { $0.wallpaper = o } }
                        OptionRow(title: "Window Shape", selection: $style.shape) { o in variant { $0.shape = o } }
                        OptionRow(title: "Frame Material", selection: $style.material) { o in variant { $0.material = o } }
                        OptionRow(title: "Frame Thickness", selection: $style.frame) { o in variant { $0.frame = o } }
                        OptionRow(title: "Panes", selection: $style.panes) { o in variant { $0.panes = o } }
                        OptionRow(title: "On the Sill", selection: $style.sill) { o in variant { $0.sill = o } }
                    }

                    GroupBox("Preview Weather") {
                        Picker("Sky", selection: $condition) {
                            ForEach(SkyCondition.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Toggle("Daytime", isOn: $isDay)
                    }

                    GroupBox("Place") {
                        TextField("City, ST — leave empty to use your location", text: $placeName)
                            .textInputAutocapitalization(.words)
                        locationStatus
                    }

                    GroupBox("Add the Widget") {
                        Text("Lock Screen: long-press it → Customize → Lock Screen → tap the widget row → Pixel Window.\nHome Screen: long-press → Edit → Add Widget → Pixel Window.\nAnything you pick here updates every Pixel Window widget.")
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .navigationTitle("Pixel Window")
            .onChange(of: style) { _, newValue in
                StyleStore.style = newValue
                WidgetCenter.shared.reloadAllTimelines()
            }
            .onChange(of: placeName) { _, newValue in
                StyleStore.placeName = newValue
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    /// Static swatch: the current design with one option swapped in.
    private func variant(_ change: (inout WindowStyle) -> Void) -> some View {
        var s = style
        change(&s)
        return PixelWeatherScene(layout: .thumbnail, style: s, weather: weather, date: .now,
                                 place: "", fullColor: true, tick: 600)
            .frame(width: 76, height: 76)
            .background(Color(hex: s.backgroundHex))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder private var locationStatus: some View {
        switch location.status {
        case .notDetermined:
            Button("Allow Location Access") { location.request() }
                .frame(maxWidth: .infinity, alignment: .leading)
        case .denied, .restricted:
            HStack {
                Text("Location is off; the widget uses its fallback city.").font(.footnote)
                Spacer()
                Button("Settings") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
            }
        default:
            Label("Using your location", systemImage: "location.fill")
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var place: String {
        let p = placeName.trimmingCharacters(in: .whitespaces)
        return p.isEmpty ? "CUPERTINO, CA" : p
    }

    // Live previews. The widget advances one frame per minute; here it plays ~3 frames a second.
    private var previews: some View {
        TimelineView(.periodic(from: .now, by: 0.35)) { ctx in
            let tick = Int(ctx.date.timeIntervalSinceReferenceDate / 0.35)
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    homePreview(date: ctx.date, tick: tick).frame(width: 150, height: 150)
                    ZStack {
                        LinearGradient(colors: [Color(hex: 0x1D2B53), Color(hex: 0x7E2553)],
                                       startPoint: .top, endPoint: .bottom)
                        VStack(spacing: 10) {
                            PixelWeatherScene(layout: .lockCircular, style: style, weather: weather,
                                              date: ctx.date, place: place, fullColor: false, tick: tick)
                                .frame(width: 64, height: 64)
                            Text("Lock Screen").font(.caption2).foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                homePreview(date: ctx.date, tick: tick).frame(height: 150)
            }
        }
    }

    private func homePreview(date: Date, tick: Int) -> some View {
        PixelWeatherScene(layout: .home, style: style, weather: weather, date: date,
                          place: place, fullColor: true, tick: tick)
            .background(Color(hex: style.backgroundHex))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

extension SkyCondition {
    var title: String {
        switch self {
        case .clear: "Clear"
        case .partlyCloudy: "Partly Cloudy"
        case .cloudy: "Cloudy"
        case .fog: "Fog"
        case .rain: "Rain"
        case .snow: "Snow"
        case .storm: "Storm"
        }
    }
}

#Preview { ContentView() }

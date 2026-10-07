//  ContentView.swift
//  APP TARGET ONLY. Replaces the ContentView.swift Xcode generates.
//  My Widgets: a grid of every window the user designed, one per place.
//  Tapping one (or +) opens the editor. Every change is saved to the shared
//  App Group and the widgets refresh right away.

import SwiftUI
import UIKit
import CoreLocation
import WidgetKit

// MARK: - Theme

/// Quiet neutrals so each window's own look is the only colour on screen.
enum Theme {
    static let ground = Color(light: 0xF4F4F2, dark: 0x0E0E0D)
    static let stage = Color(light: 0xE9E9E6, dark: 0x1A1A19)
    static let card = Color(light: 0xFFFFFF, dark: 0x1A1A19)
    static let selected = Color(light: 0xFFFFFF, dark: 0x2A2A28)
    static let destructive = Color(hex: 0xC4372C)
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.75)
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        func ui(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }
}

/// Shrinks a little while pressed and springs back.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.95
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

extension View {
    /// Hides content softly at the given edges to hint that there is more to scroll.
    func edgeFade(_ axis: Axis, leading: CGFloat, trailing: CGFloat) -> some View {
        mask {
            let stops: [Gradient.Stop] = [.init(color: .clear, location: 0), .init(color: .black, location: 1)]
            if axis == .horizontal {
                HStack(spacing: 0) {
                    LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing).frame(width: leading)
                    Rectangle()
                    LinearGradient(stops: stops, startPoint: .trailing, endPoint: .leading).frame(width: trailing)
                }
            } else {
                VStack(spacing: 0) {
                    LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom).frame(height: leading)
                    Rectangle()
                    LinearGradient(stops: stops, startPoint: .bottom, endPoint: .top).frame(height: trailing)
                }
            }
        }
    }
}

// MARK: - Library (the saved windows)

@Observable
final class WidgetLibrary {
    var widgets: [SavedWidget] = WidgetStore.all {
        didSet {
            WidgetStore.all = widgets
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// A binding that follows a window by id, so it stays valid while the list changes.
    func binding(for id: UUID) -> Binding<SavedWidget> {
        Binding(
            get: { self.widgets.first { $0.id == id } ?? SavedWidget(id: id) },
            set: { new in
                if let i = self.widgets.firstIndex(where: { $0.id == id }) { self.widgets[i] = new }
            })
    }

    func add() -> UUID {
        var new = SavedWidget()
        if let last = widgets.last { new.style = last.style }   // start from the most recent design
        widgets.append(new)
        return new.id
    }

    func delete(_ id: UUID) { widgets.removeAll { $0.id == id } }
}

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

// MARK: - My Widgets

struct ContentView: View {
    @State private var library = WidgetLibrary()
    @State private var path: [UUID] = []
    @State private var appeared = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                if library.widgets.isEmpty {
                    emptyState
                } else {
                    grid
                }
            }
            .scrollIndicators(.hidden)
            .edgeFade(.vertical, leading: 12, trailing: 48)
            .background(Theme.ground)
            .navigationTitle("My Widgets")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { path.append(library.add()) } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.ground)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(.primary))
                    }
                    .buttonStyle(PressableStyle(scale: 0.88))
                    .accessibilityLabel("Add widget")
                }
            }
            .navigationDestination(for: UUID.self) { id in
                EditorView(widget: library.binding(for: id)) {
                    path.removeAll()
                    // Let the pop animation finish before the tile disappears from the grid.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        withAnimation(Theme.spring) { library.delete(id) }
                    }
                }
            }
            .onAppear { appeared = true }
        }
        .tint(.primary)
    }

    /// Small windows sit two to a row; medium and large take the full width.
    private var rows: [[SavedWidget]] {
        var rows: [[SavedWidget]] = []
        var pending: SavedWidget?
        for w in library.widgets {
            if w.size == .small {
                if let p = pending { rows.append([p, w]); pending = nil } else { pending = w }
            } else {
                rows.append([w])
            }
        }
        if let p = pending { rows.append([p]) }
        return rows
    }

    private var grid: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let tick = Int(ctx.date.timeIntervalSinceReferenceDate)
            VStack(spacing: 18) {
                ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(row) { w in
                            let index = library.widgets.firstIndex(of: w) ?? r
                            Button { path.append(w.id) } label: { WidgetTile(widget: w, date: ctx.date, tick: tick) }
                                .buttonStyle(PressableStyle(scale: 0.97))
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 12)
                                .animation(.spring(response: 0.5, dampingFraction: 0.85).delay(Double(index) * 0.05),
                                           value: appeared)
                                .transition(.scale(scale: 0.9).combined(with: .opacity))
                        }
                        if row.count == 1 && row[0].size == .small { Color.clear.frame(maxWidth: .infinity) }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 48)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Text("No windows yet").font(.headline)
            Text("Design a window for each place you want to keep an eye on.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Add a Window") { path.append(library.add()) }
                .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }
}

struct WidgetTile: View {
    let widget: SavedWidget
    let date: Date
    let tick: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PixelWeatherScene(layout: .home, style: widget.style, weather: .sample, date: date,
                              place: widget.usesCurrentLocation ? "HERE" : widget.placeName,
                              fullColor: true, tick: tick)
                .background(Color(hex: widget.style.backgroundHex))
                .frame(maxWidth: .infinity)
                .frame(height: widget.size == .large ? 330 : 160)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            HStack(alignment: .firstTextBaseline) {
                Text(widget.displayName).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 4)
                Text(widget.style.aesthetic.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.horizontal, 4)
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Edit this widget")
    }
}

// MARK: - Edit Widget

struct EditorView: View {
    @Binding var widget: SavedWidget
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var location = LocationPermission()
    @State private var onLockScreen = false
    @State private var lockRound = true
    @State private var condition: SkyCondition = .partlyCloudy
    @State private var isDay = true
    @State private var confirmingDelete = false
    @State private var geocodeTask: Task<Void, Never>?

    private var weather: WeatherSnapshot { WeatherSnapshot(condition: condition, isDay: isDay, temperature: 72) }
    private var place: String { widget.usesCurrentLocation ? "CUPERTINO, CA" : widget.placeName }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                placeField
                stage.padding(.top, 12)
                weatherMenu.padding(.top, 6)

                OptionRow(title: "Look", selection: $widget.style.aesthetic) { o in variant { $0.aesthetic = o } }
                if widget.style.aesthetic.isCharacterGrid {
                    // ASCII & Terminal are a plain weather display — nothing else to configure.
                    Text("This look is just the weather in characters — nothing else to set.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20).padding(.top, 18)
                        .transition(.opacity)
                } else {
                    Group {
                        OptionRow(title: "Wallpaper", selection: $widget.style.wallpaper) { o in variant { $0.wallpaper = o } }
                        OptionRow(title: "Window Shape", selection: $widget.style.shape) { o in variant { $0.shape = o } }
                        OptionRow(title: "Frame Material", selection: $widget.style.material) { o in variant { $0.material = o } }
                        OptionRow(title: "Frame Thickness", selection: $widget.style.frame) { o in variant { $0.frame = o } }
                        OptionRow(title: "Panes", selection: $widget.style.panes) { o in variant { $0.panes = o } }
                        OptionRow(title: "On the Sill", selection: $widget.style.sill) { o in variant { $0.sill = o } }
                    }
                    .transition(.opacity)
                }

                Button("Delete Widget", role: .destructive) { confirmingDelete = true }
                    .font(.body)
                    .foregroundStyle(Theme.destructive)
                    .frame(minHeight: 44)
                    .padding(.top, 28)
                    .buttonStyle(PressableStyle())
            }
            .padding(.top, 8)
            .padding(.bottom, 56)
            .animation(Theme.spring, value: widget.style.aesthetic.isCharacterGrid)
        }
        .scrollIndicators(.hidden)
        .edgeFade(.vertical, leading: 12, trailing: 56)
        .background(Theme.ground)
        .navigationTitle("Edit Widget")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }.fontWeight(.semibold)
            }
        }
        .alert("Delete \(widget.displayName)?", isPresented: $confirmingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { onDelete() }
        } message: {
            Text("Any copies of this widget on your Home or Lock Screen will go blank until you choose another.")
        }
        .sensoryFeedback(.warning, trigger: confirmingDelete) { _, new in new }
    }

    // MARK: Place

    private var placeField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: widget.usesCurrentLocation ? "location.fill" : "mappin")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .contentTransition(.symbolEffect(.replace))
                TextField("Current location", text: $widget.placeName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                if !widget.usesCurrentLocation {
                    Button { widget.placeName = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .accessibilityLabel("Use current location")
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .animation(Theme.spring, value: widget.usesCurrentLocation)
            .onChange(of: widget.placeName) { _, _ in lookUpPlace() }

            if widget.usesCurrentLocation { locationStatus.padding(.horizontal, 4) }
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder private var locationStatus: some View {
        switch location.status {
        case .notDetermined:
            Button("Allow Location Access") { location.request() }.font(.footnote)
        case .denied, .restricted:
            HStack {
                Text("Location is off; the widget shows Cupertino.").font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Button("Settings") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                    .font(.footnote)
            }
        default:
            EmptyView()
        }
    }

    /// Finds the typed place's coordinates (after a short pause in typing) so the widget can fetch its weather.
    private func lookUpPlace() {
        widget.latitude = nil
        widget.longitude = nil
        geocodeTask?.cancel()
        let query = widget.placeName.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        geocodeTask = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled,
                  let c = try? await CLGeocoder().geocodeAddressString(query).first?.location?.coordinate,
                  !Task.isCancelled else { return }
            widget.latitude = c.latitude
            widget.longitude = c.longitude
        }
    }

    // MARK: Preview

    private var previewSize: CGSize {
        switch widget.size {
        case .small: CGSize(width: 150, height: 150)
        case .medium: CGSize(width: 320, height: 150)
        case .large: CGSize(width: 320, height: 336)
        }
    }

    private var stage: some View {
        VStack(spacing: 18) {
            TimelineView(.periodic(from: .now, by: 0.35)) { ctx in
                let tick = Int(ctx.date.timeIntervalSinceReferenceDate / 0.35)
                if onLockScreen {
                    PixelWeatherScene(layout: lockRound ? .lockCircular : .lockRectangular, style: widget.style,
                                      weather: weather, date: ctx.date, place: place, fullColor: false, tick: tick)
                        .frame(width: lockRound ? 76 : 170, height: 76)
                        .background(Color.black.opacity(0.85),
                                    in: RoundedRectangle(cornerRadius: lockRound ? 38 : 18, style: .continuous))
                        .frame(height: 150)
                } else {
                    PixelWeatherScene(layout: .home, style: widget.style, weather: weather, date: ctx.date,
                                      place: place, fullColor: true, tick: tick)
                        .frame(width: previewSize.width, height: previewSize.height)
                        .background(Color(hex: widget.style.backgroundHex))
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 15, y: 10)
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: widget.size)
            .animation(Theme.spring, value: onLockScreen)
            .animation(Theme.spring, value: lockRound)

            HStack(spacing: 8) {
                Segmented(options: ["Home", "Lock"], selected: onLockScreen ? 1 : 0) { onLockScreen = $0 == 1 }
                if onLockScreen {
                    Segmented(options: ["Circle", "Rect"], selected: lockRound ? 0 : 1) { lockRound = $0 == 0 }
                } else {
                    Segmented(options: WidgetSize.allCases.map(\.shortTitle),
                              selected: WidgetSize.allCases.firstIndex(of: widget.size) ?? 1) {
                        widget.size = WidgetSize.allCases[$0]
                    }
                    .accessibilityLabel("Widget size")
                }
            }
        }
        .padding(.top, 28)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
        .background(Theme.stage, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 20)
    }

    private var weatherMenu: some View {
        Menu {
            Picker("Sky", selection: $condition) {
                ForEach(SkyCondition.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Toggle("Daytime", isOn: $isDay)
        } label: {
            HStack(spacing: 6) {
                Text("Previewing: \(condition.title) · \(isDay ? "Day" : "Night")")
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(minHeight: 36)
        }
    }

    /// Static swatch: the current design with one option swapped in.
    private func variant(_ change: (inout WindowStyle) -> Void) -> some View {
        var s = widget.style
        change(&s)
        return PixelWeatherScene(layout: .thumbnail, style: s, weather: weather, date: .now,
                                 place: "", fullColor: true, tick: 600)
            .frame(width: 60, height: 60)
            .background(Color(hex: s.backgroundHex))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// A compact pill-shaped segmented control whose highlight slides between options.
struct Segmented: View {
    let options: [String]
    let selected: Int
    let pick: (Int) -> Void
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { i, title in
                Button {
                    withAnimation(Theme.spring) { pick(i) }
                } label: {
                    Text(title)
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 12)
                        .frame(minWidth: 34, minHeight: 30)
                        .background {
                            if i == selected {
                                Capsule().fill(Theme.selected)
                                    .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "pill", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle(scale: 0.92))
                .accessibilityAddTraits(i == selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.06), in: Capsule())
        .foregroundStyle(.primary)
        .sensoryFeedback(.selection, trigger: selected)
    }
}

// MARK: - Swatch row

/// A horizontal row of tappable pixel-art swatches, one per option.
struct OptionRow<Option: PixelOption, Swatch: View>: View {
    let title: String
    @Binding var selection: Option
    @ViewBuilder let swatch: (Option) -> Swatch

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(Option.allCases) { option in
                        let selected = selection == option
                        Button {
                            withAnimation(Theme.spring) { selection = option }
                        } label: {
                            VStack(spacing: 6) {
                                swatch(option)
                                    .padding(2)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .stroke(Color.primary, lineWidth: 2)
                                            .opacity(selected ? 1 : 0)
                                            .scaleEffect(selected ? 1 : 1.08))
                                Text(option.title)
                                    .font(.caption2.weight(selected ? .semibold : .regular))
                                    .foregroundStyle(selected ? .primary : .secondary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .frame(width: 68, height: 28, alignment: .top)   // names wrap under their swatch
                            }
                        }
                        .buttonStyle(PressableStyle(scale: 0.9))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .edgeFade(.horizontal, leading: 20, trailing: 44)
            .sensoryFeedback(.selection, trigger: selection)
        }
        .padding(.top, 18)
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

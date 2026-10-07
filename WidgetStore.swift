//  WidgetStore.swift
//  SHARED FILE — add to BOTH the app target and the widget extension target.
//
//  Every window the user designs is a SavedWidget: its own place and its own style.
//  The app edits the list; each widget on the Home or Lock Screen picks one by id.

import Foundation

/// Home Screen size the window is designed for (sets its preview and its tile in the app).
enum WidgetSize: String, Codable, CaseIterable, Identifiable {
    case small, medium, large
    var id: Self { self }
    var shortTitle: String {
        switch self {
        case .small: "S"
        case .medium: "M"
        case .large: "L"
        }
    }
    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }
}

struct SavedWidget: Codable, Identifiable, Hashable {
    var id = UUID()
    /// "City, ST"; empty means use the current location.
    var placeName = ""
    /// Looked up by the app when the place is typed, so the widget doesn't have to.
    var latitude: Double?
    var longitude: Double?
    var style = WindowStyle()
    var size: WidgetSize = .medium

    var usesCurrentLocation: Bool { placeName.trimmingCharacters(in: .whitespaces).isEmpty }
    var displayName: String { usesCurrentLocation ? "Current Location" : placeName.trimmingCharacters(in: .whitespaces) }
}

enum WidgetStore {
    private static let key = "savedWidgets"
    private static var defaults: UserDefaults { UserDefaults(suiteName: StyleStore.appGroup) ?? .standard }

    /// All saved windows, in the order shown in the app.
    /// The first launch after updating turns the old single design into the first window.
    static var all: [SavedWidget] {
        get {
            if let data = defaults.data(forKey: key),
               let saved = try? JSONDecoder().decode([SavedWidget].self, from: data) {
                return saved
            }
            // Save the migrated window right away so its id stays the same on every read.
            let migrated = [SavedWidget(placeName: StyleStore.placeName, style: StyleStore.style)]
            defaults.set(try? JSONEncoder().encode(migrated), forKey: key)
            return migrated
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }

    static func widget(id: UUID) -> SavedWidget? { all.first { $0.id == id } }
}

import SwiftUI
import Observation

/// Checks the latest GitHub release and compares it with the installed version.
@Observable
final class UpdateChecker {
    enum State: Equatable {
        case idle, checking, upToDate
        case available(version: String, url: URL)
        case failed(String)
    }

    static let repo = "davidpraznik/Filetor"
    var state: State = .idle

    /// True while a newer release exists. Drives the dot on the Settings button.
    var isAvailable: Bool {
        if case .available = state { return true }
        return false
    }

    var installed: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    @MainActor
    func check() async {
        // A background re-check keeps showing a known update instead of flickering to "Checking…".
        let previous = state
        if !isAvailable { state = .checking }
        guard let api = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest") else { return }
        do {
            var req = URLRequest(url: api)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: req)
            if (response as? HTTPURLResponse)?.statusCode == 404 {
                state = isAvailable ? previous : .failed("No release published yet.")
                return
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                state = isAvailable ? previous : .failed("Could not read the latest release.")
                return
            }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let page = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? URL(string: "https://github.com/\(Self.repo)/releases")!
            if latest.compare(installed, options: .numeric) == .orderedDescending {
                state = .available(version: latest, url: page)
            } else {
                state = .upToDate
            }
        } catch {
            state = isAvailable ? previous : .failed("Could not reach GitHub.")
        }
    }

    var message: String {
        switch state {
        case .idle: return ""
        case .checking: return "Checking…"
        case .upToDate: return "Filetor is up to date."
        case .available(let v, _): return "Version \(v) is available."
        case .failed(let m): return m
        }
    }
}

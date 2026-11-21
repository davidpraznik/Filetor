import Foundation
import Security

/// Which AI Filetor talks to. Stored in the "aiProvider" setting.
enum AIProvider: Int {
    case off = 0, other = 1, local = 2
}

/// Settings and connection checks for the AI features. The API key lives in the Keychain, never in preferences.
enum AIStore {
    static let defaultLocalAddress = "http://localhost:11434"

    private static let service = "Filetor AI"
    private static let account = "other-api-key"

    private static func keychainQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func apiKey() -> String {
        var query = keychainQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func setAPIKey(_ key: String) {
        SecItemDelete(keychainQuery() as CFDictionary)
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var query = keychainQuery()
        query[kSecValueData as String] = Data(trimmed.utf8)
        SecItemAdd(query as CFDictionary, nil)
    }

    /// Address of the chat endpoint of an OpenAI-compatible service, from the base address the user typed.
    static func chatURL(base: String) -> URL? {
        var text = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        guard !text.isEmpty else { return nil }
        return URL(string: text + "/chat/completions")
    }

    /// Sends one tiny request to check the address, key and model name. Returns a short message for the settings page.
    static func testOther(base: String, model: String) async -> String {
        let key = apiKey()
        guard let url = chatURL(base: base) else { return "Enter the base address first." }
        guard !model.trimmingCharacters(in: .whitespaces).isEmpty else { return "Enter a model name first." }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        if !key.isEmpty { request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization") }
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": model,
            "messages": [["role": "user", "content": "ping"]],
        ] as [String: Any])
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 200 { return "Connected." }
            if code == 401 || code == 403 { return "The key was not accepted." }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any], let message = error["message"] as? String {
                return message
            }
            return "Request failed (\(code))."
        } catch {
            return "Could not reach the service."
        }
    }

    /// Models installed in a local Ollama-style server.
    static func localModels(address: String) async -> (models: [String], message: String) {
        let base = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: base.hasSuffix("/") ? base + "api/tags" : base + "/api/tags") else {
            return ([], "Bad address.")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = json["models"] as? [[String: Any]] else { return ([], "Unexpected answer.") }
            let names = list.compactMap { $0["name"] as? String }
            return (names, names.isEmpty ? "No models installed." : "Found \(names.count).")
        } catch {
            return ([], "Nothing is running at this address.")
        }
    }
}

// MARK: - Asking in words

/// A search described in words, turned into filters by the AI. Only this text and today's date are sent, never file names.
nonisolated struct AIQuery: Equatable, Sendable {
    var prompt = ""
    var name: String?
    var extensions: [String] = []
    var after: Date?
    var before: Date?
    var minBytes: Int64?
    var maxBytes: Int64?

    static let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey]

    /// "October 2026" or "2025" when the range is a whole month or year, otherwise "1 Oct to 9 Nov 2026".
    private static func period(_ start: Date, _ end: Date) -> String {
        let calendar = Calendar.current
        let last = end.addingTimeInterval(-1)
        let f = DateFormatter()
        if let month = calendar.dateInterval(of: .month, for: start), month.start == start, month.end == end {
            f.dateFormat = "LLLL yyyy"
            return f.string(from: start)
        }
        if let year = calendar.dateInterval(of: .year, for: start), year.start == start, year.end == end {
            f.dateFormat = "yyyy"
            return f.string(from: start)
        }
        return "\(day(start)) to \(day(last))"
    }

    private static func day(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        return f.string(from: date)
    }

    /// Short labels for the chips under the toolbar.
    var chips: [String] {
        var list: [String] = []
        if let name, !name.isEmpty { list.append("Name contains \(name)") }
        if !extensions.isEmpty {
            let images: Set<String> = ["jpg", "jpeg", "png", "heic", "gif", "webp"]
            if images.isSubset(of: Set(extensions)) {
                list.append("Kind: Images")
            } else {
                let shown = extensions.prefix(3).map { $0.uppercased() }.joined(separator: ", ")
                list.append("Kind: " + shown + (extensions.count > 3 ? " +\(extensions.count - 3)" : ""))
            }
        }
        if let after, let before {
            list.append("Modified: " + Self.period(after, before))
        } else if let after {
            list.append("Modified after \(Self.day(after))")
        } else if let before {
            list.append("Modified before \(Self.day(before.addingTimeInterval(-1)))")
        }
        if let minBytes { list.append("Larger than \(ByteCountFormatter.string(fromByteCount: minBytes, countStyle: .file))") }
        if let maxBytes { list.append("Smaller than \(ByteCountFormatter.string(fromByteCount: maxBytes, countStyle: .file))") }
        return list
    }

    var isEmpty: Bool { chips.isEmpty }

    func matches(_ url: URL, _ values: URLResourceValues) -> Bool {
        let isFolder = values.isDirectory == true
        if let name, !name.isEmpty {
            let file = url.lastPathComponent
            for word in name.split(separator: " ") where file.range(of: String(word), options: [.caseInsensitive, .diacriticInsensitive]) == nil {
                return false
            }
        }
        if !extensions.isEmpty {
            if isFolder || !extensions.contains(url.pathExtension.lowercased()) { return false }
        }
        if after != nil || before != nil {
            guard let date = values.contentModificationDate else { return false }
            if let after, date < after { return false }
            if let before, date >= before { return false }
        }
        if minBytes != nil || maxBytes != nil {
            if isFolder { return false }
            let size = Int64(values.fileSize ?? 0)
            if let minBytes, size < minBytes { return false }
            if let maxBytes, size > maxBytes { return false }
        }
        return true
    }
}

extension AIStore {
    private static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "name": ["type": ["string", "null"]],
            "extensions": ["type": "array", "items": ["type": "string"]],
            "modified_after": ["type": ["string", "null"]],
            "modified_before": ["type": ["string", "null"]],
            "min_size_mb": ["type": ["number", "null"]],
            "max_size_mb": ["type": ["number", "null"]],
        ],
        "required": ["name", "extensions", "modified_after", "modified_before", "min_size_mb", "max_size_mb"],
    ]

    private static func instructions(today: String) -> String {
        """
        You turn a request to find files into a JSON filter. The request may be in Slovenian or English. Today is \(today).
        Reply with JSON only, with exactly these keys:
        {"name": string or null, "extensions": [strings], "modified_after": "YYYY-MM-DD" or null, "modified_before": "YYYY-MM-DD" or null, "min_size_mb": number or null, "max_size_mb": number or null}
        Rules:
        - name: only the distinctive words that should appear in the file name (a company, a person, a project), separated by spaces. Leave out generic words such as file, document, invoice and their translations. null if there are none.
        - extensions: lowercase, without a dot. Fill it only when the request names a kind of file (pdf, images, spreadsheets, videos). Images are jpg, jpeg, png, heic, gif, webp. Otherwise [].
        - modified_after is the first day of the period, modified_before is the last day, both inclusive. "last year" or "lani" means the previous calendar year, "last March" or "lanskega marca" means March of the previous calendar year, "this month" means the current month, "last week" means the previous week.
        - Sizes in megabytes. "večji od", "larger than", "bigger than", "over", "nad" set min_size_mb. "manjši od", "smaller than", "under", "pod" set max_size_mb.
        - Set a field only when the request says it. Never invent dates or sizes. Without a time expression both dates are null.
        Examples:
        "pdf večji od 5 MB" -> {"name": null, "extensions": ["pdf"], "modified_after": null, "modified_before": null, "min_size_mb": 5, "max_size_mb": null}
        "slike manjše od 2 MB" -> {"name": null, "extensions": ["jpg","jpeg","png","heic","gif","webp"], "modified_after": null, "modified_before": null, "min_size_mb": null, "max_size_mb": 2}
        "račun za Elektro iz lanskega marca" (today 2026-11-21) -> {"name": "Elektro", "extensions": [], "modified_after": "2025-03-01", "modified_before": "2025-03-31", "min_size_mb": null, "max_size_mb": null}
        "zip files from this month" (today 2026-11-21) -> {"name": null, "extensions": ["zip"], "modified_after": "2026-11-01", "modified_before": "2026-11-30", "min_size_mb": null, "max_size_mb": null}
        """
    }

    private static func parse(_ text: String, prompt: String) -> AIQuery? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
              let data = String(text[start...end]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        var query = AIQuery(prompt: prompt)
        if let name = json["name"] as? String, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            query.name = name.trimmingCharacters(in: .whitespaces)
        }
        query.extensions = (json["extensions"] as? [String] ?? []).map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". ")) }.filter { !$0.isEmpty }
        if let s = json["modified_after"] as? String, let d = day.date(from: s) { query.after = d }
        if let s = json["modified_before"] as? String, let d = day.date(from: s) {
            query.before = Calendar.current.date(byAdding: .day, value: 1, to: d)
        }
        if let mb = json["min_size_mb"] as? Double { query.minBytes = Int64(mb * 1_000_000) }
        if let mb = json["max_size_mb"] as? Double { query.maxBytes = Int64(mb * 1_000_000) }
        return query
    }

    /// Small models mix up "larger" and "smaller" and invent dates. Sizes are read from the words directly,
    /// and dates are dropped when the sentence has no time expression at all.
    private static func applyRules(to query: inout AIQuery, prompt: String) {
        let text = prompt.lowercased()
        let units: [String: Double] = ["kb": 1_000, "mb": 1_000_000, "gb": 1_000_000_000]
        func size(_ words: String) -> Int64? {
            let pattern = "(?:\\b(?:" + words + ")\\b)\\s*(?:od|than|of)?\\s*(\\d+(?:[.,]\\d+)?)\\s*(kb|mb|gb)"
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let number = Range(match.range(at: 1), in: text), let unit = Range(match.range(at: 2), in: text),
                  let value = Double(text[number].replacingOccurrences(of: ",", with: ".")),
                  let factor = units[String(text[unit])] else { return nil }
            return Int64(value * factor)
        }
        let larger = size("večji|večja|večje|vecji|larger|bigger|greater|over|above|nad|more than|at least|vsaj")
        let smaller = size("manjši|manjša|manjše|manjsi|smaller|under|below|pod|less than|at most")
        if larger != nil || smaller != nil {
            query.minBytes = larger
            query.maxBytes = smaller
        }
        let timeWords = ["lani", "lansk", "last", "this", "ta mesec", "ta teden", "letos", "danes", "today", "včeraj", "yesterday", "week", "teden", "month", "mesec",
                         "year", "leto", "ago", "nazaj", "older", "newer", "starejš", "novejš", "since", "before", "after", "pred ", "po ",
                         "jan", "feb", "mar", "apr", "maj", "jun", "jul", "avg", "aug", "sep", "okt", "oct", "nov", "dec"]
        let hasYear = text.range(of: "\\b(19|20)\\d\\d\\b", options: .regularExpression) != nil
        if !hasYear, !timeWords.contains(where: { text.contains($0) }) {
            query.after = nil
            query.before = nil
        }
    }

    /// Asks the chosen AI to turn a sentence into filters. Returns the filters, or a short message when it fails.
    static func interpret(_ prompt: String) async -> Result<AIQuery, AIFailure> {
        let provider = AIProvider(rawValue: UserDefaults.standard.integer(forKey: "aiProvider")) ?? .off
        let today: String = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: Date())
        }()
        let system = instructions(today: today)
        let reply: String
        switch provider {
        case .off:
            return .failure(AIFailure(message: "AI is off. Turn it on in Settings, AI."))
        case .other:
            let key = apiKey()
            let model = (UserDefaults.standard.string(forKey: "aiOtherModel") ?? "").trimmingCharacters(in: .whitespaces)
            guard let url = chatURL(base: UserDefaults.standard.string(forKey: "aiOtherURL") ?? ""), !model.isEmpty else {
                return .failure(AIFailure(message: "Set the address and model in Settings, AI."))
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 30
            if !key.isEmpty { request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization") }
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: [
                "model": model,
                "messages": [["role": "system", "content": system], ["role": "user", "content": prompt]],
            ] as [String: Any])
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard code == 200 else { return .failure(AIFailure(message: code == 401 || code == 403 ? "The API key was not accepted." : "The AI request failed (\(code)).")) }
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let message = choices.first?["message"] as? [String: Any],
                      let text = message["content"] as? String else { return .failure(AIFailure(message: "Unexpected answer from the AI.")) }
                reply = text
            } catch {
                return .failure(AIFailure(message: "Could not reach the AI service."))
            }
        case .local:
            let base = (UserDefaults.standard.string(forKey: "aiLocalAddress") ?? defaultLocalAddress).trimmingCharacters(in: .whitespacesAndNewlines)
            let model = UserDefaults.standard.string(forKey: "aiLocalModel") ?? ""
            guard !model.isEmpty else { return .failure(AIFailure(message: "Choose a local model in Settings, AI.")) }
            guard let url = URL(string: base.hasSuffix("/") ? base + "api/chat" : base + "/api/chat") else { return .failure(AIFailure(message: "Bad local address.")) }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 120
            request.httpBody = try? JSONSerialization.data(withJSONObject: [
                "model": model, "stream": false, "format": schema, "options": ["temperature": 0],
                "messages": [["role": "system", "content": system], ["role": "user", "content": prompt]],
            ] as [String: Any])
            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let message = json["message"] as? [String: Any],
                      let text = message["content"] as? String else { return .failure(AIFailure(message: "Unexpected answer from the local model.")) }
                reply = text
            } catch {
                return .failure(AIFailure(message: "Nothing is running at the local address."))
            }
        }
        guard var query = parse(reply, prompt: prompt) else {
            return .failure(AIFailure(message: "Could not turn that into a search. Try describing the name, kind or date."))
        }
        applyRules(to: &query, prompt: prompt)
        guard !query.isEmpty else {
            return .failure(AIFailure(message: "Could not turn that into a search. Try describing the name, kind or date."))
        }
        return .success(query)
    }
}

struct AIFailure: Error {
    var message: String
}

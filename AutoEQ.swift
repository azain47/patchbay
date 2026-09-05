import Foundation

/// Headphone correction profiles from jaakkopasanen/AutoEq (MIT), fetched on demand.
/// The catalogue is `results/INDEX.md`; each entry's folder holds `<name> ParametricEQ.txt`.
final class AutoEQCatalog: ObservableObject {
    struct Entry: Identifiable, Hashable {
        let name: String
        let path: String       // URL-encoded path relative to results/
        let source: String
        let rig: String
        var id: String { path }
        var title: String { name }
        var subtitle: String { rig.isEmpty ? source : "\(source) · \(rig)" }
    }

    enum State: Equatable { case idle, loading, ready(Int), failed(String) }

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var state: State = .idle

    private static let base = "https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master/results/"
    private static let sourcePriority = ["oratory1990", "crinacle", "Rtings", "Innerfidelity", "Super Review", "HypetheSonics", "Headphone.com Legacy"]
    private var cacheURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("patchbay", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("autoeq-index.md")
    }

    func load(force: Bool = false) {
        guard state != .loading else { return }
        if !force, let attrs = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
           let modified = attrs[.modificationDate] as? Date, Date().timeIntervalSince(modified) < 7 * 86_400,
           let text = try? String(contentsOf: cacheURL, encoding: .utf8) {
            state = .loading
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let parsed = Self.parse(text)
                DispatchQueue.main.async { self?.entries = parsed; self?.state = .ready(parsed.count) }
            }
            return
        }
        state = .loading
        URLSession.shared.dataTask(with: URL(string: Self.base + "INDEX.md")!) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let data, let text = String(data: data, encoding: .utf8) else {
                    self.state = .failed(error?.localizedDescription ?? "download failed")
                    return
                }
                try? data.write(to: self.cacheURL)
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    let parsed = Self.parse(text)
                    DispatchQueue.main.async { self?.entries = parsed; self?.state = .ready(parsed.count) }
                }
            }
        }.resume()
    }

    private static func parse(_ text: String) -> [Entry] {
        var parsed: [Entry] = []
        for line in text.split(whereSeparator: \.isNewline) {
            // - [Name](./Source/Rig type/Name) by Source on Rig
            guard line.hasPrefix("- ["), let close = line.firstIndex(of: "]"), let open = line[close...].firstIndex(of: "("), let end = line[open...].firstIndex(of: ")") else { continue }
            let name = String(line[line.index(line.startIndex, offsetBy: 3)..<close])
            var path = String(line[line.index(after: open)..<end])
            if path.hasPrefix("./") { path.removeFirst(2) }
            let parts = path.removingPercentEncoding?.split(separator: "/").map(String.init) ?? []
            let source = parts.first ?? ""
            let rig = parts.count >= 3 ? parts[1].replacingOccurrences(of: " in-ear", with: "").replacingOccurrences(of: " over-ear", with: "").replacingOccurrences(of: " earbud", with: "") : ""
            parsed.append(Entry(name: name, path: path, source: source, rig: rig == "in-ear" || rig == "over-ear" || rig == "earbud" ? "" : rig))
        }
        return parsed
    }

    func search(_ query: String, limit: Int = 40) -> [Entry] {
        let terms = query.lowercased().split(separator: " ").map(String.init)
        guard !terms.isEmpty else { return [] }
        let matches = entries.filter { entry in
            let hay = entry.name.lowercased()
            return terms.allSatisfy { hay.contains($0) }
        }
        return matches.sorted { a, b in
            let pa = Self.sourcePriority.firstIndex(of: a.source) ?? 99
            let pb = Self.sourcePriority.firstIndex(of: b.source) ?? 99
            if pa != pb { return pa < pb }
            return a.name.count < b.name.count
        }.prefix(limit).map { $0 }
    }

    func fetchProfile(_ entry: Entry, completion: @escaping (Result<ParametricPreset, Error>) -> Void) {
        let file = entry.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? entry.name
        guard let url = URL(string: Self.base + entry.path + "/" + file + "%20ParametricEQ.txt") else {
            completion(.failure(URLError(.badURL))); return
        }
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                if let data, (response as? HTTPURLResponse)?.statusCode == 200, let text = String(data: data, encoding: .utf8), let preset = ParametricPreset.parse(text) {
                    completion(.success(preset))
                } else {
                    completion(.failure(error ?? URLError(.badServerResponse)))
                }
            }
        }.resume()
    }
}

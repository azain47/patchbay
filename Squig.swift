import Foundation

/// Reviewer measurement databases hosted on squig.link. Each site is a CrinGraph
/// deployment: `phone_book.json` lists the phones, `config.js` names the target
/// curves, and `data/<file> L.txt` / `R.txt` hold REW-style frequency responses.
/// Sites that opted out of cross-site listing (Hangout.Audio among them) are skipped.
final class SquigCatalog: ObservableObject {
    struct Database: Identifiable, Hashable, Codable {
        let site: String
        let siteName: String
        let type: String
        /// Folder URL with a trailing slash; `data/` and `config.js` hang off it.
        let folder: URL
        var id: String { folder.absoluteString }
        var title: String { "\(siteName) · \(type)" }
    }

    struct Entry: Identifiable, Hashable {
        let brand: String
        let model: String
        let file: String
        let suffix: String
        var id: String { file }
        var title: String { suffix.isEmpty ? "\(brand) \(model)" : "\(brand) \(model) \(suffix)" }
    }

    struct Target: Identifiable, Hashable {
        let name: String
        let group: String
        var id: String { name }
    }

    enum State: Equatable { case idle, loading, ready(Int), failed(String) }

    @Published private(set) var databases: [Database] = []
    @Published private(set) var database: Database?
    @Published private(set) var entries: [Entry] = []
    @Published private(set) var targets: [Target] = []
    @Published private(set) var target: Target?
    @Published private(set) var state: State = .idle
    private var dataDir = "data/"
    /// Cache-file stem for the selected database.
    private var key: String { database.map { $0.site + "-" + $0.type.lowercased().filter(\.isLetter) } ?? "none" }

    private static let sitesJSON = URL(string: "https://squig.link/squigsites.json")!
    private static let sitesJS = URL(string: "https://squig.link/squigsites.js")!
    /// Fallback if the opt-out list cannot be read from squigsites.js.
    private static let knownOptedOut: Set<String> = ["64audio", "bloomaudio", "cammyfi", "crinacle", "eliseaudio", "hbb", "joycesreview", "kr0mka", "graph", "vsg"]
    private static let cacheAge: TimeInterval = 7 * 86_400

    init() {
        if let data = UserDefaults.standard.data(forKey: "squig.database"), let db = try? JSONDecoder().decode(Database.self, from: data) {
            database = db
        }
    }

    // MARK: Sites

    func loadSites() {
        guard databases.isEmpty else { return }
        Self.fetch(Self.sitesJS, cache: "squig-sites.js") { [weak self] jsResult in
            let optedOut = (try? jsResult.get()).flatMap(Self.parseOptedOut) ?? Self.knownOptedOut
            Self.fetch(Self.sitesJSON, cache: "squig-sites.json") { jsonResult in
                guard let data = try? jsonResult.get() else { return }
                let parsed = Self.parseSites(data, optedOut: optedOut)
                DispatchQueue.main.async { self?.databases = parsed }
            }
        }
    }

    private static func parseOptedOut(_ data: Data) -> Set<String>? {
        guard let text = String(data: data, encoding: .utf8),
              let start = text.range(of: "optedOut = ["), let end = text[start.upperBound...].firstIndex(of: "]") else { return nil }
        let names = text[start.upperBound..<end].split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "'\"")) }
        return Set(names.filter { !$0.isEmpty })
    }

    private static func parseSites(_ data: Data, optedOut: Set<String>) -> [Database] {
        guard let sites = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        var out: [Database] = []
        for site in sites {
            guard let user = site["username"] as? String, !optedOut.contains(user),
                  let name = site["name"] as? String, let dbs = site["dbs"] as? [[String: Any]] else { continue }
            let root: String
            switch site["urlType"] as? String {
            case "root": root = "https://squig.link"
            case "labFolder": root = "https://squig.link/lab/\(user)"
            case "altDomain": root = site["altDomain"] as? String ?? "https://\(user).squig.link"
            default: root = "https://\(user).squig.link"
            }
            for db in dbs {
                guard let type = db["type"] as? String, var folder = db["folder"] as? String else { continue }
                if !folder.hasSuffix("/") { folder += "/" }
                guard let url = URL(string: root + folder) else { continue }
                out.append(Database(site: user, siteName: name, type: type, folder: url))
            }
        }
        return out.sorted { ($0.siteName.lowercased(), $0.type) < ($1.siteName.lowercased(), $1.type) }
    }

    // MARK: Database

    func select(_ db: Database) {
        database = db
        if let data = try? JSONEncoder().encode(db) { UserDefaults.standard.set(data, forKey: "squig.database") }
        entries = []; targets = []; target = nil
        load()
    }

    func load() {
        guard let db = database, state != .loading, entries.isEmpty else { return }
        state = .loading
        let key = key
        Self.fetch(db.folder.appendingPathComponent("phone_book.json"), cache: "squig-\(key)-book.json") { [weak self] bookResult in
            guard let self else { return }
            guard let book = try? bookResult.get() else {
                DispatchQueue.main.async { self.state = .failed("phone book unavailable") }; return
            }
            let parsed = Self.parseBook(book)
            Self.configURL(for: db, cache: "squig-\(key)-index.html") { configURL in
                let finish: (Data?) -> Void = { config in
                    let text = config.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    let targets = Self.parseTargets(text)
                    let dir = Self.parseDataDir(text)
                    DispatchQueue.main.async {
                        self.entries = parsed
                        self.targets = targets
                        self.dataDir = dir
                        let remembered = UserDefaults.standard.string(forKey: "squig.target.\(db.id)")
                        self.target = targets.first { $0.name == remembered } ?? Self.defaultTarget(targets)
                        self.state = .ready(parsed.count)
                    }
                }
                guard let configURL else { finish(nil); return }
                Self.fetch(configURL, cache: "squig-\(key)-config.js") { finish(try? $0.get()) }
            }
        }
    }

    func setTarget(_ t: Target) {
        target = t
        if let db = database { UserDefaults.standard.set(t.name, forKey: "squig.target.\(db.id)") }
    }

    private static func parseBook(_ data: Data) -> [Entry] {
        guard let brands = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        var out: [Entry] = []
        for brand in brands {
            guard let brandName = brand["name"] as? String, let phones = brand["phones"] as? [[String: Any]] else { continue }
            for phone in phones {
                guard let model = phone["name"] as? String else { continue }
                let files = (phone["file"] as? [String]) ?? (phone["file"] as? String).map { [$0] } ?? []
                let suffixes = (phone["suffix"] as? [String]) ?? (phone["suffix"] as? String).map { [$0] } ?? []
                for (i, file) in files.enumerated() {
                    let suffix = files.count > 1 ? (i < suffixes.count ? suffixes[i] : "") : ""
                    out.append(Entry(brand: brandName, model: model, file: file, suffix: suffix))
                }
            }
        }
        return out
    }

    /// The page's config script: `config.js` beside the index, or wherever the index points.
    private static func configURL(for db: Database, cache: String, completion: @escaping (URL?) -> Void) {
        fetch(db.folder, cache: cache) { result in
            guard let data = try? result.get(), let html = String(data: data, encoding: .utf8) else {
                completion(db.folder.appendingPathComponent("config.js")); return
            }
            let pattern = #"src="([^"]*config[^"]*\.js)""#
            if let m = html.range(of: pattern, options: .regularExpression) {
                let tag = html[m]
                let src = tag.dropFirst(5).dropLast()
                completion(URL(string: String(src), relativeTo: db.folder)?.absoluteURL)
            } else {
                completion(db.folder.appendingPathComponent("config.js"))
            }
        }
    }

    /// `const targets = [ { type:"Reference", files:["Harman 2019 IEM", ...] }, ... ]`; Δ groups are
    /// differences for display, not targets.
    private static func parseTargets(_ config: String) -> [Target] {
        guard let start = config.range(of: "targets = [") else { return [] }
        var depth = 0; var end = start.upperBound
        for i in config[start.lowerBound...].indices {
            let c = config[i]
            if c == "[" { depth += 1 } else if c == "]" { depth -= 1; if depth == 0 { end = i; break } }
        }
        let body = String(config[start.upperBound..<end])
        var out: [Target] = []
        let groupPattern = #"type\s*:\s*"([^"]*)"\s*,\s*files\s*:\s*\[([^\]]*)\]"#
        guard let regex = try? NSRegularExpression(pattern: groupPattern) else { return [] }
        for m in regex.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
            guard let g = Range(m.range(at: 1), in: body), let f = Range(m.range(at: 2), in: body) else { continue }
            let group = String(body[g])
            if group.hasPrefix("Δ") { continue }
            for raw in body[f].split(separator: ",") {
                let name = raw.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                if !name.isEmpty { out.append(Target(name: name, group: group)) }
            }
        }
        return out
    }

    private static func parseDataDir(_ config: String) -> String {
        guard let m = config.range(of: #"DIR\s*=\s*"([^"]*)""#, options: .regularExpression) else { return "data/" }
        let tag = config[m]
        guard let q = tag.firstIndex(of: "\"") else { return "data/" }
        let dir = String(tag[tag.index(after: q)...].dropLast())
        return dir.isEmpty ? "data/" : dir
    }

    private static func defaultTarget(_ targets: [Target]) -> Target? {
        targets.first { $0.name.localizedCaseInsensitiveContains("harman") }
            ?? targets.first { $0.group.localizedCaseInsensitiveContains("reference") }
            ?? targets.first
    }

    func search(_ query: String, limit: Int = 40) -> [Entry] {
        let terms = query.lowercased().split(separator: " ").map(String.init)
        guard !terms.isEmpty else { return [] }
        return entries.filter { e in
            let hay = e.title.lowercased()
            return terms.allSatisfy { hay.contains($0) }
        }
        .sorted { $0.title.count < $1.title.count }
        .prefix(limit).map { $0 }
    }

    // MARK: Measurements

    /// The correction (target − measurement, centred and smoothed) for a phone, ready to fit.
    func fetchCorrection(_ entry: Entry, completion: @escaping (Result<[(frequency: Double, gainDB: Double)], Error>) -> Void) {
        guard let db = database else { completion(.failure(URLError(.badURL))); return }
        guard let target else { completion(.failure(SquigError.noTarget)); return }
        let dir = dataDir
        func dataURL(_ name: String) -> URL? {
            URL(string: dir + (name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name), relativeTo: db.folder)?.absoluteURL
        }
        let channels = ["\(entry.file) L.txt", "\(entry.file) R.txt", "\(entry.file).txt"].compactMap(dataURL)
        let targetURL = dataURL("\(target.name) Target.txt")
        let group = DispatchGroup()
        var curves: [[(Double, Double)]] = []
        var targetCurve: [(Double, Double)]?
        let lock = NSLock()
        for url in channels.prefix(2) {
            group.enter()
            Self.fetch(url, cache: nil) { result in
                if let data = try? result.get(), let curve = Self.parseResponse(data), curve.count > 20 {
                    lock.lock(); curves.append(curve); lock.unlock()
                }
                group.leave()
            }
        }
        if let targetURL {
            group.enter()
            Self.fetch(targetURL, cache: "squig-\(key)-target-\(target.name.filter { $0.isLetter || $0.isNumber }).txt") { result in
                if let data = try? result.get() { targetCurve = Self.parseResponse(data) }
                group.leave()
            }
        }
        group.notify(queue: .global(qos: .userInitiated)) {
            var measured = curves
            if measured.isEmpty, let single = channels.dropFirst(2).first {
                // Single-file phones: no channel suffix.
                let sem = DispatchSemaphore(value: 0)
                Self.fetch(single, cache: nil) { result in
                    if let data = try? result.get(), let curve = Self.parseResponse(data) { measured = [curve] }
                    sem.signal()
                }
                sem.wait()
            }
            guard !measured.isEmpty else { DispatchQueue.main.async { completion(.failure(SquigError.noMeasurement)) }; return }
            guard let targetCurve, targetCurve.count > 20 else { DispatchQueue.main.async { completion(.failure(SquigError.noTarget)) }; return }
            let correction = Correction.compute(measurement: Correction.average(measured), target: targetCurve)
            DispatchQueue.main.async { completion(.success(correction)) }
        }
    }

    enum SquigError: LocalizedError {
        case noTarget, noMeasurement
        var errorDescription: String? {
            switch self {
            case .noTarget: "This database has no target curve to compensate against."
            case .noMeasurement: "No measurement file found for that phone."
            }
        }
    }

    /// REW / CrinGraph text: `freq<sep>dB[<sep>phase]`, comments start with `*` or `#`.
    static func parseResponse(_ data: Data) -> [(Double, Double)]? {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }
        if text.hasPrefix("<") { return nil }
        var out: [(Double, Double)] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard let first = t.first, first.isNumber || first == "-" || first == "." else { continue }
            let parts = t.split(whereSeparator: { $0 == "\t" || $0 == "," || $0 == " " || $0 == ";" })
            guard parts.count >= 2, let f = Double(parts[0]), let db = Double(parts[1]), f > 0, db.isFinite else { continue }
            out.append((f, db))
        }
        return out.isEmpty ? nil : out.sorted { $0.0 < $1.0 }
    }

    // MARK: Fetching

    private static var cacheDir: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("patchbay", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// GET with an on-disk cache; squig.link refuses requests without a browser-like agent.
    private static func fetch(_ url: URL, cache: String?, completion: @escaping (Result<Data, Error>) -> Void) {
        if let cache {
            let file = cacheDir.appendingPathComponent(cache)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
               let modified = attrs[.modificationDate] as? Date, Date().timeIntervalSince(modified) < cacheAge,
               let data = try? Data(contentsOf: file) {
                completion(.success(data)); return
            }
        }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh) patchbay", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data, (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else {
                completion(.failure(error ?? URLError(.badServerResponse))); return
            }
            if let cache { try? data.write(to: cacheDir.appendingPathComponent(cache)) }
            completion(.success(data))
        }.resume()
    }
}

/// Turns a measurement and a target into the curve an equaliser should add, the way
/// AutoEq does: resample to a log grid, centre the error on the midrange, smooth with a
/// window that widens into the treble, negate, then cap boosts and distrust the top octave.
enum Correction {
    static let fMin = 20.0, fMax = 20_000.0, pointsPerOctave = 24.0
    static var grid: [Double] {
        let n = Int((log2(fMax / fMin) * pointsPerOctave).rounded()) + 1
        return (0..<n).map { fMin * pow(2, Double($0) / pointsPerOctave) }
    }

    static func average(_ curves: [[(Double, Double)]]) -> [(Double, Double)] {
        let g = grid
        let sampled = curves.map { resample($0, to: g) }
        return g.indices.map { k in (g[k], sampled.reduce(0) { $0 + $1[k] } / Double(sampled.count)) }
    }

    static func compute(measurement: [(Double, Double)], target: [(Double, Double)]) -> [(frequency: Double, gainDB: Double)] {
        let g = grid
        let m = resample(measurement, to: g), t = resample(target, to: g)
        var error = g.indices.map { m[$0] - t[$0] }
        // Level is arbitrary on both sides: align on the 200 Hz – 3 kHz mean.
        let mid = g.indices.filter { g[$0] >= 200 && g[$0] <= 3_000 }
        let offset = mid.reduce(0) { $0 + error[$1] } / Double(max(1, mid.count))
        for k in error.indices { error[k] -= offset }
        let smoothed = smooth(error, grid: g)
        return g.indices.map { k in
            let f = g[k]
            var gain = -smoothed[k]
            // Boost limit: 10 dB in the bass, none above 8 kHz where ear-canal resonances
            // make measurements personal; cuts up there are applied at half strength.
            let boostCap = f <= 6_000 ? 10.0 : max(0, 10 * (1 - (log2(f / 6_000) / log2(8_000 / 6_000))))
            if gain > boostCap { gain = boostCap }
            if f > 10_000, gain < 0 { gain *= 0.5 }
            if gain < -20 { gain = -20 }
            return (f, gain)
        }
    }

    /// Linear interpolation in log-frequency; flat beyond the ends.
    static func resample(_ curve: [(Double, Double)], to g: [Double]) -> [Double] {
        guard let first = curve.first, let last = curve.last else { return g.map { _ in 0 } }
        var i = 0
        return g.map { f in
            if f <= first.0 { return first.1 }
            if f >= last.0 { return last.1 }
            while i + 1 < curve.count, curve[i + 1].0 < f { i += 1 }
            let (f0, d0) = curve[i], (f1, d1) = curve[i + 1]
            let t = log(f / f0) / log(f1 / f0)
            return d0 + (d1 - d0) * t
        }
    }

    /// Moving average whose window grows from 1/12 octave at 200 Hz to 2/3 octave at 10 kHz.
    static func smooth(_ values: [Double], grid g: [Double]) -> [Double] {
        let narrow = 1.0 / 12.0, wide = 2.0 / 3.0
        let span = log2(10_000.0 / 200.0)
        var out = values
        for k in values.indices {
            let f = g[k]
            var octaves = narrow
            if f >= 10_000 { octaves = wide }
            else if f > 200 { octaves = narrow + (wide - narrow) * (log2(f / 200) / span) }
            let half = max(1, Int((octaves * pointsPerOctave / 2).rounded()))
            let lo = max(0, k - half), hi = min(values.count - 1, k + half)
            var sum = 0.0
            for i in lo...hi { sum += values[i] }
            out[k] = sum / Double(hi - lo + 1)
        }
        return out
    }
}

import Foundation

/// Reviewer measurement databases hosted on squig.link. Each site is a CrinGraph
/// deployment: `phone_book.json` lists the phones, `config.js` names the target
/// curves, and `data/<file> L.txt` / `R.txt` hold REW-style frequency responses.
/// Sites that opted out of cross-site listing (Hangout.Audio among them) are skipped.
/// Two ways to search: one selected database, or every listed database at once.
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

    /// A phone in a particular database; the same model often appears in several.
    struct Hit: Identifiable, Hashable {
        let db: Database
        let entry: Entry
        var id: String { db.id + "|" + entry.file }
    }

    /// What a database's page config says: its target curves and where its data lives.
    private struct Resolved {
        let targets: [Target]
        /// Folder holding `<file> L.txt`, relative to the database folder.
        let phoneDir: String
        /// Folders tried, in order, for `<target> Target.txt`.
        let targetDirs: [String]
        /// Measurement files are `<file> <channel><sample>.txt`, e.g. `X L.txt` or `X R2.txt`.
        let channels: [String]
        let samples: [String]
    }

    /// Which kind of curve to correct towards when the database is not narrowed down.
    enum Style: String, CaseIterable, Identifiable {
        case harman, neutral
        var id: String { rawValue }
        var title: String { self == .harman ? "Harman" : "Neutral" }
    }

    enum State: Equatable { case idle, loading, ready(Int), failed(String) }

    @Published private(set) var databases: [Database] = []
    @Published private(set) var database: Database?
    @Published private(set) var entries: [Entry] = []
    @Published private(set) var targets: [Target] = []
    @Published private(set) var target: Target?
    @Published private(set) var state: State = .idle
    /// Every-database index: phone books loaded so far, out of how many.
    @Published private(set) var books: [String: [Entry]] = [:]
    @Published private(set) var indexed = 0
    @Published private(set) var indexTotal = 0
    private var indexing = false
    private var resolved: [String: Resolved] = [:]
    private var siteWaiters: [() -> Void] = []
    private var sitesLoading = false

    /// Cache-file stem for a database, shared by single and every-database loading. The
    /// folder is part of it: one site can host several databases of the same type.
    private static func key(_ db: Database) -> String {
        let folder = db.folder.path.lowercased().filter { $0.isLetter || $0.isNumber }
        return db.site + "-" + db.type.lowercased().filter { $0.isLetter || $0.isNumber } + (folder.isEmpty ? "" : "-" + folder)
    }

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

    func loadSites(then done: (() -> Void)? = nil) {
        guard databases.isEmpty else { done?(); return }
        if let done { siteWaiters.append(done) }
        guard !sitesLoading else { return }
        sitesLoading = true
        Self.fetch(Self.sitesJS, cache: "squig-sites.js") { [weak self] jsResult in
            let optedOut = (try? jsResult.get()).flatMap(Self.parseOptedOut) ?? Self.knownOptedOut
            Self.fetch(Self.sitesJSON, cache: "squig-sites.json") { jsonResult in
                let parsed = (try? jsonResult.get()).map { Self.parseSites($0, optedOut: optedOut) } ?? []
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.sitesLoading = false
                    self.databases = parsed
                    let waiters = self.siteWaiters
                    self.siteWaiters = []
                    waiters.forEach { $0() }
                }
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
        entries = []; targets = []; target = nil; state = .idle
        load()
    }

    func load() {
        guard let db = database, state != .loading, entries.isEmpty else { return }
        state = .loading
        loadBook(db) { [weak self] book in
            guard let self, self.database == db else { return }
            guard let book else { self.state = .failed("phone book unavailable"); return }
            self.resolve(db) { r in
                guard self.database == db else { return }
                self.entries = book
                self.targets = r.targets
                self.target = self.candidates(for: db, among: r.targets, style: nil).first
                self.state = .ready(book.count)
            }
        }
    }

    /// Loads every listed database's phone book, a few at a time; results appear in
    /// `books` as they arrive. A database that fails is skipped.
    func loadAll() {
        guard !indexing, indexTotal == 0 || indexed < indexTotal else { return }
        indexing = true
        loadSites { [weak self] in
            guard let self else { return }
            let pending = self.databases.filter { self.books[$0.id] == nil }
            self.indexTotal = self.databases.count
            self.indexed = self.databases.count - pending.count
            var queue = pending[...]
            func next() {
                guard let db = queue.popFirst() else { return }
                self.loadBook(db) { book in
                    if let book { self.books[db.id] = book }
                    self.indexed += 1
                    if self.indexed >= self.indexTotal { self.indexing = false }
                    next()
                }
            }
            if pending.isEmpty { self.indexing = false }
            for _ in 0..<min(6, pending.count) { next() }
        }
    }

    func setTarget(_ t: Target) {
        target = t
        if let db = database { UserDefaults.standard.set(t.name, forKey: "squig.target.\(db.id)") }
    }

    /// Targets to try for a database, best first. Narrowed to one database (`style` nil)
    /// the target you picked there comes first; searching everywhere, the style decides.
    private func candidates(for db: Database, among targets: [Target], style: Style?) -> [Target] {
        let book = books[db.id] ?? (db == database ? entries : [])
        let phones = Set(book.flatMap { [$0.title.lowercased(), $0.file.lowercased(), "\($0.brand) \($0.model)".lowercased()] })
        let ranked = Self.ranked(targets, for: db, style: style ?? .harman, phones: phones)
        guard style == nil, let remembered = UserDefaults.standard.string(forKey: "squig.target.\(db.id)"),
              let picked = targets.first(where: { $0.name == remembered }) else { return ranked }
        return [picked] + ranked.filter { $0 != picked }
    }

    /// Phone book for one database; calls back on the main queue. Most sites keep it in
    /// `data/` beside the measurements, a few at the site root.
    private func loadBook(_ db: Database, completion: @escaping ([Entry]?) -> Void) {
        if let book = books[db.id] { completion(book); return }
        let cache = "squig-\(Self.key(db))-book.json"
        let finish: (Result<Data, Error>) -> Void = { result in
            let book = (try? result.get()).flatMap { data -> [Entry]? in
                let parsed = Self.parseBook(data)
                return parsed.isEmpty ? nil : parsed
            }
            DispatchQueue.main.async { completion(book) }
        }
        Self.fetch(db.folder.appendingPathComponent("data/phone_book.json"), cache: cache) { result in
            if (try? result.get()).map(Self.parseBook)?.isEmpty == false { finish(result); return }
            Self.fetch(db.folder.appendingPathComponent("phone_book.json"), cache: cache, refresh: true, completion: finish)
        }
    }

    /// Targets and data folder from a database's page config; calls back on the main queue.
    private func resolve(_ db: Database, completion: @escaping (Resolved) -> Void) {
        if let r = resolved[db.id] { completion(r); return }
        let key = Self.key(db)
        Self.configURL(for: db, cache: "squig-\(key)-index.html") { configURL in
            let finish: (Data?) -> Void = { config in
                let text = config.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let r = Self.parseConfig(text)
                DispatchQueue.main.async { [weak self] in
                    self?.resolved[db.id] = r
                    completion(r)
                }
            }
            guard let configURL else { finish(nil); return }
            Self.fetch(configURL, cache: "squig-\(key)-config.js") { finish(try? $0.get()) }
        }
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
                let stem = (phone["prefix"] as? String) ?? "\(brandName) \(model)"
                for (i, file) in files.enumerated() {
                    var suffix = files.count > 1 && i < suffixes.count ? suffixes[i] : ""
                    // Unlabelled variants (pads, positions, units) differ only in the file
                    // name; without this they list as identical rows.
                    if files.count > 1, suffix.isEmpty {
                        suffix = file.hasPrefix(stem) ? String(file.dropFirst(stem.count)).trimmingCharacters(in: .whitespaces) : file
                    }
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
            // `config.js`, `config_hp.js`, `./config.js?cachebust`: the query is dropped.
            let pattern = #"src="([^"?]*config[^"?]*\.js)(\?[^"]*)?""#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let m = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let src = Range(m.range(at: 1), in: html) {
                // Standardized: Foundation keeps a leading `../` at the site root, which 404s.
                completion(URL(string: String(html[src]), relativeTo: db.folder)?.absoluteURL.standardized)
            } else {
                completion(db.folder.appendingPathComponent("config.js"))
            }
        }
    }

    /// Two page formats. CrinGraph: `DIR = "data/"`, `const targets = [ {type, files} ]`,
    /// targets in `DIR/targets/` (older sites: `DIR`). The newer graph tool: a `CONFIG`
    /// object with `PATH.PHONE_MEASUREMENT`, `PATH.TARGET_MEASUREMENT` and `TARGET_MANIFEST`.
    private static func parseConfig(_ config: String) -> Resolved {
        if config.contains("TARGET_MANIFEST") {
            func path(_ key: String, _ fallback: String) -> String {
                guard let m = config.range(of: key + #"\s*:\s*"[^"]*""#, options: .regularExpression) else { return fallback }
                var v = String(config[m].drop { $0 != "\"" }.dropFirst().dropLast())
                if v.hasPrefix("./") { v.removeFirst(2) }
                return v.isEmpty ? fallback : (v.hasSuffix("/") ? v : v + "/")
            }
            return Resolved(targets: parseTargets(config, after: "TARGET_MANIFEST"),
                            phoneDir: path("PHONE_MEASUREMENT", "data/phones/"),
                            targetDirs: [path("TARGET_MEASUREMENT", "data/target/")],
                            channels: ["L", "R"], samples: [""])
        }
        let dir = parseDataDir(config)
        return Resolved(targets: parseTargets(config, after: "targets = ["), phoneDir: dir,
                        targetDirs: [dir + "targets/", dir],
                        channels: parseChannels(config), samples: parseSamples(config))
    }

    /// Target groups `{ type: "Reference", files: ["Harman 2019 IEM", ...] }` in the first
    /// bracketed list after `marker`; `type` is optional. Δ groups and ∆/Δ files are
    /// compensation deltas for display, not curves to aim for.
    private static func parseTargets(_ config: String, after marker: String) -> [Target] {
        guard let marked = config.range(of: marker), let open = config[marked.lowerBound...].firstIndex(of: "[") else { return [] }
        var depth = 0; var end = config.endIndex
        for i in config[open...].indices {
            let c = config[i]
            if c == "[" { depth += 1 } else if c == "]" { depth -= 1; if depth == 0 { end = i; break } }
        }
        let body = String(config[config.index(after: open)..<end])
        var out: [Target] = []
        let groupPattern = #"(?:type\s*:\s*"([^"]*)"\s*,\s*)?files\s*:\s*\[([^\]]*)\]"#
        guard let regex = try? NSRegularExpression(pattern: groupPattern) else { return [] }
        for m in regex.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
            guard let f = Range(m.range(at: 2), in: body) else { continue }
            let group = Range(m.range(at: 1), in: body).map { String(body[$0]) } ?? ""
            if group.hasPrefix("Δ") { continue }
            for raw in body[f].split(separator: ",") {
                let name = raw.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                if !name.isEmpty, !name.hasPrefix("∆"), !name.hasPrefix("Δ") { out.append(Target(name: name, group: group)) }
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

    /// `default_channels = ["L","R"]`; some databases publish one channel only.
    private static func parseChannels(_ config: String) -> [String] {
        guard let m = config.range(of: #"default_channels\s*=\s*\[([^\]]*)\]"#, options: .regularExpression) else { return ["L", "R"] }
        let inner = config[m].drop { $0 != "[" }.dropFirst().dropLast()
        let channels = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "'\"")) }.filter { !$0.isEmpty }
        return channels.isEmpty ? ["L", "R"] : channels
    }

    /// `num_samples = 3` numbers the files `L1`…`L3`; without it there is one unnumbered file.
    private static func parseSamples(_ config: String) -> [String] {
        guard let m = config.range(of: #"num_samples\s*=\s*\d+"#, options: .regularExpression),
              let n = Int(config[m].filter(\.isNumber)), n > 0 else { return [""] }
        return (1...min(n, 5)).map(String.init)
    }

    /// Targets usable for this database, best first for the style. Loudspeaker/room
    /// curves are dropped, and so is a "target" that is really another phone's
    /// measurement (a reviewer's reference unit): correcting towards it is not a target.
    static func ranked(_ targets: [Target], for db: Database, style: Style, phones: Set<String>) -> [Target] {
        let inEar = !db.type.localizedCaseInsensitiveContains("headphone")
        func has(_ t: Target, _ words: [String]) -> Bool { words.contains { t.name.range(of: $0, options: .caseInsensitive) != nil } }
        func score(_ t: Target) -> Int {
            let harman = has(t, ["harman"])
            // "IE"/"OE" as words, years Harman used for each, and the plain descriptions.
            let fitsIE = has(t, [" IE ", " IE", "in-ear", "IEM", "2017", "2019"])
            let fitsOE = has(t, [" OE ", " OE", "over-ear", "2013", "2015", "2018"])
            let fits = inEar ? !fitsOE : !fitsIE
            let neutral = has(t, ["DF", "diffuse", "neutral", "ISO", "JM-1", "KEMAR", "free field"])
                || t.group.localizedCaseInsensitiveContains("neutral") || t.group.localizedCaseInsensitiveContains("hrtf")
            switch style {
            case .harman: return harman ? (fits ? 0 : 1) : neutral ? 2 : 3
            case .neutral: return neutral ? 0 : harman ? (fits ? 1 : 2) : 3
            }
        }
        return targets
            .filter { !has($0, ["in-room", "loudspeaker", "speaker"]) && !phones.contains($0.name.lowercased()) }
            .enumerated().sorted { (score($0.element), $0.offset) < (score($1.element), $1.offset) }.map(\.element)
    }

    /// The selected database, or every indexed one when `everywhere`.
    func search(_ query: String, everywhere: Bool, limit: Int = 40) -> [Hit] {
        let terms = query.lowercased().split(separator: " ").map(String.init)
        guard !terms.isEmpty else { return [] }
        let pool: [(Database, [Entry])]
        if everywhere {
            pool = databases.compactMap { db in books[db.id].map { (db, $0) } }
        } else {
            pool = database.map { [($0, entries)] } ?? []
        }
        var hits: [Hit] = []
        for (db, book) in pool {
            for e in book where terms.allSatisfy({ e.title.lowercased().contains($0) }) {
                hits.append(Hit(db: db, entry: e))
            }
        }
        return hits
            .sorted { ($0.entry.title.count, $0.db.siteName.lowercased()) < ($1.entry.title.count, $1.db.siteName.lowercased()) }
            .prefix(limit).map { $0 }
    }

    // MARK: Measurements

    /// The correction (target − measurement, centred and smoothed) for a phone, ready to fit,
    /// and the name of the target used. `style` nil means the database's own chosen target.
    func fetchCorrection(_ hit: Hit, style: Style?, completion: @escaping (Result<(curve: [(frequency: Double, gainDB: Double)], target: String), Error>) -> Void) {
        resolve(hit.db) { [weak self] r in
            guard let self else { return }
            // A config can list targets its server does not have: try the next best rather
            // than fail, and when the database has none worth using, AutoEq's curve.
            let targets = self.candidates(for: hit.db, among: r.targets, style: style)
            Self.correction(for: hit, targets: Array(targets.prefix(6)), fallback: Self.standardTarget(for: hit.db, style: style ?? .harman),
                            resolved: r, completion: completion)
        }
    }

    /// AutoEq's published curve of the style for this kind of phone. Harman's research
    /// curves are for 711/GRAS rigs, so a 5128 database gets none.
    private static func standardTarget(for db: Database, style: Style) -> (name: String, url: URL)? {
        let rig5128 = db.type.contains("5128")
        let inEar = !db.type.localizedCaseInsensitiveContains("headphone")
        let file: String?
        switch style {
        case .harman: file = rig5128 ? nil : inEar ? "Harman in-ear 2019" : "Harman over-ear 2018"
        case .neutral: file = rig5128 ? "Diffuse field 5128" : "Diffuse field GRAS KEMAR"
        }
        guard let file, let url = URL(string: "https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master/targets/" + (file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file) + ".csv") else { return nil }
        return (file + " (AutoEq)", url)
    }

    private static func correction(for hit: Hit, targets: [Target], fallback: (name: String, url: URL)?, resolved r: Resolved, completion: @escaping (Result<(curve: [(frequency: Double, gainDB: Double)], target: String), Error>) -> Void) {
        let db = hit.db, entry = hit.entry
        func url(_ dir: String, _ name: String) -> URL? {
            URL(string: dir + (name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name), relativeTo: db.folder)?.absoluteURL.standardized
        }
        let files = r.channels.flatMap { c in r.samples.map { "\(entry.file) \(c)\($0).txt" } }
        let channels = (files + ["\(entry.file).txt"]).compactMap { url(r.phoneDir, $0) }
        let group = DispatchGroup()
        var curves: [[(Double, Double)]] = []
        var targetCurve: [(Double, Double)]?
        var targetName = ""
        let lock = NSLock()
        for url in channels.dropLast() {
            group.enter()
            fetch(url, cache: nil) { result in
                if let data = try? result.get(), let curve = parseResponse(data), curve.count > 20 {
                    lock.lock(); curves.append(curve); lock.unlock()
                }
                group.leave()
            }
        }
        var attempts: [(name: String, url: URL, cache: String)] = targets.flatMap { t in
            r.targetDirs.compactMap { url($0, "\(t.name) Target.txt") }.map { (t.name, $0, "squig-\(key(db))-target-\(t.name.filter { $0.isLetter || $0.isNumber }).txt") }
        }
        if let fallback { attempts.append((fallback.name, fallback.url, "autoeq-target-\(fallback.name.filter { $0.isLetter || $0.isNumber }).csv")) }
        group.enter()
        func tryTarget(_ i: Int) {
            guard i < attempts.count else { group.leave(); return }
            let a = attempts[i]
            fetch(a.url, cache: a.cache) { result in
                if let data = try? result.get(), let curve = parseResponse(data), curve.count > 20 {
                    targetCurve = curve; targetName = a.name
                    group.leave()
                } else {
                    tryTarget(i + 1)
                }
            }
        }
        tryTarget(0)
        group.notify(queue: .global(qos: .userInitiated)) {
            var measured = curves
            if measured.isEmpty, let single = channels.last {
                // Single-file phones: no channel suffix.
                let sem = DispatchSemaphore(value: 0)
                fetch(single, cache: nil) { result in
                    if let data = try? result.get(), let curve = parseResponse(data) { measured = [curve] }
                    sem.signal()
                }
                sem.wait()
            }
            guard !measured.isEmpty else { DispatchQueue.main.async { completion(.failure(SquigError.noMeasurement)) }; return }
            guard let targetCurve, targetCurve.count > 20 else { DispatchQueue.main.async { completion(.failure(SquigError.noTarget)) }; return }
            let correction = Correction.compute(measurement: Correction.average(measured), target: targetCurve)
            DispatchQueue.main.async { completion(.success((curve: correction, target: targetName))) }
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
    private static func fetch(_ url: URL, cache: String?, refresh: Bool = false, completion: @escaping (Result<Data, Error>) -> Void) {
        if let cache, !refresh {
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

import SwiftUI
import MapKit
import CoreLocation

// MARK: - واجهة الموقع (api/v1)

/** طلبات واجهة الموقع الرسمية؛ صفحة المصحف تطلبها عبر الجسر (cmd: net) لأن ask.php لا يسمح بطلبات الصفحات */
enum SiteAPI {
    static let base = "https://7awlalaalam.com/quran/api/v1/"

    static func request(_ path: String, method: String = "GET", body: String? = nil) async -> (Int, String) {
        let ok = path.range(of: "^[A-Za-z0-9_\\-./?=&%:+]*$", options: .regularExpression) != nil
        guard ok, !path.contains(".."), !path.contains("://"), let url = URL(string: base + path) else { return (0, "") }
        var req = URLRequest(url: url, timeoutInterval: method == "POST" ? 60 : 20)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("HawlalaalamApp/2 (iOS)", forHTTPHeaderField: "User-Agent")
        if method == "POST" {
            req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            req.httpBody = (body ?? "{}").data(using: .utf8)
        }
        do {
            let (d, r) = try await URLSession.shared.data(for: req)
            return ((r as? HTTPURLResponse)?.statusCode ?? 0, String(data: d, encoding: .utf8) ?? "")
        } catch { return (0, "") }
    }
}

// MARK: - المساجد القريبة

struct NearMosque: Identifiable, Hashable {
    let id: String
    let name: String
    let coord: CLLocationCoordinate2D
    let jami: Bool            // جامع (تقام فيه الجمعة)
    let musalla: Bool         // مصلى
    var meters: Double = 0

    static func == (a: NearMosque, b: NearMosque) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/**
 * يجمع المساجد حول المستخدم من مصدرين مجانيين: بحث خرائط Apple، وOpenStreetMap (Overpass).
 * النتائج تُحفظ لكل منطقة، ولا يُعاد البحث إلا إذا ابتعد المستخدم نحو كيلومتر أو مرّ يوم.
 * الموقع يُطلب مرة واحدة (لا متابعة مستمرة) توفيرًا للبطارية.
 */
@MainActor
final class MosqueFinder: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var center: CLLocationCoordinate2D?
    @Published var list: [NearMosque] = []
    @Published var loading = false
    @Published var failed = false
    @Published var denied = false

    private var lm: CLLocationManager?
    static let radius: Double = 2500

    func start() {
        if center != nil { return }
        let m = CLLocationManager()
        m.delegate = self
        m.desiredAccuracy = kCLLocationAccuracyHundredMeters
        lm = m
        switch m.authorizationStatus {
        case .notDetermined: m.requestWhenInUseAuthorization()
        case .denied, .restricted: useStored(denied: true)
        default: m.requestLocation()
        }
        // إن تأخر الموقع نبدأ بموقع المدينة المحفوظ
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self, self.center == nil else { return }
            self.useStored(denied: false)
        }
    }

    private func useStored(denied: Bool) {
        self.denied = denied
        if center == nil, Geo.has { set(CLLocationCoordinate2D(latitude: Geo.lat, longitude: Geo.lng)) }
        else if center == nil { failed = true }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        Task { @MainActor in
            switch m.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways: m.requestLocation()
            case .denied, .restricted: self.useStored(denied: true)
            default: break
            }
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations l: [CLLocation]) {
        guard let c = l.last?.coordinate else { return }
        Task { @MainActor in self.set(c) }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError e: Error) {
        Task { @MainActor in self.useStored(denied: false) }
    }

    private func set(_ c: CLLocationCoordinate2D) {
        let first = center == nil
        center = c
        lm = nil
        if first { Task { await load(c) } }
    }

    func reload() { if let c = center { Task { await load(c, force: true) } } }

    // MARK: التحميل والحفظ

    private struct Cached: Codable { var lat: Double; var lng: Double; var at: Double; var items: [[String: String]] }
    private static var cacheURL: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("mosques.json") }

    private func load(_ c: CLLocationCoordinate2D, force: Bool = false) async {
        let here = CLLocation(latitude: c.latitude, longitude: c.longitude)
        if !force, let d = try? Data(contentsOf: Self.cacheURL), let k = try? JSONDecoder().decode(Cached.self, from: d),
           Date().timeIntervalSince1970 - k.at < 86400 * 7,
           here.distance(from: CLLocation(latitude: k.lat, longitude: k.lng)) < 1000 {
            var items = k.items.compactMap(Self.decode)
            let ap = await approved()                    // ما اعتمده الموقع حديثًا يظهر فورًا ولو كانت المنطقة محفوظة
            for m in ap where !items.contains(where: { Self.near($0.coord, m.coord, 30) }) { items.append(m) }
            apply(items, here)
            return
        }
        loading = true; failed = false
        async let a = appleSearch(c)
        async let t = tiles(c)
        let (apple, tiled) = await (a, t)
        var osm: [NearMosque]
        if let t = tiled { osm = t } else { osm = await overpass(c) }
        var all = osm
        for m in apple where !all.contains(where: { Self.near($0.coord, m.coord, 45) }) { all.append(m) }
        let ap = await approved()
        for m in ap where !all.contains(where: { Self.near($0.coord, m.coord, 30) }) { all.append(m) }
        loading = false
        if all.isEmpty && apple.isEmpty && osm.isEmpty { failed = list.isEmpty; return }
        apply(all, here)
        let k = Cached(lat: c.latitude, lng: c.longitude, at: Date().timeIntervalSince1970, items: all.map(Self.encode))
        if let d = try? JSONEncoder().encode(k) { try? d.write(to: Self.cacheURL) }
    }

    private func apply(_ items: [NearMosque], _ here: CLLocation) {
        list = items.map { m in
            var x = m
            x.meters = here.distance(from: CLLocation(latitude: m.coord.latitude, longitude: m.coord.longitude))
            return x
        }.filter { $0.meters <= Self.radius * 1.3 }.sorted { $0.meters < $1.meters }
    }

    private static func near(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, _ m: Double) -> Bool {
        CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) < m
    }

    private static func encode(_ m: NearMosque) -> [String: String] {
        ["id": m.id, "n": m.name, "la": String(m.coord.latitude), "lo": String(m.coord.longitude), "j": m.jami ? "1" : "0", "u": m.musalla ? "1" : "0"]
    }

    private static func decode(_ d: [String: String]) -> NearMosque? {
        guard let id = d["id"], let la = Double(d["la"] ?? ""), let lo = Double(d["lo"] ?? "") else { return nil }
        return NearMosque(id: id, name: d["n"] ?? "", coord: .init(latitude: la, longitude: lo), jami: d["j"] == "1", musalla: d["u"] == "1")
    }

    static func kind(_ name: String) -> (jami: Bool, musalla: Bool) {
        let n = name.lowercased()
        return (n.contains("جامع") || n.contains("jami") || n.contains("masjid jami"), n.contains("مصلى") || n.contains("مصلّى") || n.contains("musalla") || n.contains("prayer room"))
    }

    private func appleSearch(_ c: CLLocationCoordinate2D) async -> [NearMosque] {
        let region = MKCoordinateRegion(center: c, latitudinalMeters: Self.radius * 2, longitudinalMeters: Self.radius * 2)
        var out: [NearMosque] = []
        for q in ["مسجد", "جامع", "mosque"] {
            let r = MKLocalSearch.Request()
            r.naturalLanguageQuery = q
            r.region = region
            r.resultTypes = .pointOfInterest
            guard let res = try? await MKLocalSearch(request: r).start() else { continue }
            for it in res.mapItems {
                let co = it.placemark.coordinate
                let name = it.name ?? ""
                let lower = name.lowercased()
                guard lower.contains("مسجد") || lower.contains("جامع") || lower.contains("مصلى") || lower.contains("mosque") || lower.contains("masjid") else { continue }
                if out.contains(where: { Self.near($0.coord, co, 30) }) { continue }
                let k = Self.kind(name)
                out.append(NearMosque(id: "a\(co.latitude),\(co.longitude)", name: name, coord: co, jami: k.jami, musalla: k.musalla))
            }
        }
        return out
    }

    /** المساجد التي أضافها المستخدمون واعتمدها الموقع */
    private func approved() async -> [NearMosque] {
        let (code, txt) = await SiteAPI.request("mosques/approved")
        guard code == 200, let d = txt.data(using: .utf8), let arr = try? JSONSerialization.jsonObject(with: d) as? [[Any]] else { return [] }
        return arr.compactMap { e in
            guard e.count >= 3 else { return nil }
            let la = (e[0] as? Double) ?? Double("\(e[0])"), lo = (e[1] as? Double) ?? Double("\(e[1])")
            guard let la, let lo else { return nil }
            let k = e.count > 3 ? "\(e[3])" : ""
            return NearMosque(id: "u\(la),\(lo)", name: e[2] as? String ?? "", coord: .init(latitude: la, longitude: lo),
                              jami: k == "jami" || k == "1", musalla: k == "musalla" || k == "2")
        }
    }

    /** ملفات المساجد الجاهزة (الخليج ومصر والأردن) من مستودع التطبيق؛ nil = المنطقة غير مغطاة فنسأل Overpass */
    private func tiles(_ c: CLLocationCoordinate2D) async -> [NearMosque]? {
        let dLa = Self.radius / 111000, dLo = Self.radius / (111000 * cos(c.latitude * .pi / 180))
        var keys = Set<String>()
        for a in [-1.0, 1.0] { for b in [-1.0, 1.0] {
            keys.insert("\(Int(floor((c.latitude + a * dLa) * 4)))_\(Int(floor((c.longitude + b * dLo) * 4)))")
        } }
        var out: [NearMosque] = [], covered = false
        for k in keys {
            for base in ["https://raw.githubusercontent.com/7awlalaalam-creator/hawlalaalam-app/main/data/mosques/",
                         "https://cdn.jsdelivr.net/gh/7awlalaalam-creator/hawlalaalam-app@main/data/mosques/"] {
                guard let u = URL(string: base + k + ".json"),
                      let (d, r) = try? await URLSession.shared.data(for: URLRequest(url: u, timeoutInterval: 15)),
                      let code = (r as? HTTPURLResponse)?.statusCode else { continue }
                if code == 404 { break }
                guard code == 200, let arr = try? JSONSerialization.jsonObject(with: d) as? [[Any]] else { continue }
                covered = true
                for e in arr {
                    guard e.count >= 5, let la = e[0] as? Double, let lo = e[1] as? Double else { continue }
                    let nAr = e[2] as? String ?? "", nEn = e[3] as? String ?? ""
                    let kind = e[4] as? Int ?? 0
                    out.append(NearMosque(id: "t\(la),\(lo)", name: Lang.en ? (nEn.isEmpty ? nAr : nEn) : (nAr.isEmpty ? nEn : nAr),
                                          coord: .init(latitude: la, longitude: lo), jami: kind == 1, musalla: kind == 2))
                }
                break
            }
        }
        return covered ? out : nil
    }

    /** OpenStreetMap: الموقع يُقرّب إلى ~١٠٠ م قبل الإرسال */
    private func overpass(_ c: CLLocationCoordinate2D) async -> [NearMosque] {
        let lat = (c.latitude * 1000).rounded() / 1000, lng = (c.longitude * 1000).rounded() / 1000
        let q = "[out:json][timeout:45];(nwr[\"amenity\"=\"place_of_worship\"][\"religion\"=\"muslim\"](around:\(Int(Self.radius)),\(lat),\(lng)););out center 200;"
        for host in ["https://overpass-api.de/api/interpreter", "https://overpass.private.coffee/api/interpreter"] {
            guard let u = URL(string: host) else { continue }
            var req = URLRequest(url: u, timeoutInterval: 50)
            req.httpMethod = "POST"
            req.setValue("HawlalaalamApp/2 (iOS)", forHTTPHeaderField: "User-Agent")
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.httpBody = ("data=" + (q.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")).data(using: .utf8)
            guard let (d, r) = try? await URLSession.shared.data(for: req), (r as? HTTPURLResponse)?.statusCode == 200,
                  let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let els = o["elements"] as? [[String: Any]] else { continue }
            var out: [NearMosque] = []
            for e in els {
                let tags = e["tags"] as? [String: String] ?? [:]
                let center = e["center"] as? [String: Double]
                guard let la = (e["lat"] as? Double) ?? center?["lat"], let lo = (e["lon"] as? Double) ?? center?["lon"] else { continue }
                let name = (Lang.en ? (tags["name:en"] ?? tags["name"]) : (tags["name:ar"] ?? tags["name"])) ?? ""
                let k = Self.kind(name)
                let jami = k.jami || tags["mosque"] == "jami" || tags["friday_prayer"] == "yes"
                let musalla = k.musalla
                out.append(NearMosque(id: "o\(e["id"] ?? 0)", name: name, coord: .init(latitude: la, longitude: lo), jami: jami, musalla: musalla))
            }
            return out
        }
        return []
    }
}

enum Distance {
    static func text(_ m: Double) -> String {
        m < 1000 ? ar(Int((m / 10).rounded() * 10)) + L(" م") : ar(String(format: "%.1f", m / 1000)) + L(" كم")
    }
    /** المشي ~٥ كم/س على الطريق (المسافة المستقيمة × ١٫٣) */
    static func walk(_ m: Double) -> String {
        let min = max(1, Int((m * 1.3 / 83).rounded()))
        return ar(min) + L(" د مشيًا")
    }
    static func drive(_ m: Double) -> String {
        let min = max(1, Int((m * 1.4 / 400).rounded()))
        return ar(min) + L(" د بالسيارة")
    }
}

struct MosquesView: View {
    @StateObject private var finder = MosqueFinder()
    @State private var selected: NearMosque?
    @State private var filter = 0                 // ٠ الكل، ١ الجوامع، ٢ المصليات
    @State private var showList = false
    @State private var showAdd = false
    @AppStorage("mosq_sat") private var satellite = false
    @Environment(\.colorScheme) private var scheme

    private var shown: [NearMosque] {
        switch filter {
        case 1: return finder.list.filter { $0.jami }
        case 2: return finder.list.filter { $0.musalla }
        default: return finder.list
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            MosqueMap(satellite: satellite, center: finder.center, items: finder.list, selected: $selected)
                .ignoresSafeArea(edges: .bottom)
            if finder.loading && finder.list.isEmpty {
                VStack { ProgressView(); Text(L("نبحث عن المساجد حولك…")).font(AppFont.ui(13)).foregroundColor(Palette.muted) }
                    .padding(18).card().frame(maxHeight: .infinity)
            } else if finder.failed && finder.list.isEmpty {
                VStack(spacing: 10) {
                    Text(finder.center == nil ? L("حدّد موقعك من الإعدادات أو اسمح بالوصول للموقع لعرض المساجد القريبة.") : L("تعذّر جلب المساجد الآن. تحقّق من الاتصال وحاول مجددًا."))
                        .font(AppFont.ui(14)).foregroundColor(Palette.ink).multilineTextAlignment(.center)
                    Button(L("حاول مجددًا")) { finder.reload() }.font(AppFont.ui(14, 700))
                    mapsSearchButton
                }
                .padding(18).card().padding(24).frame(maxHeight: .infinity)
            }
            VStack(spacing: 10) {
                HStack {
                    if !finder.list.isEmpty {
                        Button { if let m = finder.list.first { selected = m } } label: {
                            Text(L("أقرب مسجد")).font(AppFont.ui(14, 700)).foregroundColor(Color(hex: 0x163942))
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(Capsule().fill(Color(hex: 0xE4C58A)))
                        }
                        Spacer()
                        Button { showList = true } label: {
                            Label(L("القائمة"), systemImage: "list.bullet").font(AppFont.ui(14, 700)).foregroundColor(.white)
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .background(Capsule().fill(Palette.dark))
                        }
                    }
                }
                if let m = selected { card(m) }
            }
            .padding(12)
        }
        .navigationTitle(L("المساجد القريبة"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { finder.start() }
        .sheet(isPresented: $showList) { listSheet }
        .sheet(isPresented: $showAdd) { AddMosqueView(start: finder.center ?? CLLocationCoordinate2D(latitude: Geo.lat, longitude: Geo.lng)) }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { satellite.toggle() } label: { Image(systemName: satellite ? "map" : "globe.americas.fill") }
                    .accessibilityLabel(satellite ? L("الخريطة") : L("القمر الصناعي"))
                Button { showAdd = true } label: { Image(systemName: "plus.circle") }
                    .accessibilityLabel(L("أضف مسجدًا ناقصًا"))
            }
        }
        .environment(\.layoutDirection, Lang.dir)
    }

    private func card(_ m: NearMosque) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "building.columns.fill").font(.system(size: 22)).foregroundColor(Color(hex: 0xE4C58A))
                    .frame(width: 46, height: 46).background(RoundedRectangle(cornerRadius: 14).fill(Palette.dark))
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.name.isEmpty ? L("مسجد") : m.name).font(AppFont.ui(17, 700)).foregroundColor(Palette.ink).lineLimit(2)
                    Text(m.jami ? L("مسجد جامع") : (m.musalla ? L("مصلى") : L("مسجد"))).font(AppFont.ui(12)).foregroundColor(Palette.muted)
                }
                Spacer()
                Button { selected = nil } label: { Image(systemName: "xmark").foregroundColor(Palette.muted) }
                    .accessibilityLabel(L("إغلاق"))
            }
            HStack(spacing: 8) {
                chip("🚶 " + Distance.walk(m.meters))
                chip(Distance.text(m.meters))
                chip("🚗 " + Distance.drive(m.meters))
            }
            HStack(spacing: 8) {
                Button { directions(m) } label: {
                    Text(L("الاتجاهات")).font(AppFont.ui(15, 700)).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.dark))
                }
                Button { share(m) } label: {
                    Image(systemName: "square.and.arrow.up").foregroundColor(Palette.ink)
                        .frame(width: 48, height: 44).background(RoundedRectangle(cornerRadius: 12).stroke(Palette.line))
                }
                .accessibilityLabel(L("مشاركة"))
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22).fill(Palette.card).shadow(color: .black.opacity(0.25), radius: 14, y: 6))
    }

    private func chip(_ t: String) -> some View {
        Text(t).font(AppFont.ui(12)).foregroundColor(Palette.ink).padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10).fill(Palette.chip))
    }

    private var listSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $filter) {
                    Text(L("الكل")).tag(0); Text(L("الجوامع")).tag(1); Text(L("المصليات")).tag(2)
                }
                .pickerStyle(.segmented).padding(12)
                List {
                    ForEach(shown) { m in
                        Button { selected = m; showList = false } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "building.columns").foregroundColor(Color(hex: 0xE4C58A))
                                    .frame(width: 38, height: 38).background(RoundedRectangle(cornerRadius: 11).fill(Palette.dark))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.name.isEmpty ? L("مسجد") : m.name).font(AppFont.ui(15, 700)).foregroundColor(Palette.ink)
                                    Text(m.jami ? L("مسجد جامع") : (m.musalla ? L("مصلى") : L("مسجد"))).font(AppFont.ui(12)).foregroundColor(Palette.muted)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(Distance.text(m.meters)).font(AppFont.ui(14, 700)).foregroundColor(Palette.ink)
                                    Text(m.meters < 1200 ? Distance.walk(m.meters) : Distance.drive(m.meters)).font(AppFont.ui(11)).foregroundColor(Palette.muted)
                                }
                            }
                        }
                    }
                    Section { mapsSearchButton.frame(maxWidth: .infinity) }
                }
                .listStyle(.plain)
            }
            .navigationTitle(L("مساجد قريبة: ") + ar(finder.list.count))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .environment(\.layoutDirection, Lang.dir)
    }

    private var mapsSearchButton: some View {
        Button {
            let c = finder.center ?? CLLocationCoordinate2D(latitude: Geo.lat, longitude: Geo.lng)
            let q = (Lang.en ? "mosque" : "مسجد").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let u = URL(string: "http://maps.apple.com/?q=\(q)&sll=\(c.latitude),\(c.longitude)") { UIApplication.shared.open(u) }
        } label: {
            Text(L("لم تجد مسجدك؟ ابحث في الخرائط")).font(AppFont.ui(13, 700)).foregroundColor(Palette.goldDeep)
        }
    }

    private func directions(_ m: NearMosque) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: m.coord))
        item.name = m.name.isEmpty ? L("مسجد") : m.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: m.meters < 1200 ? MKLaunchOptionsDirectionsModeWalking : MKLaunchOptionsDirectionsModeDriving])
    }

    private func share(_ m: NearMosque) {
        let link = "https://maps.apple.com/?ll=\(m.coord.latitude),\(m.coord.longitude)&q=" + ((m.name.isEmpty ? L("مسجد") : m.name).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
        Share.present([(m.name.isEmpty ? L("مسجد") : m.name) + "\n" + link])
    }
}

/** الخريطة: داكنة بألوان التطبيق، وعلامات ذهبية للمساجد */
struct MosqueMap: UIViewRepresentable {
    var satellite = false
    var center: CLLocationCoordinate2D?
    var items: [NearMosque]
    @Binding var selected: NearMosque?

    func makeCoordinator() -> Coord { Coord(self) }

    func makeUIView(context: Context) -> MKMapView {
        let v = MKMapView()
        v.delegate = context.coordinator
        v.overrideUserInterfaceStyle = .dark
        v.showsUserLocation = true
        v.pointOfInterestFilter = .excludingAll
        v.showsCompass = true
        v.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "m")
        return v
    }

    func updateUIView(_ v: MKMapView, context: Context) {
        context.coordinator.parent = self
        let type: MKMapType = satellite ? .hybrid : .standard
        if v.mapType != type { v.mapType = type }
        if let c = center, !context.coordinator.centered {
            context.coordinator.centered = true
            v.setRegion(MKCoordinateRegion(center: c, latitudinalMeters: 2200, longitudinalMeters: 2200), animated: false)
        }
        let have = Set(v.annotations.compactMap { ($0 as? Pin)?.m.id })
        if have != Set(items.map(\.id)) {
            v.removeAnnotations(v.annotations.filter { $0 is Pin })
            v.addAnnotations(items.map { Pin($0) })
        }
        if let s = selected, let p = v.annotations.first(where: { ($0 as? Pin)?.m.id == s.id }) {
            if !(v.selectedAnnotations.contains { $0 === p }) {
                v.selectAnnotation(p, animated: true)
                v.setCenter(s.coord, animated: true)
            }
        } else if selected == nil, !v.selectedAnnotations.isEmpty {
            v.selectedAnnotations.forEach { v.deselectAnnotation($0, animated: true) }
        }
    }

    final class Pin: NSObject, MKAnnotation {
        let m: NearMosque
        var coordinate: CLLocationCoordinate2D { m.coord }
        var title: String? { m.name.isEmpty ? nil : m.name }
        init(_ m: NearMosque) { self.m = m }
    }

    final class Coord: NSObject, MKMapViewDelegate {
        var parent: MosqueMap
        var centered = false
        init(_ p: MosqueMap) { parent = p }

        func mapView(_ v: MKMapView, viewFor a: MKAnnotation) -> MKAnnotationView? {
            guard a is Pin else { return nil }
            let mv = v.dequeueReusableAnnotationView(withIdentifier: "m", for: a) as? MKMarkerAnnotationView
            mv?.markerTintColor = UIColor(red: 0.89, green: 0.77, blue: 0.54, alpha: 1)
            mv?.glyphImage = UIImage(systemName: "building.columns.fill")
            mv?.glyphTintColor = UIColor(red: 0.07, green: 0.21, blue: 0.25, alpha: 1)
            mv?.titleVisibility = .hidden
            mv?.displayPriority = .required
            return mv
        }

        func mapView(_ v: MKMapView, didSelect view: MKAnnotationView) {
            guard let p = view.annotation as? Pin else { return }
            DispatchQueue.main.async { self.parent.selected = p.m }
        }
    }
}

/** «أضف مسجدًا ناقصًا»: حرّك الخريطة حتى يقع الدبوس على المسجد، ثم الاسم والنوع؛ يظهر للجميع بعد المراجعة */
struct AddMosqueView: View {
    let start: CLLocationCoordinate2D
    @Environment(\.dismiss) private var dismiss
    @State private var region: MKCoordinateRegion
    @State private var name = ""
    @State private var kind = "mosque"
    @State private var sending = false
    @State private var error = ""
    @State private var done = false

    init(start: CLLocationCoordinate2D) {
        self.start = start
        _region = State(initialValue: MKCoordinateRegion(center: start, latitudinalMeters: 400, longitudinalMeters: 400))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZStack {
                    CenterMap(region: $region)
                    Image(systemName: "mappin").font(.system(size: 40, weight: .bold)).foregroundColor(Color(hex: 0xC9A24F))
                        .shadow(radius: 4).offset(y: -20).allowsHitTesting(false)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("حرّك الخريطة حتى يقع الدبوس الذهبي على المسجد، ثم اكتب اسمه. تظهر الإضافة للجميع بعد المراجعة."))
                        .font(AppFont.ui(13)).foregroundColor(Palette.muted)
                    TextField(L("اسم المسجد، مثل: مسجد الفتح"), text: $name)
                        .font(AppFont.ui(16)).padding(12).background(RoundedRectangle(cornerRadius: 12).stroke(Palette.line))
                    Picker("", selection: $kind) {
                        Text(L("مسجد")).tag("mosque"); Text(L("جامع")).tag("jami"); Text(L("مصلى")).tag("musalla")
                    }.pickerStyle(.segmented)
                    if !error.isEmpty { Text(error).font(AppFont.ui(13)).foregroundColor(Color(hex: 0xA1460A)) }
                    Button { Task { await send() } } label: {
                        Text(sending ? L("جارٍ الإرسال…") : L("إرسال")).font(AppFont.ui(16, 700)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 13).background(RoundedRectangle(cornerRadius: 12).fill(Palette.dark))
                    }.disabled(sending)
                }
                .padding(16)
            }
            .navigationTitle(L("أضف مسجدًا ناقصًا")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("إلغاء")) { dismiss() } } }
            .alert(L("جزاك الله خيرًا 🤍"), isPresented: $done) {
                Button(L("حسنًا")) { dismiss() }
            } message: { Text(L("وصلت إضافتك، وتظهر للجميع بعد مراجعتها.")) }
        }
        .environment(\.layoutDirection, Lang.dir)
    }

    private static var device: String {
        if let d = Store.d.string(forKey: "mosq_dev") { return d }
        let d = "i" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(20)
        Store.d.set(d, forKey: "mosq_dev")
        return d
    }

    private func send() async {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard n.count >= 3 else { error = L("اكتب اسم المسجد (٣ أحرف على الأقل)."); return }
        let c = region.center
        if CLLocation(latitude: c.latitude, longitude: c.longitude).distance(from: CLLocation(latitude: start.latitude, longitude: start.longitude)) > 20000 {
            error = L("الموقع بعيد عنك؛ أضف المساجد القريبة منك فقط."); return
        }
        sending = true; error = ""
        let body: [String: Any] = ["name": n, "lat": (c.latitude * 1e6).rounded() / 1e6, "lng": (c.longitude * 1e6).rounded() / 1e6, "kind": kind, "device": Self.device]
        let json = (try? JSONSerialization.data(withJSONObject: body)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let (code, txt) = await SiteAPI.request("mosques/add.php", method: "POST", body: json)
        sending = false
        let o = txt.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        if code == 200, (o?["ok"] as? Bool) == true { done = true }
        else if code == 0 { error = L("لا يوجد اتصال بالإنترنت.") }
        else { error = o?["error"] as? String ?? L("تعذّر الإرسال، حاول لاحقًا.") }
    }
}

/** خريطة صفحة الإضافة: صور القمر الصناعي مع الأسماء ليظهر مبنى المسجد ومنارته بوضوح */
struct CenterMap: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion

    func makeCoordinator() -> Coord { Coord(self) }

    func makeUIView(context: Context) -> MKMapView {
        let v = MKMapView()
        v.mapType = .hybrid
        v.showsUserLocation = true
        v.pointOfInterestFilter = .excludingAll
        v.delegate = context.coordinator
        v.setRegion(region, animated: false)
        return v
    }

    func updateUIView(_ v: MKMapView, context: Context) { context.coordinator.parent = self }

    final class Coord: NSObject, MKMapViewDelegate {
        var parent: CenterMap
        init(_ p: CenterMap) { parent = p }
        func mapView(_ v: MKMapView, regionDidChangeAnimated animated: Bool) {
            let r = v.region
            DispatchQueue.main.async { self.parent.region = r }
        }
    }
}

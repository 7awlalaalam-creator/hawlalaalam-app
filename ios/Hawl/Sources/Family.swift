import SwiftUI

// MARK: - ختمة العائلة (نفس خادم صفحة الموقع: khatma-api.php، ونفس رابط الدعوة)

struct FamilyPart: Decodable, Hashable {
    let n: Int
    let by: String?
    let done: Bool
    let mine: Bool
}

struct FamilyGroup: Decodable, Hashable {
    let id: String
    let name: String
    let owner: String
    let deadline: String?
    let round: Int?
    let parts: [FamilyPart]
    var admin: Bool?

    var doneCount: Int { parts.filter { $0.done }.count }
    var takenCount: Int { parts.filter { $0.by != nil }.count }

    /** المشاركون: الاسم، أجزاؤه، وما أتمّه */
    struct Member: Hashable { let name: String; let parts: [Int]; let done: Int }

    var members: [Member] {
        var order: [String] = []
        var map: [String: ([Int], Int)] = [:]
        for p in parts {
            guard let b = p.by, !b.isEmpty else { continue }
            if map[b] == nil { order.append(b); map[b] = ([], 0) }
            map[b]!.0.append(p.n)
            if p.done { map[b]!.1 += 1 }
        }
        return order.map { Member(name: $0, parts: map[$0]!.0, done: map[$0]!.1) }
    }

    var deadlineText: String? {
        guard let d = deadline, !d.isEmpty else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        guard let date = f.date(from: d) else { return nil }
        let o = DateFormatter()
        o.locale = Lang.locale
        o.calendar = Calendar(identifier: .gregorian)
        o.dateFormat = "d MMMM"
        return ar(o.string(from: date))
    }
}

enum FamilyAPI {
    static let endpoint = URL(string: "https://7awlalaalam.com/quran/khatma-api.php")!

    struct Saved: Codable, Hashable { var id: String; var name: String; var adminKey: String? }

    struct Failure: LocalizedError { let message: String; var errorDescription: String? { message } }

    private struct Reply: Decodable {
        let ok: Bool
        let error: String?
        let group: FamilyGroup?
        let adminKey: String?
        let deleted: Bool?
    }

    /** رمز عشوائي يميّز هذا الجهاز (لا يُرسل معه أي بيانات أخرى) */
    static var member: String {
        if let m = Store.d.string(forKey: "family_member"), m.count >= 16 { return m }
        let abc = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        var g = SystemRandomNumberGenerator()
        let m = String((0..<32).map { _ in abc[Int(g.next() % UInt64(abc.count))] })
        Store.d.set(m, forKey: "family_member")
        return m
    }

    static var saved: [Saved] {
        get {
            guard let s = Store.d.string(forKey: "family_groups"), let d = s.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([Saved].self, from: d)) ?? []
        }
        set {
            if let d = try? JSONEncoder().encode(newValue), let s = String(data: d, encoding: .utf8) { Store.d.set(s, forKey: "family_groups") }
        }
    }

    static func remember(_ g: FamilyGroup, adminKey: String? = nil) {
        var l = saved
        if let i = l.firstIndex(where: { $0.id == g.id }) {
            l[i].name = g.name
            if let k = adminKey { l[i].adminKey = k }
        } else {
            l.insert(Saved(id: g.id, name: g.name, adminKey: adminKey), at: 0)
        }
        saved = l
    }

    static func forget(_ id: String) { saved = saved.filter { $0.id != id } }

    static func adminKey(_ id: String) -> String? { saved.first { $0.id == id }?.adminKey }

    static var myName: String {
        get { Store.string("family_name") }
        set { Store.d.set(newValue, forKey: "family_name") }
    }

    static func inviteURL(_ id: String) -> URL { Links.site("family-khatma.html?id=" + id) }

    /** رمز الختمة من رابط الدعوة أو من الرمز نفسه */
    static func parseID(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if valid(t) { return t.uppercased() }
        // رسالة الدعوة كاملة أو رابط بمعاملات إضافية: نبحث عن id=XXXXXX في أي موضع
        if let r = t.range(of: "[?&]id=([A-Za-z2-9]{6})(?![A-Za-z0-9])", options: .regularExpression) {
            return String(t[r].suffix(6)).uppercased()
        }
        return nil
    }

    static func valid(_ id: String) -> Bool { id.range(of: "^[A-Za-z2-9]{6}$", options: .regularExpression) != nil }

    private static func call(_ body: [String: Any]) async throws -> Reply {
        var b = body
        b["member"] = member
        var req = URLRequest(url: endpoint, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(WebConfig.userAgentMark, forHTTPHeaderField: "User-Agent")
        req.httpBody = try JSONSerialization.data(withJSONObject: b)
        let data: Data
        do { data = try await URLSession.shared.data(for: req).0 }
        catch { throw Failure(message: L("تحتاج اتصالًا بالإنترنت")) }
        guard let r = try? JSONDecoder().decode(Reply.self, from: data) else { throw Failure(message: L("تعذّر الاتصال بالخادم، حاول بعد قليل")) }
        if !r.ok { throw Failure(message: r.error ?? L("حدث خطأ، حاول مرة أخرى")) }
        return r
    }

    static func get(_ id: String) async throws -> FamilyGroup {
        var b: [String: Any] = ["action": "get", "id": id]
        if let k = adminKey(id) { b["adminKey"] = k }
        guard let g = try await call(b).group else { throw Failure(message: L("لم نجد هذه الختمة")) }
        return g
    }

    static func create(name: String, owner: String, deadline: Date?) async throws -> FamilyGroup {
        var b: [String: Any] = ["action": "create", "name": name, "owner": owner]
        if let d = deadline {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.locale = Locale(identifier: "en_US_POSIX")
            f.calendar = Calendar(identifier: .gregorian)
            b["deadline"] = f.string(from: d)
        }
        let r = try await call(b)
        guard let g = r.group else { throw Failure(message: L("تعذّر إنشاء الختمة")) }
        remember(g, adminKey: r.adminKey)
        return g
    }

    static func act(_ action: String, _ id: String, part: Int, who: String = "") async throws -> FamilyGroup {
        guard let g = try await call(["action": action, "id": id, "part": part, "who": who]).group else { throw Failure(message: L("حدث خطأ")) }
        return g
    }

    static func newRound(_ id: String) async throws -> FamilyGroup {
        guard let g = try await call(["action": "newround", "id": id, "adminKey": adminKey(id) ?? ""]).group else { throw Failure(message: L("حدث خطأ")) }
        return g
    }

    static func delete(_ id: String) async throws {
        _ = try await call(["action": "delete", "id": id, "adminKey": adminKey(id) ?? ""])
        forget(id)
    }
}

// MARK: - ختماتي وإنشاء ختمة

struct FamilyListView: View {
    var openID: String?
    @State private var saved = FamilyAPI.saved
    @State private var name = ""
    @State private var owner = FamilyAPI.myName
    @State private var hasDeadline = false
    @State private var deadline = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    @State private var joinText = ""
    @State private var busy = false
    @State private var error: String?
    @State private var path: String?
    @State private var opened = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("ختمة العائلة")).font(AppFont.ui(13, 700)).foregroundColor(Palette.gold)
                    Text(L("نختم القرآن معًا")).font(AppFont.ui(22, 700)).foregroundColor(.white)
                    Text(L("أنشئ ختمة وأرسل رابطها لأهلك، وكل فرد يحجز جزءًا يقرؤه، وتتابعون التقدّم حتى الختم."))
                        .font(AppFont.ui(13)).foregroundColor(Palette.onDarkMuted)
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 20).fill(Palette.dark))

                if !saved.isEmpty {
                    Text(L("ختماتي")).font(AppFont.ui(15, 700)).foregroundColor(Palette.ink)
                    VStack(spacing: 0) {
                        ForEach(Array(saved.enumerated()), id: \.element.id) { i, g in
                            if i > 0 { Rectangle().fill(Palette.divider).frame(height: 1) }
                            Button { path = g.id } label: {
                                HStack {
                                    Image(systemName: "person.3.fill").foregroundColor(Palette.goldDeep)
                                        .frame(width: 40, height: 40).background(Circle().fill(Palette.chip))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(g.name).font(AppFont.ui(15, 700)).foregroundColor(Palette.ink)
                                        Text(g.adminKey != nil ? L("أنشأتها أنت") : L("مشارك")).font(AppFont.ui(12)).foregroundColor(Palette.muted)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.left").foregroundColor(Palette.muted)
                                }
                                .padding(.vertical, 10).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14).card()
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(L("ختمة جديدة")).font(AppFont.ui(16, 700)).foregroundColor(Palette.ink)
                    field(L("اسم الختمة"), L("مثل: ختمة رمضان للعائلة"), $name)
                    field(L("اسمك كما يراه أهلك"), L("اسمك"), $owner)
                    Toggle(isOn: $hasDeadline) { Text(L("نختم قبل تاريخ")).font(AppFont.ui(14, 700)).foregroundColor(Palette.ink) }
                        .tint(Palette.goldDeep)
                    if hasDeadline {
                        DatePicker("", selection: $deadline, in: Date()..., displayedComponents: .date)
                            .datePickerStyle(.compact).labelsHidden()
                            .environment(\.calendar, Calendar(identifier: .gregorian))
                    }
                    Button { Task { await create() } } label: {
                        Pill(title: busy ? L("جارٍ الإنشاء…") : L("أنشئ الختمة"), systemImage: "plus", primary: true, height: 50)
                    }
                    .buttonStyle(.plain)
                    .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty || owner.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(16).card()

                VStack(alignment: .leading, spacing: 10) {
                    Text(L("لديك رابط ختمة؟")).font(AppFont.ui(16, 700)).foregroundColor(Palette.ink)
                    field(L("الصق الرابط أو الرمز"), "7awlalaalam.com/quran/family-khatma.html?id=…", $joinText)
                    Button {
                        if let id = FamilyAPI.parseID(joinText) { path = id; joinText = "" } else { error = L("الرابط أو الرمز غير صحيح") }
                    } label: { Pill(title: L("افتح الختمة"), systemImage: "link", height: 46) }
                    .buttonStyle(.plain)
                    .disabled(joinText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(16).card()

                Text(L("لا نطلب بريدًا ولا رقمًا. الختمة يراها من معه رابطها فقط.")).font(AppFont.ui(12)).foregroundColor(Palette.muted)
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center)
            }
            .padding(16)
        }
        .background(Palette.page.ignoresSafeArea())
        .navigationTitle(L("ختمة العائلة"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: Binding(get: { path != nil }, set: { if !$0 { path = nil; saved = FamilyAPI.saved } })) {
            if let id = path { FamilyGroupView(id: id) }
        }
        .onAppear {
            saved = FamilyAPI.saved
            if !opened, let id = openID { opened = true; path = id }
        }
        .alert(L("ختمة العائلة"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button(L("حسنًا"), role: .cancel) { }
        } message: { Text(error ?? "") }
    }

    private func field(_ label: String, _ placeholder: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(AppFont.ui(13, 700)).foregroundColor(Palette.muted)
            TextField(placeholder, text: text)
                .font(AppFont.ui(15))
                .padding(.horizontal, 12).frame(minHeight: 44)
                .card(Palette.page, border: Palette.fieldBorder, radius: 12)
        }
    }

    private func create() async {
        busy = true
        defer { busy = false }
        do {
            let o = owner.trimmingCharacters(in: .whitespaces)
            FamilyAPI.myName = o
            let g = try await FamilyAPI.create(name: name.trimmingCharacters(in: .whitespaces), owner: o, deadline: hasDeadline ? deadline : nil)
            name = ""
            saved = FamilyAPI.saved
            path = g.id
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - الختمة: الأجزاء والمشاركون

struct FamilyGroupView: View {
    let id: String
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var group: FamilyGroup?
    @State private var error: String?
    @State private var loadError: String?
    @State private var sheet: FamilyPart?
    @State private var who = FamilyAPI.myName
    @State private var seq = 0                       // ردود التحديث الأقدم من آخر إجراء تُهمل
    @State private var busy = false
    @State private var confirmDelete = false
    @State private var confirmRound = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)

    var body: some View {
        ScrollView {
            if let g = group { content(g) }
            else if let e = loadError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.circle").font(.system(size: 34)).foregroundColor(Palette.goldDeep)
                    Text(e).font(AppFont.ui(15, 700)).foregroundColor(Palette.ink).multilineTextAlignment(.center)
                    Button { Task { await refresh() } } label: { Pill(title: L("إعادة المحاولة"), systemImage: "arrow.clockwise", primary: true) }
                        .frame(maxWidth: 240)
                }
                .padding(40)
            } else {
                ProgressView().tint(Palette.goldDeep).padding(60)
            }
        }
        .background(Palette.page.ignoresSafeArea())
        .navigationTitle(group?.name ?? L("ختمة العائلة"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refresh()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                if Task.isCancelled { break }
                // في الخلفية (والتلاوة تعمل مثلًا) لا نتصل بالخادم
                if UIApplication.shared.applicationState != .active { continue }
                await refresh(quiet: true)
            }
        }
        .refreshable { await refresh() }
        .sheet(item: $sheet) { p in partSheet(p).environment(\.layoutDirection, Lang.dir) }
        .alert(L("ختمة العائلة"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button(L("حسنًا"), role: .cancel) { }
        } message: { Text(error ?? "") }
        .alert(L("حذف الختمة؟"), isPresented: $confirmDelete) {
            Button(L("حذف"), role: .destructive) { Task { await remove() } }
            Button(L("إلغاء"), role: .cancel) { }
        } message: { Text(L("ستُحذف الختمة عند جميع المشاركين ولا يمكن استعادتها.")) }
        .alert(L("ختمة جديدة بالرابط نفسه؟"), isPresented: $confirmRound) {
            Button(L("ابدأ")) { Task { await run { try await FamilyAPI.newRound(id) } } }
            Button(L("إلغاء"), role: .cancel) { }
        } message: { Text(L("تُفرَّغ الأجزاء الثلاثون ليبدأ الجميع ختمة جديدة.")) }
    }

    private func content(_ g: FamilyGroup) -> some View {
        let mine = g.parts.filter { $0.mine }
        let round: Int = g.round ?? 1
        let kicker: String = round > 1 ? L("ختمة جماعية · الختمة ") + ar(round) : L("ختمة جماعية")
        let deadline: String = g.deadlineText.map { L(" · نختم قبل ") + $0 } ?? ""
        let byLine: String = L("أنشأها ") + g.owner + deadline
        let invite: String = L("انضم إلى «") + g.name + L("» واحجز جزءًا نختم به القرآن معًا 🤍\n") + FamilyAPI.inviteURL(g.id).absoluteString
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(kicker).font(AppFont.ui(13, 700)).foregroundColor(Palette.gold)
                Text(g.name).font(AppFont.ui(21, 700)).foregroundColor(.white)
                Text(byLine).font(AppFont.ui(13)).foregroundColor(Palette.onDarkMuted)
                HStack {
                    Text(L("أُنجز ") + ar(g.doneCount) + L(" من ٣٠ جزءًا"))
                    Spacer()
                    Text(ar(g.members.count) + L(" مشارك"))
                }
                .font(AppFont.ui(13, 700)).foregroundColor(Palette.onDarkSoft).padding(.top, 6)
                ProgressView(value: Double(g.doneCount), total: 30).tint(Palette.gold)
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20).fill(Palette.dark))

            if g.doneCount == 30 {
                VStack(spacing: 8) {
                    Text(L("تمّت الختمة بفضل الله")).font(AppFont.ui(18, 700)).foregroundColor(Palette.ink)
                    Text(L("تقبّل الله منكم جميعًا")).font(AppFont.ui(14)).foregroundColor(Palette.muted)
                    if g.admin == true {
                        Button { confirmRound = true } label: { Pill(title: L("ابدأ ختمة جديدة"), systemImage: "arrow.clockwise", primary: true) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(18).frame(maxWidth: .infinity).card(Palette.ivory, border: Palette.ivoryBorder)
            }

            if !mine.isEmpty {
                Text(L("أجزائي")).font(AppFont.ui(15, 700)).foregroundColor(Palette.ink)
                VStack(spacing: 0) {
                    ForEach(Array(mine.enumerated()), id: \.element.n) { i, p in
                        if i > 0 { Rectangle().fill(Palette.divider).frame(height: 1) }
                        HStack(spacing: 10) {
                            Text(ar(p.n)).font(AppFont.ui(15, 700)).foregroundColor(Palette.goldKey)
                                .frame(width: 38, height: 38).background(Circle().fill(Palette.chip))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L("الجزء ") + ar(p.n)).font(AppFont.ui(15, 700)).foregroundColor(Palette.ink)
                                Text(p.done ? L("أتممته، تقبّل الله") : L("من صفحة ") + ar(Self.start(p.n))).font(AppFont.ui(12)).foregroundColor(Palette.muted)
                            }
                            Spacer()
                            if p.done {
                                Button(L("تراجع")) { Task { await run { try await FamilyAPI.act("undo", id, part: p.n) } } }
                                    .font(AppFont.ui(13, 700)).foregroundColor(Palette.goldDeep)
                            } else {
                                Button(L("اقرأ")) { state.openMushaf(page: Self.start(p.n)) }
                                    .font(AppFont.ui(13, 700)).foregroundColor(Palette.goldDeep).padding(.horizontal, 6)
                                Button(L("أتممته")) { Task { await run { try await FamilyAPI.act("done", id, part: p.n) } } }
                                    .font(AppFont.ui(13, 700)).foregroundColor(.white)
                                    .padding(.horizontal, 12).frame(minHeight: 34).background(Capsule().fill(Palette.primary))
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 10)
                    }
                }
                .padding(.horizontal, 14).card()
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L("الأجزاء")).font(AppFont.ui(15, 700)).foregroundColor(Palette.ink)
                    Spacer()
                    Text(L("متاح ") + ar(30 - g.takenCount)).font(AppFont.ui(12)).foregroundColor(Palette.muted)
                }
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(g.parts, id: \.n) { p in partCell(p) }
                }
                HStack(spacing: 12) {
                    legend(Palette.gold, L("مقروء"))
                    legend(Palette.chip, L("محجوز"))
                    legend(Palette.card, L("متاح"))
                    Spacer()
                }
                Text(L("اضغط على جزء متاح لتحجزه.")).font(AppFont.ui(12)).foregroundColor(Palette.muted)
            }
            .padding(16).card()

            if !g.members.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text(L("المشاركون (") + ar(g.members.count) + ")").font(AppFont.ui(15, 700)).foregroundColor(Palette.ink).padding(.vertical, 10)
                    ForEach(g.members, id: \.name) { m in
                        HStack {
                            Text(String(m.name.first ?? "؟")).font(AppFont.ui(15, 700)).foregroundColor(Palette.gold)
                                .frame(width: 36, height: 36).background(Circle().fill(Palette.dark))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.name).font(AppFont.ui(14, 700)).foregroundColor(Palette.ink)
                                Text(L("الأجزاء ") + m.parts.map { ar($0) }.joined(separator: L("، "))).font(AppFont.ui(12)).foregroundColor(Palette.muted)
                            }
                            Spacer()
                            Text(ar(m.done) + "/" + ar(m.parts.count)).font(AppFont.ui(13, 700)).foregroundColor(Palette.goldDeep)
                        }
                        .padding(.vertical, 6)
                    }
                }
                .padding(.horizontal, 14).padding(.bottom, 8).card()
            }

            Button { Share.present([invite]) } label: {
                Pill(title: L("ادعُ أهلك برابط"), systemImage: "square.and.arrow.up", primary: true, height: 50)
            }
            .buttonStyle(.plain)
            if g.admin == true {
                HStack(spacing: 8) {
                    if g.doneCount < 30 {
                        Button { confirmRound = true } label: { Pill(title: L("ختمة جديدة"), systemImage: "arrow.clockwise", height: 44) }
                    }
                    Button { confirmDelete = true } label: { Pill(title: L("حذف الختمة"), systemImage: "trash", height: 44) }
                }
                .buttonStyle(.plain)
            } else {
                Button { FamilyAPI.forget(id); dismiss() } label: {
                    Text(L("إزالة من ختماتي")).font(AppFont.ui(13, 700)).foregroundColor(Palette.muted).frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
    }

    private func partCell(_ p: FamilyPart) -> some View {
        let fill: Color = p.done ? Palette.gold : (p.by != nil ? Palette.chip : Palette.card)
        let ink: Color = p.done ? Palette.dark : Palette.ink
        let border: Color = p.mine ? Palette.goldDeep : Palette.line
        let width: CGFloat = p.mine ? 2 : 1
        let status: String = p.done ? L("مقروء") : (p.by != nil ? L("محجوز لـ") + (p.by ?? "") : L("متاح"))
        let label: String = L("الجزء ") + ar(p.n) + L("، ") + status
        return Button { tapPart(p) } label: {
            Text(ar(p.n)).font(AppFont.ui(15, 700))
                .foregroundColor(ink)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(RoundedRectangle(cornerRadius: 10).fill(fill))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(border, lineWidth: width))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3).fill(c).frame(width: 12, height: 12)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Palette.line, lineWidth: 1))
            Text(t).font(AppFont.ui(11)).foregroundColor(Palette.muted)
        }
    }

    static func start(_ juz: Int) -> Int { Quran.juzStart[max(0, min(29, juz - 1))] }

    private func tapPart(_ p: FamilyPart) {
        if p.mine || p.by == nil { sheet = p }
        else { error = L("الجزء ") + ar(p.n) + (p.done ? L(" قرأه ") : L(" محجوز لـ")) + (p.by ?? "") }
    }

    private func partSheet(_ p: FamilyPart) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                if p.mine {
                    Text(L("الجزء ") + ar(p.n) + L(" محجوز باسمك")).font(AppFont.ui(17, 700)).foregroundColor(Palette.ink)
                    Button { sheet = nil; state.openMushaf(page: Self.start(p.n)) } label: { Pill(title: L("اقرأ الجزء"), systemImage: "book", primary: true) }
                    Button { sheet = nil; Task { await run { try await FamilyAPI.act("release", id, part: p.n) } } } label: {
                        Pill(title: L("ألغِ الحجز"), systemImage: "xmark")
                    }
                } else {
                    Text(L("احجز الجزء ") + ar(p.n)).font(AppFont.ui(18, 700)).foregroundColor(Palette.ink)
                    Text(L("يبدأ من صفحة ") + ar(Self.start(p.n)) + L(". اكتب اسمك ليعرف أهلك من يقرؤه.")).font(AppFont.ui(14)).foregroundColor(Palette.muted)
                    TextField(L("اسمك"), text: $who)
                        .font(AppFont.ui(16)).padding(.horizontal, 12).frame(minHeight: 46)
                        .card(Palette.page, border: Palette.fieldBorder, radius: 12)
                    Button {
                        let w = who.trimmingCharacters(in: .whitespaces)
                        FamilyAPI.myName = w
                        sheet = nil
                        Task { await run { try await FamilyAPI.act("take", id, part: p.n, who: w) } }
                    } label: { Pill(title: L("احجزه"), systemImage: "checkmark", primary: true) }
                    .disabled(who.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Spacer()
            }
            .buttonStyle(.plain)
            .padding(20)
            .background(Palette.page.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("إلغاء")) { sheet = nil }.font(AppFont.ui(15)) } }
        }
        .presentationDetents([.medium])
    }

    private func refresh(quiet: Bool = false) async {
        seq += 1
        let mine = seq
        do {
            let g = try await FamilyAPI.get(id)
            guard mine == seq else { return }
            group = g
            loadError = nil
            FamilyAPI.remember(g)
        } catch {
            if !quiet && group == nil { loadError = error.localizedDescription }
        }
    }

    private func run(_ f: @escaping () async throws -> FamilyGroup) async {
        if busy { return }
        busy = true
        defer { busy = false }
        do {
            var g = try await f()
            // ردود الحجز والإتمام لا تحمل صلاحية المنشئ: نعيدها من مفتاحه المحفوظ
            if FamilyAPI.adminKey(id) != nil { g.admin = true }
            seq += 1                                 // أي تحديث أُرسل قبل هذا الرد صار قديمًا
            group = g
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch {
            self.error = error.localizedDescription
            await refresh(quiet: true)
        }
    }

    private func remove() async {
        do {
            try await FamilyAPI.delete(id)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

extension FamilyPart: Identifiable { var id: Int { n } }

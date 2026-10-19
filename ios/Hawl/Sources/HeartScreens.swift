import SwiftUI

// MARK: - آية لحالك

/** «آية لحالك»: تختار شعورك فتأتيك آية تواسيك، وتشاركها كصورة (نفس MoodActivity) */
struct MoodView: View {
    var initial: Int?

    /** (الشعور، عنوان البطاقة، مراجع الآيات، الأيقونة) */
    static let moods: [(String, String, String, String)] = [
        ("قلق", "حين يقلقك أمر", "13:28,65:3,9:51,2:286,3:173,20:46", "cloud"),
        ("حزين", "حين يثقل الحزن قلبك", "9:40,93:3,12:86,94:6,2:155,3:139", "drop"),
        ("ضيق", "حين يضيق صدرك", "94:1,65:2,15:97,21:88,2:214,94:5", "wind"),
        ("خائف", "حين يغلبك الخوف", "20:46,3:175,9:51,41:30,28:31,10:62", "shield"),
        ("مذنب", "حين تثقلك ذنوبك", "39:53,4:110,3:135,25:70,11:114,66:8", "arrow.uturn.backward"),
        ("متعب", "حين يتعبك الطريق", "94:5,2:286,65:7,29:69,2:45,2:153", "battery.25"),
        ("وحيد", "حين تشعر بالوحدة", "2:186,50:16,58:7,57:4,20:46,2:152", "person"),
        ("غاضب", "حين يشتد غضبك", "3:134,41:34,7:199,42:37,42:43,3:159", "flame"),
        ("ممتن", "حين يغمرك الامتنان", "14:7,10:58,2:152,16:18,93:11,55:13", "sparkles"),
    ]

    struct Pick: Equatable { let s: Int, a: Int, text: String }

    @State private var mood: Int?
    @State private var pick: Pick?
    @State private var lastRef = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("كيف تشعر الآن؟").font(AppFont.ui(20, 700)).foregroundColor(Palette.ink).padding(.horizontal, 4).padding(.top, 8)
                Text("اختر شعورك، وتأتيك آية من كتاب الله تواسيك").font(AppFont.ui(14)).foregroundColor(Palette.muted)
                    .padding(.horizontal, 4).padding(.bottom, 12)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(0..<Self.moods.count, id: \.self) { i in
                        Button { choose(i) } label: {
                            VStack(spacing: 8) {
                                Image(systemName: Self.moods[i].3).font(.system(size: 24)).foregroundColor(Palette.goldDeep)
                                Text(Self.moods[i].0).font(AppFont.ui(14, 700)).foregroundColor(Palette.ink)
                            }
                            .frame(maxWidth: .infinity, minHeight: 80)
                            .background(RoundedRectangle(cornerRadius: 16).fill(mood == i ? Palette.ivory : Palette.card))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(mood == i ? Palette.goldDeep : Palette.line))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Self.moods[i].0)
                    }
                }
                if let p = pick, let m = mood { result(p, m).padding(.top, 18) }
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
        }
        .background(Palette.page.ignoresSafeArea())
        .navigationTitle("آية لحالك")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if mood == nil, let m = initial, Self.moods.indices.contains(m) { choose(m) } }
    }

    private func result(_ p: Pick, _ m: Int) -> some View {
        VStack(spacing: 12) {
            VStack(spacing: 10) {
                Text(Self.moods[m].1).font(AppFont.ui(14, 700)).foregroundColor(Palette.goldDeep)
                Text(Quran.withNumber(p.text, p.a)).font(AppFont.quran(25))
                    .foregroundColor(Palette.ink).multilineTextAlignment(.center).lineSpacing(9)
                    .textSelection(.enabled)
                Text("سورة " + Quran.surahName(p.s) + " · الآية " + ar(p.a)).font(AppFont.ui(13)).foregroundColor(Palette.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(18)
            .card(Palette.ivory, border: Palette.ivoryBorder, radius: 22)
            HStack(spacing: 8) {
                Button { shareImage(p, m) } label: { Pill(title: "شارك كصورة", systemImage: "photo", primary: true) }
                Button { choose(m) } label: { Pill(title: "آية أخرى", systemImage: "arrow.clockwise") }
            }
            NavigationLink(value: Screen.web(Links.ayah(p.s, p.a), "التفسير")) {
                Text("اقرأ التفسير ←").font(AppFont.ui(14, 700)).foregroundColor(Palette.goldDeep)
            }
            .padding(.top, 2)
        }
    }

    private func choose(_ i: Int) {
        mood = i
        let refs = Self.moods[i].2.split(separator: ",").map(String.init)
        var ref = refs.randomElement() ?? refs[0]
        var guardCount = 0
        while refs.count > 1 && ref == lastRef && guardCount < 20 { ref = refs.randomElement() ?? ref; guardCount += 1 }
        lastRef = ref
        let p = ref.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2, let t = Quran.verse(p[0], p[1]) else { pick = nil; return }
        pick = Pick(s: p[0], a: p[1], text: t)
    }

    @MainActor private func shareImage(_ p: Pick, _ m: Int) {
        let card = MoodCard(title: Self.moods[m].1, text: p.text, surah: p.s, ayah: p.a)
            .environment(\.layoutDirection, .rightToLeft)
        let r = ImageRenderer(content: card)
        r.scale = 3
        var msg: String = Self.moods[m].1 + " 🤍\n﴿ " + p.text + " ﴾ "
        msg += "[\(Quran.surahName(p.s)): \(ar(p.a))]\n\n"
        msg += "اختر شعورك واقرأ آية تواسيك في تطبيق «حول العالم | القرآن الكريم»:\n"
        msg += "https://7awlalaalam.com/quran/?utm_source=app_share&utm_medium=mood"
        if let img = r.uiImage { Share.present([img, msg]) } else { Share.present([msg]) }
    }
}

/** بطاقة «آية لحالك» للمشاركة (٣٦٠×٤٥٠ بمقياس ٣ = ١٠٨٠×١٣٥٠ كما في أندرويد) */
struct MoodCard: View {
    let title: String, text: String, surah: Int, ayah: Int

    var body: some View {
        VStack(spacing: 0) {
            Image(uiImage: UIImage(named: "app_logo_png") ?? UIImage()).resizable().frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 12)).padding(.top, 34)
            Text(title).font(AppFont.ui(15, 700)).foregroundColor(Palette.gold).padding(.top, 14)
            Spacer(minLength: 8)
            Text(Quran.withNumber(text, ayah)).font(AppFont.quran(text.count > 160 ? 15 : (text.count > 90 ? 18 : 21)))
                .foregroundColor(.white).multilineTextAlignment(.center).lineSpacing(8).padding(.horizontal, 24)
            Text("سورة " + Quran.surahName(surah) + " · الآية " + ar(ayah)).font(AppFont.ui(12, 500))
                .foregroundColor(Color(hex: 0xE9DFC9)).padding(.top, 10)
            Spacer(minLength: 8)
            Rectangle().fill(Palette.gold.opacity(0.33)).frame(width: 60, height: 1)
            Text("آية لحالك · تطبيق «حول العالم | القرآن الكريم»").font(AppFont.ui(11, 500)).foregroundColor(.white).padding(.top, 10)
            Text("7awlalaalam.com/quran").font(AppFont.ui(13, 700)).foregroundColor(Palette.gold).padding(.top, 6).padding(.bottom, 34)
        }
        .frame(width: 360, height: 450)
        .background(LinearGradient(colors: [Color(hex: 0x16424A), Color(hex: 0x071A1E)], startPoint: .top, endPoint: .bottom))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.gold, lineWidth: 1.3).padding(13))
    }
}

// MARK: - اجعلها صدقة جارية

/** «اجعلها صدقة جارية»: بطاقة مشاركة التطبيق باسم من تحب (نفس DedicateActivity) */
struct DedicateView: View {
    private static let titles = ["رحمه الله", "رحمها الله", "حفظه الله", "حفظها الله"]
    private static let link = "7awlalaalam.com/quran"

    @State private var name = ""
    @State private var honor = 0

    private var feminine: Bool { honor == 1 || honor == 3 }
    private var shownName: String {
        let n = name.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "من تحب" : n
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("شارك التطبيق باسم من تحب، حيًّا أو ميتًا، ليصل القرآن إلى غيرك صدقةً عنه.")
                    .font(AppFont.ui(15)).foregroundColor(Palette.muted)
                TextField("الاسم، مثال: والدي محمد", text: $name)
                    .font(AppFont.ui(17, 500))
                    .padding(.horizontal, 16).frame(minHeight: 50)
                    .card(radius: 14)
                HStack(spacing: 6) {
                    ForEach(0..<Self.titles.count, id: \.self) { i in
                        Button { honor = i } label: {
                            Text(Self.titles[i]).font(AppFont.ui(13, 500))
                                .foregroundColor(i == honor ? .white : Palette.ink)
                                .frame(maxWidth: .infinity, minHeight: 38)
                                .background(Capsule().fill(i == honor ? Palette.primary : Palette.card))
                                .overlay(Capsule().stroke(i == honor ? Color.clear : Palette.fieldBorder))
                        }
                        .buttonStyle(.plain)
                    }
                }
                card
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("معاينة البطاقة")
                Button { share() } label: { Pill(title: "شارك البطاقة", systemImage: "square.and.arrow.up", primary: true, height: 56) }
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
        .background(Palette.page.ignoresSafeArea())
        .navigationTitle("اجعلها صدقة جارية")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var card: some View {
        DedicateCard(name: shownName, honor: Self.titles[honor], feminine: feminine, link: Self.link)
            .environment(\.layoutDirection, .rightToLeft)
    }

    @MainActor private func share() {
        let r = ImageRenderer(content: card)
        r.scale = 3
        let n = name.trimmingCharacters(in: .whitespaces)
        let who: String = n.isEmpty ? "من أحب" : n
        var msg: String = "صدقة جارية عن " + who + " " + Self.titles[honor]
        msg += "\nحمّل تطبيق «حول العالم | القرآن الكريم» واقرأ وادعُ " + (feminine ? "لها" : "له") + " 🤍\n"
        msg += "https://" + Self.link + "/"
        if let img = r.uiImage { Share.present([img, msg]) } else { Share.present([msg]) }
    }
}

/** بطاقة الصدقة الجارية (٣٦٠×٤٥٠ بمقياس ٣ = ١٠٨٠×١٣٥٠ كما في أندرويد) */
struct DedicateCard: View {
    let name: String, honor: String, feminine: Bool, link: String

    var body: some View {
        VStack(spacing: 0) {
            Image(uiImage: UIImage(named: "app_logo_png") ?? UIImage()).resizable().frame(width: 74, height: 74)
                .clipShape(RoundedRectangle(cornerRadius: 16)).padding(.top, 40)
            Text("صدقة جارية عن").font(AppFont.ui(15, 500)).foregroundColor(Palette.gold).padding(.top, 26)
            Text(name).font(AppFont.ui(30, 700)).foregroundColor(.white).multilineTextAlignment(.center)
                .lineLimit(2).minimumScaleFactor(0.5).padding(.horizontal, 24).padding(.top, 6)
            Text(honor).font(AppFont.ui(17, 500)).foregroundColor(Color(hex: 0xE9DFC9)).padding(.top, 2)
            Rectangle().fill(Palette.gold.opacity(0.33)).frame(width: 60, height: 1).padding(.top, 20)
            Text("حمّل تطبيق «حول العالم | القرآن الكريم»\nواقرأ وادعُ " + (feminine ? "لها" : "له"))
                .font(AppFont.ui(15, 500)).foregroundColor(.white).multilineTextAlignment(.center).lineSpacing(3).padding(.top, 16)
            Text("مجاني · بلا تسجيل · بلا إعلانات").font(AppFont.ui(12)).foregroundColor(Palette.onDarkMuted).padding(.top, 20)
            Spacer(minLength: 0)
            Text(link).font(AppFont.ui(15, 700)).foregroundColor(Palette.gold).padding(.bottom, 44)
        }
        .frame(width: 360, height: 450)
        .background(LinearGradient(colors: [Color(hex: 0x16424A), Color(hex: 0x071A1E)], startPoint: .top, endPoint: .bottom))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.gold, lineWidth: 1.3).padding(13))
    }
}

// MARK: - التلاوات المحمّلة

/** التلاوات المحمّلة للاستماع دون إنترنت (نفس DownloadsActivity) */
struct DownloadsView: View {
    @ObservedObject private var dl = AudioDownloads.shared
    @ObservedObject private var player = AudioPlayer.shared
    @EnvironmentObject var state: AppState
    @State private var deleting: AudioDownloads.Item?

    var body: some View {
        let done = dl.items.filter { $0.status == .done }.count
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("استمع في أي مكان", systemImage: "airplane").font(AppFont.ui(17, 700)).foregroundColor(.white)
                    Text(done == 0 ? "لا توجد تلاوات محمّلة بعد" : ar(done) + " تلاوة محمّلة · " + AudioDownloads.mb(dl.totalBytes))
                        .font(AppFont.ui(14)).foregroundColor(Palette.onDarkMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18).padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 20).fill(Palette.dark))

                if dl.items.isEmpty {
                    Text("افتح صفحة أي قارئ، واختر السورة، ثم اضغط «⬇ تحميل للاستماع بدون إنترنت» تحت المشغّل.")
                        .font(AppFont.ui(15)).foregroundColor(Palette.ink)
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .card(Palette.ivory, border: Palette.ivoryBorder, radius: 16)
                    Button { state.tab = .listen; state.listenRequest = Links.reciters } label: {
                        Pill(title: "تصفّح القرّاء", primary: true, height: 50)
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(dl.items.enumerated()), id: \.element.id) { i, it in
                            if i > 0 { Rectangle().fill(Palette.divider).frame(height: 1) }
                            row(it)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 4)
                    .card()
                    Text("يستمر الاستماع مع قفل الشاشة، وتتحكم به من شاشة القفل. والتلاوات المحمّلة تُشغَّل من جهازك حتى مع الإنترنت، توفيرًا لباقتك.")
                        .font(AppFont.ui(13)).foregroundColor(Palette.muted).padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
        }
        .background(Palette.page.ignoresSafeArea())
        .navigationTitle("التلاوات المحمّلة")
        .navigationBarTitleDisplayMode(.inline)
        .alert("حذف التلاوة؟", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("حذف", role: .destructive) {
                if let it = deleting {
                    if player.current?.url == it.url { player.stop() }
                    dl.delete(it.url)
                }
                deleting = nil
            }
            Button("إلغاء", role: .cancel) { deleting = nil }
        } message: { Text((deleting?.title ?? "") + " · " + (deleting?.reciter ?? "")) }
    }

    private func row(_ it: AudioDownloads.Item) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "headphones").foregroundColor(Palette.goldDeep)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(Palette.chip))
            VStack(alignment: .leading, spacing: 4) {
                Text(it.title).font(AppFont.ui(16, 700)).foregroundColor(Palette.ink)
                Text(it.reciter + (it.size > 0 ? " · " + AudioDownloads.mb(it.size) : "")).font(AppFont.ui(12)).foregroundColor(Palette.muted)
                if it.status == .running {
                    ProgressView(value: Double(it.percent), total: 100).tint(Palette.goldDeep)
                }
            }
            Spacer(minLength: 4)
            switch it.status {
            case .done:
                NavigationLink(value: Screen.player(it.url)) {
                    Text(player.current?.url == it.url && player.playing ? "◼︎ يعمل" : "▶ تشغيل").font(AppFont.ui(13, 700)).foregroundColor(.white)
                        .padding(.horizontal, 14).frame(minHeight: 36)
                        .background(Capsule().fill(Palette.primary))
                }
            case .running:
                Text(ar(it.percent) + "٪").font(AppFont.ui(13, 700)).foregroundColor(Palette.goldDeep)
            default:
                Button("إعادة") { dl.retry(it) }.font(AppFont.ui(13, 700)).foregroundColor(Palette.goldDeep)
            }
            Button { deleting = it } label: {
                Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundColor(Palette.muted)
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel("حذف " + it.title)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 12)
    }
}

/** مشغّل التلاوة المحمّلة بهوية الموقع؛ الصوت من الجهاز (مثل OfflineAudio.player) */
struct PlayerView: View {
    let url: String
    @ObservedObject private var dl = AudioDownloads.shared
    @ObservedObject private var player = AudioPlayer.shared

    var body: some View {
        let it = dl.item(url)
        let ok = dl.ready(url) != nil
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Text("✈️ متاحة بدون إنترنت").font(AppFont.ui(13, 700)).foregroundColor(Palette.gold)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.1)))
                Text(it?.title ?? "تلاوة").font(AppFont.ui(28, 700)).foregroundColor(.white).padding(.top, 16).padding(.bottom, 6)
                    .multilineTextAlignment(.center)
                Text(it?.reciter ?? "").font(AppFont.ui(15)).foregroundColor(Palette.onDarkMuted)
                if ok {
                    Slider(value: Binding(get: { player.position }, set: { player.seek($0) }),
                           in: 0...max(1, player.duration))
                        .tint(Palette.gold)
                        .padding(.top, 22)
                    HStack {
                        Text(Self.clock(player.position)).font(AppFont.ui(12)).foregroundColor(Palette.onDarkMuted)
                        Spacer()
                        Text(Self.clock(player.duration)).font(AppFont.ui(12)).foregroundColor(Palette.onDarkMuted)
                    }
                    HStack(spacing: 34) {
                        Button { player.skip(15) } label: { Image(systemName: "goforward.15").font(.system(size: 26)) }
                        Button {
                            if player.current?.url == url { player.toggle() } else if let i = it { player.play(i) }
                        } label: {
                            Image(systemName: player.current?.url == url && player.playing ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 60))
                        }
                        Button { player.skip(-15) } label: { Image(systemName: "gobackward.15").font(.system(size: 26)) }
                    }
                    .foregroundColor(Palette.gold)
                    .padding(.top, 12)
                    Text("يستمر الاستماع مع قفل الشاشة، وتتحكم به من شاشة القفل").font(AppFont.ui(13)).foregroundColor(Palette.onDarkSoft)
                        .multilineTextAlignment(.center).padding(.top, 16)
                } else {
                    Text("هذه التلاوة لم تعد محمّلة على جهازك").font(AppFont.ui(13)).foregroundColor(Palette.onDarkSoft).padding(.top, 16)
                }
            }
            .padding(.horizontal, 22).padding(.vertical, 28)
            .frame(maxWidth: 440)
            .background(RoundedRectangle(cornerRadius: 24).fill(Palette.widgetDark))
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.page.ignoresSafeArea())
        .navigationTitle(it?.title ?? "تلاوة")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if ok, let i = it, player.current?.url != url { player.play(i) } }
    }

    static func clock(_ s: Double) -> String {
        let t = Int(s.isFinite ? s : 0)
        return ar(t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60))
    }
}

// MARK: - الترحيب عند أول تشغيل

/** الترحيب: اختيار التذكيرات (نفس WelcomeActivity) */
struct WelcomeView: View {
    @EnvironmentObject var state: AppState
    @State private var verse = true
    @State private var adhan = true
    @State private var wird = true

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Image(uiImage: UIImage(named: "app_logo_png") ?? UIImage()).resizable().frame(width: 112, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 6)
                    .padding(.top, 40)
                Text("أهلًا بك في حول العالم").font(AppFont.ui(26, 700)).foregroundColor(Palette.ink).padding(.top, 22).padding(.bottom, 8)
                Text("رفيقك اليومي مع كتاب الله: تقرأ، وتستمع، وتتدبّر، ولا يفوتك وِردك.")
                    .font(AppFont.ui(15)).foregroundColor(Palette.muted).multilineTextAlignment(.center)
                Text("اختر ما يناسبك").font(AppFont.ui(14, 700)).foregroundColor(Palette.goldDeep)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 28).padding(.bottom, 10)
                VStack(spacing: 0) {
                    toggle("آية اليوم كل صباح", "مع تفسيرها، الساعة ٧:٠٠ ص", $verse)
                    Rectangle().fill(Palette.divider).frame(height: 1)
                    toggle("تنبيه الأذان في مدينتي", "يحتاج إذن الموقع · بطريقة الحساب المعتمدة في دولتك", $adhan)
                    Rectangle().fill(Palette.divider).frame(height: 1)
                    toggle("تذكير بالورد مساءً", "الساعة ٩:٠٠ م", $wird)
                }
                .padding(.horizontal, 16)
                .card()
                Button { start() } label: { Pill(title: "ابدأ رحلتك مع القرآن", primary: true, height: 56) }.padding(.top, 28)
                Text("يمكنك تغيير ذلك لاحقًا من الإعدادات").font(AppFont.ui(12)).foregroundColor(Palette.muted).padding(.top, 12)
                Button("ليس الآن") { finish() }.font(AppFont.ui(14, 500)).foregroundColor(Palette.muted).padding(.top, 8)
            }
            .padding(.horizontal, 24).padding(.bottom, 32)
        }
        .background(Palette.page.ignoresSafeArea())
    }

    private func toggle(_ t: String, _ s: String, _ b: Binding<Bool>) -> some View {
        Toggle(isOn: b) {
            VStack(alignment: .leading, spacing: 4) {
                Text(t).font(AppFont.ui(16, 700)).foregroundColor(Palette.ink)
                Text(s).font(AppFont.ui(13)).foregroundColor(Palette.muted)
            }
        }
        .tint(Palette.goldDeep)
        .padding(.vertical, 12)
    }

    private func start() {
        Task {
            let wants = verse || adhan || wird
            let ok = wants ? await Notifications.requestPermission() : false
            Store.d.set(ok && verse, forKey: "verse_on")
            Store.d.set(ok && wird, forKey: "wird_on")
            if ok && adhan {
                Store.d.set(true, forKey: "adhan_on")
                LocationService.shared.requestLocation()
            }
            finish()
        }
    }

    private func finish() {
        Store.d.set(true, forKey: "welcomed")
        Store.d.set(FeaturesView.tourVersion, forKey: "tour_v")      // الجولة لمن حدّث التطبيق، لا لمن ثبّته الآن
        state.showWelcome = false
        state.changed()
    }
}

// MARK: - جولة في المميزات

/** جولة في مميزات التطبيق: تظهر مرة بعد كل تحديث يضيف مميزات، وتُفتح من الإعدادات (نفس FeaturesActivity) */
struct FeaturesView: View {
    /** ارفع الرقم عند إضافة مميزات جديدة إلى الجولة، فتظهر مرة أخرى للجميع بعد التحديث */
    static let tourVersion = 5

    @Environment(\.dismiss) private var dismiss
    @State private var index = 0

    /** (عنوان، شرح، أيقونة، شارة ٠ بلا، ١ جديد، ٢ مطوّر) */
    private static let slides: [(String, String, String, Int)] = [
        ("أهلًا بك في الإصدار ٢٫٠",
         "تحديث كبير لـ«القرآن حول العالم»: حفظ ومراجعة، وتسميع بصوتك، وختمة مع عائلتك، وبحث بالمعنى، والصلاة القادمة على شاشة القفل.\nاسحب أو اضغط «التالي».",
         "book", 0),
        ("الصلاة القادمة على شاشة القفل",
         "عدّاد هادئ حتى دخول الوقت في الجزيرة الديناميكية وشاشة القفل، ويتحول وحده للصلاة التالية.\n\nفعّله من «الأدوات» ← «التنبيهات» ← «الصلاة القادمة على شاشة القفل».",
         "clock", 1),
        ("«اليوم» أوضح",
         "• مواقيت اليوم الخمس تحت الصلاة القادمة، والقادمة بالذهبي.\n• عدد أيامك المتتالية مع القرآن.\n• «صورة» في آية اليوم تُشارك البطاقة مباشرة.\n• بطاقة «مراجعة الحفظ» يوم تحين مراجعتك.",
         "square.grid.2x2", 1),
        ("المصحف مع التفسير",
         "وضع جديد من زر «Aa» في المصحف: كل آية وتحتها تفسيرها الميسر، دون إنترنت.\n\nوفي المشغّل زر لتكرار كل آية ٣ أو ٥ أو ١٠ مرات، يعينك على الحفظ.",
         "text.book.closed", 1),
        ("احفظ وراجع",
         "اضغط على آية ثم «أضفها لحفظي»: الآية، أو إلى آخر الصفحة، أو إلى آخر السورة.\n\nنعرضها عليك في أوقات متباعدة: تظهر أول كلمتين والباقي مخفي، ثم تختار «نسيتها» أو «بتردد» أو «متقنة»، فتعود غدًا أو بعد أيام أو بعد أسبوع وأكثر.",
         "puzzlepiece", 1),
        ("سمّع بصوتك (تجريبي)",
         "اقرأ من حفظك فتظهر الكلمات كلما قرأتها، والكلمة التي تتجاوزها تظهر بالبرتقالي.\n\nمن «سمّع من هنا» في لوحة الآية، أو 🎙️ في مراجعة الحفظ. التعرّف من جوالك نفسه، ولا يُحفظ صوتك.",
         "mic", 1),
        ("ابحث بالمعنى",
         "اكتب ما تبحث عنه بكلماتك، مثل «بر الوالدين» أو «الصبر على المرض»، فتظهر الآيات التي معناها ما تقصد ولو لم تحمل لفظك، من التفسير الميسر.\n\nمن 🔍 في المصحف، أو «بحث بالمعنى» في «الأدوات».",
         "text.magnifyingglass", 1),
        ("ختمة العائلة",
         "أنشئ ختمة وأرسل رابطها لأهلك؛ كل فرد يحجز جزءًا ويعلّم عليه حين يُتمّه، وتتابعون التقدّم معًا حتى الختم، ويمكن إهداؤها.\n\nمن «الأدوات» ← «ختمة العائلة».",
         "person.3", 1),
        ("رحلتي",
         "سلسلتك الحالية وأطولها، وأيام قراءتك في آخر ٣٠ يومًا، وختماتك، وحفظك.\n\nاضغط بطاقة الأيام المتتالية في «الأدوات».",
         "chart.bar", 1),
        ("اسأل Siri",
         "قل لـ Siri: «الصلاة القادمة في حول العالم» فيجيبك بالوقت، أو «افتح المصحف في حول العالم»، أو «راجع حفظي»، أو «ورد اليوم».\n\nوتجدها في تطبيق «الاختصارات».",
         "mic.circle", 1),
        ("ختمتي وتذكير الورد",
         "خطتك على مقاسك: المدة أو الورد اليومي وأيام الراحة، ويُوزَّع الباقي إن فاتك يوم، وتذكير يصلك في وقته ولا يصلك إن أتممت وردك.",
         "book.closed", 0),
        ("اجعلها صدقة جارية",
         "شارك التطبيق باسم من تحب، حيًّا أو ميتًا، ليصل القرآن إلى غيرك صدقةً عنه.\n\nوأضف إلى شاشة جوالك ويدجت: آية اليوم، ومواقيت الصلاة، وختمتي، ورمضان.",
         "heart", 0),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("تخطٍّ") { close() }.font(AppFont.ui(15, 500)).foregroundColor(Palette.muted).padding(8)
                Spacer()
            }
            TabView(selection: $index) {
                ForEach(0..<Self.slides.count, id: \.self) { i in
                    slide(Self.slides[i]).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            HStack(spacing: 6) {
                ForEach(0..<Self.slides.count, id: \.self) { k in
                    Capsule().fill(k == index ? Palette.goldDeep : Palette.line).frame(width: k == index ? 22 : 8, height: 8)
                }
            }
            .padding(.vertical, 14)
            HStack(spacing: 10) {
                Button { withAnimation { index = max(0, index - 1) } } label: { Pill(title: "السابق", height: 52) }
                    .opacity(index == 0 ? 0 : 1)
                Button {
                    if index == Self.slides.count - 1 { close() } else { withAnimation { index += 1 } }
                } label: { Pill(title: index == Self.slides.count - 1 ? "ابدأ" : "التالي", primary: true, height: 52) }
                    .layoutPriority(1.4)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .background(Palette.page.ignoresSafeArea())
        .onAppear { Store.d.set(Self.tourVersion, forKey: "tour_v") }
    }

    private func slide(_ s: (String, String, String, Int)) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                Image(systemName: s.2).font(.system(size: 34)).foregroundColor(Palette.gold)
                    .frame(width: 76, height: 76)
                    .background(RoundedRectangle(cornerRadius: 36).fill(Palette.dark))
                    .padding(.top, 28)
                if s.3 != 0 {
                    Text(s.3 == 1 ? "جديد" : "مطوّر").font(AppFont.ui(13, 700)).foregroundColor(Palette.widgetDark)
                        .padding(.horizontal, 14).padding(.vertical, 4)
                        .background(Capsule().fill(Palette.gold))
                        .padding(.top, 16)
                }
                Text(s.0).font(AppFont.ui(24, 700)).foregroundColor(Palette.ink).multilineTextAlignment(.center).padding(.top, 16)
                Text(s.1).font(AppFont.ui(16)).foregroundColor(Palette.ink).lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18).padding(.vertical, 16)
                    .card(radius: 18)
                    .padding(.top, 18)
            }
        }
    }

    private func close() {
        AppState.shared.showTour = false
        dismiss()
    }
}

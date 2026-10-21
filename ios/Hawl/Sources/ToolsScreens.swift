import SwiftUI
import CoreLocation

// MARK: - الأدوات

/** شاشة «الأدوات»: سلسلة الأيام، أدوات القرآن، الصلاة والذكر، لقلبك، والصدقة الجارية (نفس ToolsActivity) */
struct ToolsView: View {
    @EnvironmentObject var state: AppState

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                NavigationLink(value: Screen.journey) { streakCard }
                    .accessibilityHint("افتح «رحلتي»")
                section("القرآن")
                LazyVGrid(columns: columns, spacing: 8) {
                    NavigationLink(value: Screen.index) { ToolTile(title: "الفهرس", systemImage: "list.bullet") }
                    NavigationLink(value: Screen.khatma) { ToolTile(title: "ختمتي", systemImage: "book.closed") }
                    NavigationLink(value: Screen.downloads) { ToolTile(title: "المحمّلة", systemImage: "headphones") }
                    Button { Browser.open(Links.languages) } label: { ToolTile(title: "الترجمات", systemImage: "globe") }
                    Button { state.openMushaf(page: nil, extra: "hifz=1") } label: { ToolTile(title: "الحفظ", systemImage: "puzzlepiece") }
                    Button { state.openMushaf(page: nil, extra: "find=1") } label: { ToolTile(title: "بحث بالمعنى", systemImage: "text.magnifyingglass") }
                    NavigationLink(value: Screen.family(nil)) { ToolTile(title: "ختمة العائلة", systemImage: "person.3") }
                }
                section("الصلاة والذكر")
                LazyVGrid(columns: columns, spacing: 8) {
                    NavigationLink(value: Screen.prayerTimes) { ToolTile(title: "المواقيت", systemImage: "clock") }
                    NavigationLink(value: Screen.qibla) { ToolTile(title: "القبلة", systemImage: "location.north.circle") }
                    NavigationLink(value: Screen.azkar(nil)) { ToolTile(title: "الأذكار", systemImage: "sun.and.horizon") }
                    NavigationLink(value: Screen.tasbeeh) { ToolTile(title: "المسبحة", systemImage: "circle.grid.cross") }
                    NavigationLink(value: Screen.prayerAzkar) { ToolTile(title: "أذكار الصلاة", systemImage: "moon.stars") }
                    Button { Browser.open(Links.home) } label: { ToolTile(title: "الموقع", systemImage: "safari") }
                }
                section("لقلبك والتطبيق")
                LazyVGrid(columns: columns, spacing: 8) {
                    NavigationLink(value: Screen.mood(nil)) { ToolTile(title: "آية لحالك", systemImage: "heart") }
                    NavigationLink(value: Screen.dedicate) { ToolTile(title: "صدقة جارية", systemImage: "heart.circle") }
                    NavigationLink(value: Screen.notifications) { ToolTile(title: "التنبيهات", systemImage: "bell") }
                    NavigationLink(value: Screen.settings) { ToolTile(title: "الإعدادات", systemImage: "gearshape") }
                }
                dedicateCard.padding(.top, 12)
            }
            .buttonStyle(.plain)
            .padding(16)
        }
        .background(Palette.page.ignoresSafeArea())
        .navigationTitle("الأدوات")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(value: Screen.settings) { Image(systemName: "gearshape") }
                    .accessibilityLabel("الإعدادات")
            }
        }
    }

    private func section(_ t: String) -> some View {
        Text(t).font(AppFont.ui(14, 700)).foregroundColor(Palette.muted).padding(.top, 12).padding(.horizontal, 4)
    }

    private var streakCard: some View {
        _ = state.rev
        let n = Reading.streak
        let title = n == 0 ? "ابدأ سلسلتك اليوم مع القرآن"
            : n == 1 ? "يوم واحد مع القرآن" : n == 2 ? "يومان متتاليان مع القرآن"
            : ar(n) + (n <= 10 ? " أيام متتالية مع القرآن" : " يومًا متتاليًا مع القرآن")
        let cal = Calendar.current
        let days: [Date] = (0..<7).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: Date()) }
        let letters = ["ح", "ن", "ث", "ر", "خ", "ج", "س"]          // الأحد..السبت
        return VStack(alignment: .leading, spacing: 4) {
            Text(title).font(AppFont.ui(16, 700)).foregroundColor(Palette.ink)
            Text(Reading.readOn(Date()) ? "أحسنت، قرأت اليوم ✓" : "اقرأ ولو آية اليوم لتكملها")
                .font(AppFont.ui(12)).foregroundColor(Palette.muted).padding(.bottom, 8)
            HStack {
                ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                    let on = Reading.readOn(d)
                    VStack(spacing: 4) {
                        ZStack {
                            Circle().fill(on ? Palette.goldDeep : Palette.chip)
                            if i == 6 { Circle().stroke(Palette.goldDeep, lineWidth: 1.5) }
                            if on { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundColor(.white) }
                        }
                        .frame(width: 28, height: 28)
                        Text(letters[cal.component(.weekday, from: d) - 1]).font(AppFont.ui(11, i == 6 ? 700 : 400))
                            .foregroundColor(i == 6 ? Palette.goldDeep : Palette.muted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .card()
    }

    private var dedicateCard: some View {
        NavigationLink(value: Screen.dedicate) {
            HStack(spacing: 12) {
                Image(systemName: "heart.fill").foregroundColor(Palette.goldLight)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Palette.gold.opacity(0.18)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("اجعلها صدقة جارية").font(AppFont.ui(16, 700)).foregroundColor(.white)
                    Text("شارك التطبيق باسم من تحب، حيًّا أو ميتًا").font(AppFont.ui(12)).foregroundColor(Palette.onDarkMuted)
                }
                Spacer()
                Image(systemName: "chevron.left").foregroundColor(Palette.goldLight)
            }
            .padding(16)
            .background(PatternBackground().clipShape(RoundedRectangle(cornerRadius: 18)))
        }
        .accessibilityLabel("اجعلها صدقة جارية: شارك التطبيق باسم من تحب")
    }
}

// MARK: - مواقيت الصلاة

struct PrayerTimesView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var location = LocationService.shared
    @State private var now = Date()

    var body: some View {
        List {
            if state.hasLocation {
                let t = Prayer.times(for: now)
                let next = Prayer.next(now: now)
                Section {
                    ForEach(0..<6, id: \.self) { i in
                        let isNext = i == next.0 && Calendar.current.isDate(next.1, inSameDayAs: now)
                        HStack {
                            Text(Prayer.displayName(i, on: now)).font(AppFont.ui(16, isNext ? 700 : 500))
                            if isNext {
                                Text(Prayer.remaining(next.1.timeIntervalSince(now), after: true))
                                    .font(AppFont.ui(12, 700)).foregroundColor(Palette.goldDeep)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Capsule().fill(Palette.chip))
                            }
                            Spacer()
                            Text(formatTime(t[i])).font(AppFont.ui(16, isNext ? 700 : 400))
                        }
                        .foregroundColor(isNext ? Palette.goldDeep : Palette.ink)
                        .frame(minHeight: 40)
                    }
                } header: {
                    Text(hijriToday() + (state.city.isEmpty ? "" : " · " + state.city)).font(AppFont.ui(13))
                } footer: {
                    Text((Store.int("calc_method", 0) == 0 ? "تلقائي حسب دولتك · " : "")
                         + Prayer.currentMethod().name + "\n" + Prayer.currentMethod().detail).font(AppFont.ui(12))
                }
            } else {
                Text("حدّد موقعك لعرض مواقيت الصلاة في مدينتك").font(AppFont.ui(15)).foregroundColor(Palette.muted)
            }
            Section {
                Button { location.requestLocation() } label: {
                    HStack {
                        Label(state.hasLocation ? "تحديث الموقع" : "تحديد الموقع", systemImage: "location").font(AppFont.ui(15, 700))
                        Spacer()
                        if location.busy { ProgressView() }
                    }
                }
                if location.denied {
                    Button("السماح بالموقع من الإعدادات") {
                        if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                    }.font(AppFont.ui(14))
                }
                if location.failed {
                    Text("تعذّر تحديد الموقع، فعّل خدمة الموقع ثم حاول مرة أخرى").font(AppFont.ui(13)).foregroundColor(Palette.muted)
                }
                Toggle(isOn: state.toggle("adhan_on")) {
                    Text("تنبيه الأذان").font(AppFont.ui(15, 500))
                }
                .tint(Palette.goldDeep)
                .disabled(!state.hasLocation)
                NavigationLink(value: Screen.web(Links.prayerTimes, "مواقيت الصلاة")) {
                    Label("مواقيت الشهر في الموقع", systemImage: "calendar").font(AppFont.ui(15))
                }
            }
        }
        .navigationTitle("مواقيت الصلاة")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now = $0 }
    }
}

// MARK: - القبلة

struct QiblaView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var location = LocationService.shared
    @State private var aligned = false

    private static let kaaba = (lat: 21.422487, lng: 39.826206)

    private var bearing: Double? {
        guard state.hasLocation else { return nil }
        let lat = Geo.lat, lng = Geo.lng
        let p1 = lat * .pi / 180, p2 = Self.kaaba.lat * .pi / 180
        let dl = (Self.kaaba.lng - lng) * .pi / 180
        let y = sin(dl) * cos(p2)
        let x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
        let b = atan2(y, x) * 180 / .pi
        return (b + 360).truncatingRemainder(dividingBy: 360)
    }

    /** المسافة إلى مكة المكرمة بالكيلومتر */
    private var distanceKm: Double {
        let a = CLLocation(latitude: Geo.lat, longitude: Geo.lng)
        let b = CLLocation(latitude: Self.kaaba.lat, longitude: Self.kaaba.lng)
        return a.distance(from: b) / 1000
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let b = bearing {
                    Text(state.city.isEmpty ? "موقعك الحالي" : state.city)
                        .font(AppFont.ui(16, 700)).foregroundColor(Palette.ink)
                    dial(qibla: b)
                    hint(qibla: b)
                    HStack(spacing: 0) {
                        stat(icon: "safari", title: "اتجاه القبلة من الشمال", value: ar(Int(b.rounded())) + "°")
                        Rectangle().fill(Palette.line).frame(width: 1, height: 44)
                        stat(icon: "mappin.and.ellipse", title: "البُعد عن الكعبة", value: ar(Int(distanceKm.rounded())) + " كم")
                    }
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Palette.card))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.line))
                } else {
                    Text(location.denied ? "نحتاج إذن الموقع لتحديد اتجاه القبلة" : "حدّد موقعك لمعرفة اتجاه القبلة")
                        .font(AppFont.ui(16, 500)).foregroundColor(Palette.muted)
                    Button { location.requestLocation() } label: {
                        HStack { if location.busy { ProgressView() }; Pill(title: "تحديد الموقع", systemImage: "location", primary: true) }
                    }
                    .frame(width: 240)
                }
                Text("ضع الجوال مسطحًا بعيدًا عن المعادن والمغناطيس. إذا كانت القراءة غير مستقرة، حرّك الجوال في الهواء على شكل الرقم 8 لمعايرة البوصلة.")
                    .font(AppFont.ui(13)).foregroundColor(Palette.muted).multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.page.ignoresSafeArea())
        .navigationTitle("اتجاه القبلة")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            location.startHeading()
            if !state.hasLocation && location.authorized { location.requestLocation() }
        }
        .onDisappear { location.stopHeading() }
    }

    private func offset(_ qibla: Double) -> Double? {
        guard let h = location.heading else { return nil }
        return (qibla - h + 540).truncatingRemainder(dividingBy: 360) - 180
    }

    private func stat(icon: String, title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Label(title, systemImage: icon).font(AppFont.ui(12)).foregroundColor(Palette.muted)
            Text(value).font(AppFont.ui(22, 800)).foregroundColor(Palette.ink)
        }
        .frame(maxWidth: .infinity)
    }

    /** البوصلة: قرص بالدرجات يدور مع الجوال، والكعبة على حافته في اتجاه القبلة، وإبرة من المركز إليها.
        السهم الثابت أعلى القرص هو اتجاه الجوال: إذا وقعت الكعبة تحته فأنت باتجاه القبلة. */
    private func dial(qibla: Double) -> some View {
        let heading = location.heading == nil ? 0 : location.headingTurn   // متصل دون قفز عند الشمال
        let lowAccuracy = location.heading != nil && (location.headingAccuracy < 0 || location.headingAccuracy > 25)
        let isAligned = (offset(qibla).map { abs($0) <= 4 }) ?? false
        let R: CGFloat = 150
        return ZStack {
            Circle().fill(isAligned ? Palette.gold.opacity(0.9) : Palette.primary)
            Circle().fill(Palette.card).padding(9)
            ZStack {
                // التدريج: خط كل ٥°، وأطول كل ١٥° مع رقمه
                ForEach(0..<72, id: \.self) { i in
                    Rectangle().fill(i % 3 == 0 ? Palette.ink : Palette.line)
                        .frame(width: i % 3 == 0 ? 2 : 1, height: i % 3 == 0 ? 11 : 6)
                        .offset(y: -(R - 22))
                        .rotationEffect(.degrees(Double(i) * 5))
                }
                ForEach(Array(stride(from: 15, to: 360, by: 15)), id: \.self) { d in
                    if d % 90 != 0 {
                        Text(ar(d)).font(AppFont.ui(10, 500)).foregroundColor(Palette.muted)
                            .rotationEffect(.degrees(heading - Double(d)))
                            .offset(y: -(R - 40))
                            .rotationEffect(.degrees(Double(d)))
                    }
                }
                ForEach(Array(["ش", "ق", "ج", "غ"].enumerated()), id: \.offset) { i, l in
                    Text(l).font(AppFont.ui(18, 800)).foregroundColor(i == 0 ? Color(red: 0.7, green: 0.25, blue: 0.18) : Palette.ink)
                        .rotationEffect(.degrees(heading - Double(i) * 90))
                        .offset(y: -(R - 40))
                        .rotationEffect(.degrees(Double(i) * 90))
                }
                // قوس من الشمال إلى القبلة
                Circle().trim(from: 0, to: qibla / 360)
                    .stroke(Palette.gold.opacity(0.7), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(17)
                // الإبرة والكعبة على الحافة
                ZStack {
                    Capsule().fill(Palette.ink).frame(width: 6, height: R - 92).offset(y: -(R - 92) / 2)
                    KaabaMark().frame(width: 30, height: 30)
                        .rotationEffect(.degrees(heading - qibla))   // تبقى قائمة على الشاشة
                        .offset(y: -(R - 72))   // داخل حلقة الحروف حتى لا تغطيها
                }
                .rotationEffect(.degrees(qibla))
            }
            .rotationEffect(.degrees(-heading))
            // سهم ثابت = مقدمة الجوال
            Image(systemName: "arrowtriangle.down.fill").font(.system(size: 20))
                .foregroundColor(isAligned ? .white : Palette.goldDeep)
                .offset(y: -R + 4)
            Circle().fill(Palette.ink).frame(width: 18, height: 18)
            Circle().fill(Palette.card).frame(width: 7, height: 7)
            if lowAccuracy {
                Text("البوصلة تحتاج معايرة").font(AppFont.ui(12, 700)).foregroundColor(Palette.goldDeep).offset(y: 46)
            }
        }
        .frame(width: R * 2, height: R * 2)
        .animation(.easeOut(duration: 0.25), value: heading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("بوصلة القبلة")
        .onChange(of: isAligned) { now in
            if now && !aligned { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            aligned = now
        }
    }

    /** الإرشاد تحت البوصلة: أي اتجاه يحرّك المستخدم جواله */
    @ViewBuilder private func hint(qibla: Double) -> some View {
        let box: (String, String?, Color) -> AnyView = { text, icon, color in
            AnyView(HStack(spacing: 10) {
                if let icon { Image(systemName: icon).font(.system(size: 20, weight: .bold)) }
                Text(text).font(AppFont.ui(18, 700))
            }
            .foregroundColor(color)
            .frame(maxWidth: .infinity).frame(minHeight: 54)
            .background(RoundedRectangle(cornerRadius: 16).fill(Palette.card))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(color == Palette.goldDeep ? Palette.gold : Palette.line, lineWidth: 1.5)))
        }
        if !location.headingAvailable {
            box("جوالك لا يحتوي على بوصلة", nil, Palette.ink)
        } else if let off = offset(qibla) {
            if abs(off) <= 4 {
                box("أنت باتجاه القبلة", "checkmark.circle.fill", Palette.goldDeep)
            } else if off > 0 {
                box("حرّك الجوال نحو اليمين", "arrow.right", Palette.ink)
            } else {
                box("حرّك الجوال نحو اليسار", "arrow.left", Palette.ink)
            }
        } else {
            box("جارٍ قراءة البوصلة…", nil, Palette.muted)
        }
    }
}

/** رمز الكعبة: مكعب أسود بحزام ذهبي (رسم بسيط دون صور) */
struct KaabaMark: View {
    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: s * 0.12).fill(Color(white: 0.08))
                Rectangle().fill(Color(red: 0.85, green: 0.69, blue: 0.36)).frame(height: s * 0.13).padding(.top, s * 0.22)
            }
            .overlay(RoundedRectangle(cornerRadius: s * 0.12).stroke(Color.white.opacity(0.9), lineWidth: 1.5))
            .frame(width: s, height: s)
        }
    }
}

// MARK: - المسبحة

/** المسبحة الإلكترونية (نفس TasbeehActivity) */
struct TasbeehView: View {
    @AppStorage("tasbeeh_dhikr") private var dhikr = 0
    @AppStorage("tasbeeh_target") private var target = 33
    @AppStorage("tasbeeh_count") private var count = 0
    @AppStorage("tasbeeh_total") private var total = 0

    private static let dhikrs = [
        "سُبْحَانَ اللَّهِ", "الْحَمْدُ لِلَّهِ", "اللَّهُ أَكْبَرُ", "لَا إِلَهَ إِلَّا اللَّهُ",
        "أَسْتَغْفِرُ اللَّهَ", "سُبْحَانَ اللَّهِ وَبِحَمْدِهِ", "لَا حَوْلَ وَلَا قُوَّةَ إِلَّا بِاللَّهِ",
        "اللَّهُمَّ صَلِّ عَلَى مُحَمَّدٍ"]
    private static let targets = [33, 99, 100, 0]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0..<Self.dhikrs.count, id: \.self) { i in
                        Button { dhikr = i; count = 0 } label: {
                            Text(Self.dhikrs[i]).font(AppFont.ui(14, 500))
                                .foregroundColor(i == dhikr ? .white : Palette.ink)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(Capsule().fill(i == dhikr ? Palette.primary : Palette.card))
                                .overlay(Capsule().stroke(i == dhikr ? Color.clear : Palette.fieldBorder))
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 6)
            }
            Text(Self.dhikrs[min(dhikr, Self.dhikrs.count - 1)])
                .font(AppFont.amiri(30)).foregroundColor(Palette.ink)
                .multilineTextAlignment(.center)
                .padding(.top, 18).padding(.bottom, 6).padding(.horizontal, 20)

            GeometryReader { geo in
                let side = max(96, min(240, min(geo.size.width, geo.size.height) - 8))
                Button(action: tap) {
                    ZStack {
                        Circle().fill(Palette.dark)
                        Circle().stroke(Palette.gold, lineWidth: 2)
                        if target > 0 {
                            Ring(fraction: Double(count) / Double(target), track: .clear, tint: Palette.gold, width: 6)
                                .padding(6)
                        }
                        VStack(spacing: 4) {
                            Text(ar(count)).font(AppFont.ui(side * 0.25, 700)).foregroundColor(.white).monospacedDigit()
                            if side >= 140 {
                                Text(target > 0 ? "من " + ar(target) : "عدّ مفتوح").font(AppFont.ui(14, 500)).foregroundColor(Palette.gold)
                            }
                        }
                    }
                    .frame(width: side, height: side)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("اضغط للتسبيح، العدد " + ar(count))
            }

            HStack(spacing: 6) {
                ForEach(Self.targets, id: \.self) { t in
                    Button { target = t; count = 0 } label: {
                        Text(t == 0 ? "بلا حد" : ar(t)).font(AppFont.ui(14, 700))
                            .foregroundColor(t == target ? .white : Palette.ink)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(Capsule().fill(t == target ? Palette.goldDeep : Palette.card))
                            .overlay(Capsule().stroke(t == target ? Color.clear : Palette.fieldBorder))
                    }
                }
            }
            .padding(.horizontal, 20)
            Text("مجموع تسبيحاتك: " + ar(total)).font(AppFont.ui(13)).foregroundColor(Palette.muted)
                .padding(.top, 12).padding(.bottom, 20)
        }
        .background(Palette.page.ignoresSafeArea())
        .navigationTitle("المسبحة")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("تصفير") { count = 0 }.font(AppFont.ui(14, 700)).foregroundColor(Palette.goldDeep)
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private func tap() {
        count += 1
        total += 1
        if target > 0 && count == target {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        if target > 0 && count > target { count = 1 }
    }
}

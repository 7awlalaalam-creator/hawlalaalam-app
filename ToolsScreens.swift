import SwiftUI
import CoreLocation

private func site(_ path: String) -> URL { URL(string: "https://7awlalaalam.com/quran/" + path)! }

// MARK: - الأدوات

struct ToolsView: View {
    @EnvironmentObject var state: AppState

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                streakCard
                section("القرآن")
                LazyVGrid(columns: columns, spacing: 8) {
                    NavigationLink { IndexView() } label: { ToolTile(title: "الفهرس", systemImage: "list.bullet") }
                    NavigationLink { WebScreen(title: "الترجمات", url: site("languages.html")) } label: { ToolTile(title: "الترجمات", systemImage: "globe") }
                    NavigationLink { WebScreen(title: "التفسير", url: site("tafsir-sources-ar.html")) } label: { ToolTile(title: "التفسير", systemImage: "book") }
                    NavigationLink { WebScreen(title: "حول العالم", url: AppState.home) } label: { ToolTile(title: "الموقع", systemImage: "safari") }
                }
                section("الصلاة والذكر")
                LazyVGrid(columns: columns, spacing: 8) {
                    NavigationLink { PrayerTimesView() } label: { ToolTile(title: "المواقيت", systemImage: "clock") }
                    NavigationLink { QiblaView() } label: { ToolTile(title: "القبلة", systemImage: "location.north.circle") }
                    NavigationLink { WebScreen(title: "الأذكار", url: site("azkar-morning-evening-ar.html")) } label: { ToolTile(title: "الأذكار", systemImage: "sun.and.horizon") }
                    NavigationLink { TasbeehView() } label: { ToolTile(title: "المسبحة", systemImage: "circle.grid.cross") }
                    NavigationLink { PrayerAzkarView() } label: { ToolTile(title: "أذكار الصلاة", systemImage: "moon.stars") }
                    NavigationLink { WebScreen(title: "الأدعية", url: site("duas-library-ar.html")) } label: { ToolTile(title: "الأدعية", systemImage: "hands.sparkles") }
                }
                section("لقلبك والتطبيق")
                LazyVGrid(columns: columns, spacing: 8) {
                    NavigationLink { MoodView() } label: { ToolTile(title: "آية لحالك", systemImage: "heart") }
                    NavigationLink { SettingsView() } label: { ToolTile(title: "التنبيهات", systemImage: "bell") }
                    NavigationLink { SettingsView() } label: { ToolTile(title: "الإعدادات", systemImage: "gearshape") }
                }
                dedicateCard.padding(.top, 12)
            }
            .buttonStyle(.plain)
            .padding(16)
        }
        .background(Palette.page.ignoresSafeArea())
        .navigationTitle("الأدوات")
    }

    private func section(_ t: String) -> some View {
        Text(t).font(AppFont.ui(14, 700)).foregroundColor(Palette.muted).padding(.top, 12).padding(.horizontal, 4)
    }

    private var streakCard: some View {
        let n = state.streak
        let title = n == 0 ? "ابدأ سلسلتك اليوم مع القرآن"
            : n == 1 ? "يوم واحد مع القرآن" : n == 2 ? "يومان متتاليان مع القرآن"
            : ar(n) + (n <= 10 ? " أيام متتالية مع القرآن" : " يومًا متتاليًا مع القرآن")
        let cal = Calendar.current
        let days: [Date] = (0..<7).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: Date()) }
        let letters = ["ح", "ن", "ث", "ر", "خ", "ج", "س"]
        return VStack(alignment: .leading, spacing: 4) {
            Text(title).font(AppFont.ui(16, 700)).foregroundColor(Palette.ink)
            Text(state.readOn(Date()) ? "أحسنت، قرأت اليوم ✓" : "اقرأ ولو آية اليوم لتكملها")
                .font(AppFont.ui(12)).foregroundColor(Palette.muted).padding(.bottom, 8)
            HStack {
                ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                    let on = state.readOn(d)
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
        Button { Share.present([AppState.shareText]) } label: {
            HStack(spacing: 12) {
                Image(systemName: "gift").foregroundColor(Palette.goldLight)
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
    }
}

// MARK: - مواقيت الصلاة

struct PrayerTimesView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var location = LocationService.shared

    var body: some View {
        List {
            if let lat = state.lat, let lng = state.lng {
                let now = Date()
                let t = Prayer.times(for: now, lat: lat, lng: lng)
                let next = Prayer.next(lat: lat, lng: lng, now: now).0
                Section {
                    ForEach(0..<6, id: \.self) { i in
                        HStack {
                            Text(Prayer.displayName(i, on: now)).font(AppFont.ui(16, i == next ? 700 : 500))
                            Spacer()
                            Text(formatTime(t[i])).font(AppFont.ui(16, i == next ? 700 : 400))
                        }
                        .foregroundColor(i == next ? Palette.goldDeep : Palette.ink)
                    }
                } header: {
                    Text(hijriToday() + (state.city.isEmpty ? "" : " · " + state.city)).font(AppFont.ui(13))
                } footer: {
                    Text("طريقة أم القرى · العشاء بعد المغرب بساعة ونصف (ساعتين في رمضان)").font(AppFont.ui(12))
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
                Toggle(isOn: Binding(get: { state.adhanOn }, set: { on in setAdhan(on) })) {
                    Text("تنبيه الأذان").font(AppFont.ui(15, 500))
                }
                .disabled(!state.hasLocation)
            }
        }
        .navigationTitle("مواقيت الصلاة")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func setAdhan(_ on: Bool) {
        if !on { state.adhanOn = false; return }
        Task {
            if await Notifications.requestPermission() { state.adhanOn = true }
        }
    }
}

// MARK: - القبلة

struct QiblaView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var location = LocationService.shared

    private static let kaaba = (lat: 21.422487, lng: 39.826206)

    private var bearing: Double? {
        guard let lat = state.lat, let lng = state.lng else { return nil }
        let p1 = lat * .pi / 180, p2 = Self.kaaba.lat * .pi / 180
        let dl = (Self.kaaba.lng - lng) * .pi / 180
        let y = sin(dl) * cos(p2)
        let x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
        let b = atan2(y, x) * 180 / .pi
        return (b + 360).truncatingRemainder(dividingBy: 360)
    }

    var body: some View {
        VStack(spacing: 24) {
            if let b = bearing {
                let rotation = b - (location.heading ?? 0)
                ZStack {
                    Circle().stroke(Palette.line, lineWidth: 2)
                    Circle().stroke(Palette.gold.opacity(0.5), lineWidth: 1).padding(16)
                    Image(systemName: "location.north.fill")
                        .resizable().scaledToFit().frame(width: 70)
                        .foregroundColor(Palette.goldDeep)
                        .offset(y: -80)
                        .rotationEffect(.degrees(rotation))
                    Image(systemName: "building.columns.fill").font(.system(size: 34)).foregroundColor(Palette.ink)
                }
                .frame(width: 260, height: 260)
                .animation(.easeOut(duration: 0.25), value: rotation)
                Text("اتجاه القبلة " + ar(Int(b.rounded())) + "° من الشمال").font(AppFont.ui(17, 700)).foregroundColor(Palette.ink)
                Text(location.heading == nil ? "البوصلة غير متاحة؛ استخدم الزاوية من الشمال" : "وجّه أعلى الجوال نحو السهم الذهبي، وأبعده عن المعادن")
                    .font(AppFont.ui(13)).foregroundColor(Palette.muted).multilineTextAlignment(.center)
            } else {
                Text("حدّد موقعك لمعرفة اتجاه القبلة").font(AppFont.ui(16, 500)).foregroundColor(Palette.muted)
                Button { location.requestLocation() } label: { Pill(title: "تحديد الموقع", systemImage: "location", primary: true) }
                    .frame(width: 220)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.page.ignoresSafeArea())
        .navigationTitle("القبلة")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { location.startHeading() }
        .onDisappear { location.stopHeading() }
    }
}

// MARK: - المسبحة

struct TasbeehView: View {
    @AppStorage("tasbeeh_count") private var count = 0
    @AppStorage("tasbeeh_target") private var target = 33
    @AppStorage("tasbeeh_phrase") private var phrase = 0
    private let phrases = ["سبحان الله", "الحمد لله", "الله أكبر", "لا إله إلا الله", "أستغفر الله"]

    var body: some View {
        VStack(spacing: 22) {
            Picker("", selection: $phrase) {
                ForEach(0..<phrases.count, id: \.self) { Text(phrases[$0]).tag($0) }
            }
            .pickerStyle(.menu)
            .font(AppFont.ui(18, 700))
            Button {
                count += 1
                let gen = UIImpactFeedbackGenerator(style: target > 0 && count % target == 0 ? .heavy : .light)
                gen.impactOccurred()
            } label: {
                ZStack {
                    Ring(fraction: target > 0 ? Double(count % target) / Double(target) : 0, width: 10)
                    VStack(spacing: 6) {
                        Text(phrases[min(phrase, phrases.count - 1)]).font(AppFont.ui(20, 700)).foregroundColor(Palette.goldDeep)
                        Text(ar(count)).font(AppFont.ui(56, 700)).foregroundColor(Palette.ink).monospacedDigit()
                        if target > 0 { Text("الدورة " + ar(count / target + 1)).font(AppFont.ui(13)).foregroundColor(Palette.muted) }
                    }
                }
                .frame(width: 260, height: 260)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("سبّح، العدد " + ar(count))
            Picker("الهدف", selection: $target) {
                Text("٣٣").tag(33)
                Text("١٠٠").tag(100)
                Text("بلا حد").tag(0)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)
            Button("تصفير العدّاد") { count = 0 }.font(AppFont.ui(15, 700)).foregroundColor(Palette.goldDeep)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.page.ignoresSafeArea())
        .navigationTitle("المسبحة")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - الإعدادات والتنبيهات

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var location = LocationService.shared
    @State private var permissionDenied = false

    var body: some View {
        Form {
            Section {
                toggle("تنبيه الأذان", "عند دخول كل صلاة · طريقة أم القرى", get: { state.adhanOn }, set: { state.adhanOn = $0 })
                    .disabled(!state.hasLocation)
                if !state.hasLocation {
                    Button { location.requestLocation() } label: {
                        Label("حدّد موقعك لتفعيل الأذان", systemImage: "location").font(AppFont.ui(14, 700))
                    }
                }
            } header: { Text("الصلاة").font(AppFont.ui(13, 700)) }

            Section {
                toggle("آية اليوم", "تذكير يومي بآية اليوم", get: { state.verseOn }, set: { state.verseOn = $0 })
                if state.verseOn {
                    Picker(selection: $state.verseHour) {
                        ForEach(4..<23, id: \.self) { h in
                            Text(formatTime(Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: Date()) ?? Date())).tag(h)
                        }
                    } label: { Text("الوقت").font(AppFont.ui(15)) }
                }
                toggle("سورة الكهف", "كل جمعة، نورٌ لك ما بين الجمعتين", get: { state.kahfOn }, set: { state.kahfOn = $0 })
            } header: { Text("القرآن").font(AppFont.ui(13, 700)) }

            Section {
                toggle("أذكار الصباح والمساء", "الصباح ٦:٣٠ ص، والمساء ٥:٠٠ م", get: { state.azkarOn }, set: { state.azkarOn = $0 })
            } header: { Text("الذكر").font(AppFont.ui(13, 700)) }

            if permissionDenied {
                Section {
                    Button("السماح بالتنبيهات من إعدادات الجوال") {
                        if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                    }.font(AppFont.ui(14, 700))
                }
            }

            Section {
                Picker(selection: $state.themeMode) {
                    Text("تلقائي").tag(0)
                    Text("نهاري").tag(1)
                    Text("ليلي").tag(2)
                } label: { Text("المظهر").font(AppFont.ui(15)) }
                .pickerStyle(.segmented)
            } header: { Text("المظهر").font(AppFont.ui(13, 700)) }

            Section {
                Button { Share.present([AppState.shareText]) } label: { Label("شارك التطبيق مع من تحب", systemImage: "square.and.arrow.up") }
                NavigationLink { WebScreen(title: "أرسل ملاحظة", url: site("contact.html")) } label: { Label("أرسل ملاحظة", systemImage: "envelope") }
                NavigationLink { WebScreen(title: "الخصوصية", url: site("privacy-app-section.html")) } label: { Label("سياسة الخصوصية", systemImage: "hand.raised") }
                HStack {
                    Text("الإصدار").font(AppFont.ui(15))
                    Spacer()
                    Text(ar(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")).foregroundColor(Palette.muted)
                }
            } header: { Text("عام").font(AppFont.ui(13, 700)) } footer: {
                Text("صدقة جارية لمحمد بن مفرح الشهري رحمه الله، ولموتى المسلمين").font(AppFont.ui(12)).frame(maxWidth: .infinity)
            }
        }
        .font(AppFont.ui(15))
        .navigationTitle("الإعدادات والتنبيهات")
        .navigationBarTitleDisplayMode(.inline)
    }

    /** مفتاح: عند التفعيل نطلب إذن التنبيهات أولًا */
    private func toggle(_ title: String, _ sub: String, get: @escaping () -> Bool, set: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: get, set: { on in
            if !on { set(false); return }
            Task {
                if await Notifications.requestPermission() { set(true); permissionDenied = false }
                else { permissionDenied = true }
            }
        })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AppFont.ui(16, 700))
                Text(sub).font(AppFont.ui(12)).foregroundColor(Palette.muted)
            }
        }
        .tint(Palette.goldDeep)
    }
}

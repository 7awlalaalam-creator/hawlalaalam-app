import SwiftUI

/** «اليوم»: الترويسة والصلاة القادمة، «أكمل القراءة»، بطاقة في وقتها، آية اليوم، وأربع أدوات */
struct TodayView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var location = LocationService.shared
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                mainCard
                    .padding(.horizontal, 10)
                    .padding(.top, -46)
                if let ctx = azkarPrompt { ctx.padding(.top, 14) }
                verseCard.padding(.top, 14)
                toolsHeader.padding(.top, 22)
                toolsRow.padding(.top, 10)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Palette.page.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task { await state.refreshVerse() }
    }

    // MARK: الترويسة

    private var greeting: String { Calendar.current.component(.hour, from: Date()) < 12 ? "صباح الخير" : "مساء الخير" }

    private var hero: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(uiImage: UIImage(named: "app_logo_png") ?? UIImage())
                    .resizable()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Palette.gold.opacity(0.4)))
                    .accessibilityLabel("حول العالم")
                VStack(alignment: .leading, spacing: 2) {
                    Text(greeting).font(AppFont.ui(22, 700)).foregroundColor(.white)
                    Text(hijriToday() + (state.city.isEmpty ? "" : " · " + state.city))
                        .font(AppFont.ui(13)).foregroundColor(Palette.onDarkMuted).lineLimit(1)
                }
                Spacer(minLength: 4)
                Button {
                    state.themeMode = scheme == .dark ? 1 : 2
                } label: { heroIcon(scheme == .dark ? "sun.max" : "moon") }
                .accessibilityLabel("تبديل الوضع الليلي")
                NavigationLink { SettingsView() } label: { heroIcon("gearshape") }
                    .accessibilityLabel("الإعدادات")
            }
            prayerStrip
        }
        .padding(16)
        .padding(.bottom, 46)
        .background(PatternBackground().clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous)))
    }

    private func heroIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 17, weight: .medium))
            .foregroundColor(Palette.goldLight)
            .frame(width: 44, height: 44)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.gold.opacity(0.3)))
    }

    @ViewBuilder private var prayerStrip: some View {
        if let lat = state.lat, let lng = state.lng {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let nx = Prayer.next(lat: lat, lng: lng, now: ctx.date)
                let idx = nx.0, at = nx.1
                NavigationLink { PrayerTimesView() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "clock").foregroundColor(Palette.gold)
                        Text(Prayer.displayName(idx, on: at)).font(AppFont.ui(15, 700)).foregroundColor(.white)
                        Text(formatTime(at)).font(AppFont.ui(13)).foregroundColor(Palette.onDarkMuted)
                        Spacer()
                        Text("بعد").font(AppFont.ui(13)).foregroundColor(Palette.onDarkMuted)
                        Text(countdown(to: at, from: ctx.date))
                            .font(AppFont.ui(15, 700))
                            .monospacedDigit()
                            .foregroundColor(Palette.goldLight)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                    .stripStyle()
                }
            }
        } else {
            Button { location.requestLocation() } label: {
                HStack {
                    Image(systemName: "clock").foregroundColor(Palette.gold)
                    Text("فعّل مواقيت الصلاة وتنبيه الأذان").font(AppFont.ui(14, 700)).foregroundColor(.white)
                    Spacer()
                    if location.busy { ProgressView().tint(Palette.gold) }
                    else { Text("تفعيل ←").font(AppFont.ui(13, 700)).foregroundColor(Palette.gold) }
                }
                .stripStyle()
            }
        }
    }

    private func countdown(to: Date, from: Date) -> String {
        let s = max(0, Int(to.timeIntervalSince(from)))
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    // MARK: البطاقة الرئيسية

    private var mainCard: some View {
        let page = state.lastPage
        return VStack(spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "book.closed")
                    .font(.system(size: 30))
                    .foregroundColor(Palette.goldDeep)
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(Palette.chip))
                VStack(alignment: .leading, spacing: 3) {
                    Text(page > 0 ? "أكمل من حيث توقفت" : "ابدأ القراءة").font(AppFont.ui(12, 700)).foregroundColor(Palette.goldDeep)
                    Text(page > 0 ? "المصحف · صفحة " + ar(page) : "المصحف الشريف").font(AppFont.ui(18, 700)).foregroundColor(Palette.ink)
                    Text(page > 0 ? Quran.whereIs(page: page) : "بأسطر مصحف المدينة · دون إنترنت")
                        .font(AppFont.ui(13)).foregroundColor(Palette.muted)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Button { state.openMushaf(page: nil) } label: {
                    Pill(title: page > 0 ? "أكمل القراءة" : "افتح المصحف", systemImage: "book", primary: true, height: 48)
                }
                NavigationLink { IndexView() } label: {
                    Pill(title: "الفهرس", systemImage: "list.bullet", height: 48).frame(width: 120)
                }
            }
        }
        .padding(16)
        .card(radius: 22)
        .shadow(color: Color(hex: 0x123640, alpha: 0.14), radius: 12, y: 6)
    }

    // MARK: الأذكار في وقتها

    private var azkarPrompt: AnyView? {
        let h = Calendar.current.component(.hour, from: Date())
        let title: String
        if h >= 4 && h < 11 { title = "حان وقت أذكار الصباح" }
        else if h >= 15 && h < 20 { title = "حان وقت أذكار المساء" }
        else { return nil }
        return AnyView(
            NavigationLink {
                WebScreen(title: "الأذكار", url: URL(string: "https://7awlalaalam.com/quran/azkar-morning-evening-ar.html")!)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: h < 12 ? "sunrise" : "sunset")
                        .foregroundColor(Palette.goldDeep)
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.chip))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(AppFont.ui(15, 700)).foregroundColor(Palette.ink)
                        Text("دقائق تحفظك طوال يومك").font(AppFont.ui(12)).foregroundColor(Palette.muted)
                    }
                    Spacer()
                    Text("ابدأ").font(AppFont.ui(14, 700)).foregroundColor(Palette.ink)
                        .padding(.horizontal, 16).frame(minHeight: 38)
                        .overlay(Capsule().stroke(Palette.fieldBorder))
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .card()
            }
        )
    }

    // MARK: آية اليوم

    private var verseCard: some View {
        VStack(spacing: 10) {
            HStack {
                Label("آية اليوم", systemImage: "sparkle").font(AppFont.ui(13, 700)).foregroundColor(Palette.goldDeep)
                Spacer()
                if let v = state.verse { Text(v.ref).font(AppFont.ui(12)).foregroundColor(Palette.muted) }
            }
            if let v = state.verse {
                Text(Quran.withNumber(v.text, v.ayah))
                    .font(AppFont.quran(v.text.count < 80 ? 25 : (v.text.count < 180 ? 22 : 19)))
                    .foregroundColor(Palette.ink)
                    .multilineTextAlignment(.center)
                    .lineSpacing(8)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                HStack(spacing: 6) {
                    Button { shareImage(v) } label: { Pill(title: "صورة", systemImage: "photo", primary: true, height: 44) }
                    Button { Share.present(["﴿ \(v.text) ﴾\n\(v.ref)\n\nالتفسير: \(v.tafsirURL.absoluteString)"]) } label: {
                        Pill(title: "نص", systemImage: "text.alignright", height: 44)
                    }
                    NavigationLink { WebScreen(title: "التفسير", url: v.tafsirURL) } label: {
                        Pill(title: "التفسير", systemImage: "book", height: 44)
                    }
                }
            } else {
                Text("جارٍ تحميل آية اليوم…").font(AppFont.ui(16, 500)).foregroundColor(Palette.muted).padding(.vertical, 12)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .card(Palette.ivory, border: Palette.ivoryBorder, radius: 22)
    }

    @MainActor private func shareImage(_ v: AppState.DailyVerse) {
        let renderer = ImageRenderer(content: VerseShareCard(verse: v).environment(\.layoutDirection, .rightToLeft))
        renderer.scale = 3
        if let img = renderer.uiImage { Share.present([img, v.ref]) }
    }

    // MARK: الأدوات

    private var toolsHeader: some View {
        HStack {
            Text("أدواتك").font(AppFont.ui(16, 700)).foregroundColor(Palette.ink)
            Spacer()
            Button { state.tab = .tools } label: {
                Text("كل الأدوات ←").font(AppFont.ui(13, 700)).foregroundColor(Palette.goldDeep)
            }
        }
        .padding(.horizontal, 4)
    }

    private var toolsRow: some View {
        HStack(spacing: 8) {
            NavigationLink { MoodView() } label: { ToolTile(title: "آية لحالك", systemImage: "heart") }
            NavigationLink { PrayerAzkarView() } label: { ToolTile(title: "أذكار الصلاة", systemImage: "moon.stars") }
            NavigationLink { QiblaView() } label: { ToolTile(title: "القبلة", systemImage: "location.north.circle") }
            NavigationLink { TasbeehView() } label: { ToolTile(title: "المسبحة", systemImage: "circle.grid.cross") }
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    func stripStyle() -> some View {
        self
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(minHeight: 46)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.gold.opacity(0.25)))
    }
}

/** بطاقة آية اليوم للمشاركة كصورة (بهوية التطبيق وخط المجمع) */
struct VerseShareCard: View {
    var verse: AppState.DailyVerse

    var body: some View {
        VStack(spacing: 18) {
            Text(Quran.withNumber(verse.text, verse.ayah))
                .font(AppFont.quran(26))
                .foregroundColor(Color(hex: 0xF5EBD3))
                .multilineTextAlignment(.center)
                .lineSpacing(10)
            Text(verse.ref + " · حول العالم").font(AppFont.ui(14, 500)).foregroundColor(Palette.goldLight)
        }
        .padding(36)
        .frame(width: 360)
        .background(PatternBackground(color: Color(hex: 0x123640)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.gold.opacity(0.6), lineWidth: 1.5).padding(12))
    }
}

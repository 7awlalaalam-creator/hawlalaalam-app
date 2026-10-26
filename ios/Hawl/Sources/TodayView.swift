import SwiftUI
import StoreKit

/**
 * شاشة «اليوم» — مرتّبة بلا تشتيت (نفس HomeActivity):
 * ١) الترويسة والصلاة القادمة، ٢) بطاقة واحدة «أكمل القراءة» مع حلقة الختمة،
 * ٣) بطاقة في وقتها فقط (رمضان أو الأذكار)، ٤) آية اليوم، ٥) أربع أدوات وباقيها في «الأدوات».
 */
struct TodayView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var location = LocationService.shared
    @Environment(\.colorScheme) private var scheme
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var phase

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                mainCard
                    .padding(.horizontal, 10)
                    .padding(.top, -46)
                if state.hasLocation { PrayerLogCard().padding(.top, 14) }
                if let h = hifzCard { h.padding(.top, 14) }
                if let ctx = ramadanCard ?? azkarPrompt { ctx.padding(.top, 14) }
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
        .onAppear { if RatePrompt.due() { requestReview() } }          // نافذة تقييم App Store بعد قراءة ورد اليوم
        .onChange(of: phase) { p in if p == .active && RatePrompt.due() { requestReview() } }
    }

    // MARK: الترويسة

    private var greeting: String { Calendar.current.component(.hour, from: Date()) < 12 ? L("صباح الخير") : L("مساء الخير") }

    private var hero: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(uiImage: UIImage(named: "app_logo_png") ?? UIImage())
                    .resizable()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Palette.gold.opacity(0.4)))
                    .accessibilityLabel(L("حول العالم"))
                VStack(alignment: .leading, spacing: 2) {
                    Text(greeting).font(AppFont.ui(22, 700)).foregroundColor(.white)
                    Text(hijriToday() + (state.city.isEmpty ? "" : " · " + state.city))
                        .font(AppFont.ui(13)).foregroundColor(Palette.onDarkMuted).lineLimit(1)
                }
                Spacer(minLength: 4)
                Button {
                    state.themeMode = scheme == .dark ? 1 : 2
                } label: { heroIcon(scheme == .dark ? "sun.max" : "moon") }
                .accessibilityLabel(scheme == .dark ? L("الوضع النهاري") : L("الوضع الليلي"))
                NavigationLink(value: Screen.settings) { heroIcon("gearshape") }
                    .accessibilityLabel(L("الإعدادات"))
            }
            if Reading.streak >= 2 { streakChip }
            prayerStrip
            if state.hasLocation { prayersRow }
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

    /** سطر الصلاة القادمة مع العدّ التنازلي؛ وبدون موقع: دعوة لتفعيل المواقيت */
    @ViewBuilder private var prayerStrip: some View {
        if state.hasLocation {
            TimelineView(.everyMinute) { ctx in
                let nx = Prayer.next(now: ctx.date)
                let idx = nx.0, at = nx.1
                NavigationLink(value: Screen.prayerTimes) {
                    HStack(spacing: 6) {
                        Image(systemName: "clock").foregroundColor(Palette.gold)
                        Text(Prayer.displayName(idx, on: at)).font(AppFont.ui(15, 700)).foregroundColor(.white)
                        Text(formatTime(at)).font(AppFont.ui(13)).foregroundColor(Palette.onDarkMuted)
                        Spacer()
                        // «بعد ٥٢ دقيقة» / «بعد ١:٠٥ ساعة» (نفس صيغة أندرويد)
                        Text(Prayer.remaining(at.timeIntervalSince(ctx.date), after: true))
                            .font(AppFont.ui(15, 700))
                            .foregroundColor(Palette.goldLight)
                    }
                    .stripStyle()
                }
                .accessibilityLabel("الصلاة القادمة \(Prayer.displayName(idx, on: at)) \(formatTime(at))، اضغط لعرض المواقيت")
            }
        } else {
            NavigationLink(value: Screen.settings) {
                HStack {
                    Image(systemName: "clock").foregroundColor(Palette.gold)
                    Text(L("فعّل مواقيت الصلاة وتنبيه الأذان")).font(AppFont.ui(14, 700)).foregroundColor(.white)
                    Spacer()
                    if location.busy { ProgressView().tint(Palette.gold) }
                    else { Text(L("تفعيل ←")).font(AppFont.ui(13, 700)).foregroundColor(Palette.gold) }
                }
                .stripStyle()
            }
        }
    }

    /** سلسلة الأيام المتتالية مع القرآن (تظهر من اليوم الثاني) */
    private var streakChip: some View {
        let n = Reading.streak
        let r = n % 100
        let t = n == 2 ? L("يومان متتاليان مع القرآن")
            : (r >= 3 && r <= 10) ? ar(n) + L(" أيام متتالية مع القرآن")
            : (r >= 11 ? ar(n) + L(" يومًا متتاليًا مع القرآن") : ar(n) + L(" يوم متتالٍ مع القرآن"))
        return NavigationLink(value: Screen.khatma) {
            HStack(spacing: 6) {
                Image(systemName: "flame").font(.system(size: 13, weight: .semibold))
                Text(t).font(AppFont.ui(13, 700))
            }
            .foregroundColor(Palette.goldLight)
            .padding(.horizontal, 12).frame(minHeight: 32)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .overlay(Capsule().stroke(Palette.gold.opacity(0.3)))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityLabel(t)
    }

    /** مواقيت اليوم الخمس، والقادمة منها مميّزة بالذهبي */
    private var prayersRow: some View {
        TimelineView(.everyMinute) { ctx in
            let t = Prayer.times(for: ctx.date)
            let list = Prayer.alerts
            let next = list.firstIndex { t[$0] > ctx.date }
            HStack(spacing: 5) {
                ForEach(Array(list.enumerated()), id: \.offset) { k, p in
                    let isNext = k == next
                    VStack(spacing: 3) {
                        Text(Prayer.displayName(p, on: t[p])).font(AppFont.ui(12, isNext ? 700 : 500))
                        Text(formatClockShort(t[p])).font(AppFont.ui(14, 700))
                    }
                    .foregroundColor(isNext ? Palette.widgetDark : Palette.onDarkSoft)
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 12).fill(isNext ? Palette.gold : Color.white.opacity(0.07)))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: البطاقة الرئيسية

    /** «أكمل من حيث توقفت» + حلقة الختمة + ورد اليوم، بزر واحد واضح */
    private var mainCard: some View {
        _ = state.rev
        let last = Reading.lastURL
        let khatma = Khatma.running
        return VStack(spacing: 0) {
            HStack(spacing: 14) {
                // الحلقة: نسبة الختمة، أو أيقونة المصحف إن لم تبدأ ختمة
                NavigationLink(value: Screen.khatma) {
                    ZStack {
                        if khatma {
                            Ring(fraction: Double(Khatma.percent) / 100, track: Palette.chip, tint: Palette.gold)
                            VStack(spacing: 0) {
                                Text(ar(Khatma.percent) + L("٪")).font(AppFont.ui(17, 700)).foregroundColor(Palette.ink)
                                Text(L("الختمة")).font(AppFont.ui(10)).foregroundColor(Palette.muted)
                            }
                        } else {
                            Circle().fill(Palette.chip)
                            Image(systemName: "book.closed").font(.system(size: 28)).foregroundColor(Palette.goldDeep)
                        }
                    }
                    .frame(width: 80, height: 80)
                }
                .accessibilityLabel(khatma ? L("ختمتي ") + ar(Khatma.percent) + L("٪") : L("ختمتي"))
                VStack(alignment: .leading, spacing: 3) {
                    Text(last == nil ? L("ابدأ القراءة") : L("أكمل من حيث توقفت")).font(AppFont.ui(12, 700)).foregroundColor(Palette.goldDeep)
                    Text(last == nil ? L("المصحف الشريف") : Reading.lastTitle).font(AppFont.ui(18, 700)).foregroundColor(Palette.ink)
                        .lineLimit(2)
                    Text(khatma ? Khatma.todayLine : L("ابدأ ختمة: نحسب وردك كل يوم ونذكّرك به"))
                        .font(AppFont.ui(13)).foregroundColor(Palette.muted)
                }
                Spacer(minLength: 0)
            }
            if khatma {
                // تقدّم ورد اليوم
                let target = max(1, Khatma.dailyTarget)
                let doneToday = min(target, Khatma.todayCount)
                ProgressView(value: Double(doneToday), total: Double(target))
                    .tint(Palette.gold)
                    .scaleEffect(x: 1, y: 2, anchor: .center)
                    .padding(.top, 14)
                    .accessibilityLabel("ورد اليوم \(ar(doneToday)) من \(ar(target)) صفحة")
            }
            HStack(spacing: 8) {
                Button {
                    if let u = last { state.open(u) } else { state.openMushaf(page: nil) }
                } label: {
                    Pill(title: last == nil ? L("افتح المصحف") : L("أكمل القراءة"), systemImage: "book", primary: true, height: 48)
                }
                NavigationLink(value: Screen.index) {
                    Pill(title: L("الفهرس"), systemImage: "list.bullet", height: 48).frame(width: 120)
                }
                .accessibilityLabel(L("فهرس السور والأجزاء"))
            }
            .padding(.top, 14)
        }
        .padding(16)
        .card(radius: 22)
        .shadow(color: Color(hex: 0x123640, alpha: 0.14), radius: 12, y: 6)
    }

    // MARK: بطاقات في وقتها

    /** «مراجعة الحفظ»: تظهر يوم تحين مراجعة آيات من الحفظ (الحالة ترسلها صفحة المصحف) */
    private var hifzCard: AnyView? {
        _ = state.rev
        let total = Store.int("hifz_total", 0), next = Store.int("hifz_next", -1)
        let today = Int(floor((Date().timeIntervalSince1970 + Double(TimeZone.current.secondsFromGMT())) / 86400))
        guard total > 0, next >= 0, today >= next else { return nil }
        return AnyView(
            Button { state.openMushaf(page: nil, extra: "hifz=1") } label: {
                HStack(spacing: 12) {
                    Image(systemName: "puzzlepiece")
                        .foregroundColor(Palette.goldDeep)
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.chip))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("مراجعة الحفظ")).font(AppFont.ui(15, 700)).foregroundColor(Palette.ink)
                        Text(L("آيات من حفظك تنتظر المراجعة اليوم")).font(AppFont.ui(12)).foregroundColor(Palette.muted)
                    }
                    Spacer()
                    Text(L("راجع")).font(AppFont.ui(14, 700)).foregroundColor(.white)
                        .padding(.horizontal, 16).frame(minHeight: 38)
                        .background(Capsule().fill(Palette.primary))
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .card()
            }
            .buttonStyle(.plain)
        )
    }

    /** وضع رمضان: يظهر في رمضان، وقبله بعشرة أيام */
    private var ramadanCard: AnyView? {
        let active = Ramadan.active()
        let until = active ? 0 : Ramadan.daysUntil()
        if !active && (until < 1 || until > 10) { return nil }
        if !active {
            return AnyView(
                VStack(alignment: .leading, spacing: 6) {
                    Label(L("رمضان على الأبواب"), systemImage: "moon").font(AppFont.ui(13, 700)).foregroundColor(Palette.gold)
                    Text(L("بعد ") + ar(until) + (until <= 2 ? L(" يوم") : L(" أيام"))).font(AppFont.ui(26, 700)).foregroundColor(.white)
                    Text(L("جهّز ختمة رمضان من الآن، ونذكّرك بوردك كل يوم.")).font(AppFont.ui(14)).foregroundColor(Palette.onDarkMuted)
                    NavigationLink(value: Screen.khatma) { goldPill(L("جهّز ختمتي")) }.padding(.top, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18).padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 22).fill(Palette.dark))
            )
        }
        return AnyView(
            VStack(alignment: .leading, spacing: 0) {
                Label(L("رمضان كريم · ") + Ramadan.ordinal(Ramadan.day()), systemImage: "moon")
                    .font(AppFont.ui(13, 700)).foregroundColor(Palette.gold)
                if state.hasLocation {
                    TimelineView(.periodic(from: Date(), by: 1)) { ctx in
                        let ev = Ramadan.nextEvent(ctx.date)
                        VStack(spacing: 4) {
                            Text(ev.iftar ? L("الإفطار بعد") : L("الإمساك بعد")).font(AppFont.ui(14)).foregroundColor(Palette.onDarkMuted)
                            Text(countdown(ev.at.timeIntervalSince(ctx.date))).font(AppFont.ui(40, 700)).foregroundColor(.white)
                                .monospacedDigit()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)
                    }
                    HStack(spacing: 8) {
                        timeCell(L("الإمساك"), formatTime(Ramadan.imsak(Date())), .white)
                        timeCell(L("الإفطار"), formatTime(Ramadan.iftar(Date())), Palette.gold)
                    }
                    .padding(.top, 10)
                }
                HStack(spacing: 8) {
                    Button { Browser.open(Ramadan.tadabburURL()) } label: {
                        Text(L("تدبّر اليوم")).font(AppFont.ui(14, 700)).foregroundColor(Palette.ink)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(Capsule().fill(Palette.card))
                    }
                    NavigationLink(value: Screen.khatma) { goldPill(L("ختمة رمضان")).frame(maxWidth: .infinity) }
                }
                .padding(.top, 12)
            }
            .padding(.horizontal, 18).padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 22).fill(Palette.dark))
        )
    }

    private func goldPill(_ t: String) -> some View {
        Text(t).font(AppFont.ui(14, 700)).foregroundColor(Palette.widgetDark)
            .padding(.horizontal, 16).frame(minHeight: 42)
            .background(Capsule().fill(Palette.gold))
    }

    private func timeCell(_ name: String, _ time: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(name).font(AppFont.ui(15, 700))
            Text(time).font(AppFont.ui(15, 700))
        }
        .foregroundColor(color)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))
    }

    private func countdown(_ s: TimeInterval) -> String {
        let t = max(0, Int(s))
        return ar(String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60))
    }

    private var azkarPrompt: AnyView? {
        let h = Calendar.current.component(.hour, from: Date())
        let title: String
        if h >= 4 && h < 11 { title = L("حان وقت أذكار الصباح") }
        else if h >= 15 && h < 20 { title = L("حان وقت أذكار المساء") }
        else { return nil }
        return AnyView(
            NavigationLink(value: Screen.azkar(nil)) {
                HStack(spacing: 12) {
                    Image(systemName: h < 12 ? "sunrise" : "sunset")
                        .foregroundColor(Palette.goldDeep)
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.chip))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(AppFont.ui(15, 700)).foregroundColor(Palette.ink)
                        Text(L("دقائق تحفظك طوال يومك")).font(AppFont.ui(12)).foregroundColor(Palette.muted)
                    }
                    Spacer()
                    Text(L("ابدأ")).font(AppFont.ui(14, 700)).foregroundColor(Palette.ink)
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
                Label(L("آية اليوم"), systemImage: "sparkle").font(AppFont.ui(13, 700)).foregroundColor(Palette.goldDeep)
                Spacer()
                if let v = state.verse { Text(v.ref).font(AppFont.ui(12)).foregroundColor(Palette.muted) }
            }
            if let v = state.verse {
                // نص مجمع الملك فهد بخطه، مع علامة نهاية الآية برقمها كما في المصحف
                Text(Quran.withNumber(v.text, v.ayah))
                    .font(AppFont.quran(v.text.count < 80 ? 25 : (v.text.count < 180 ? 22 : 19)))
                    .foregroundColor(Palette.ink)
                    .multilineTextAlignment(.center)
                    .lineSpacing(8)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .textSelection(.enabled)
                // ثلاثة أزرار في صف واحد: الصورة، النص، التفسير
                HStack(spacing: 6) {
                    // مشاركة سريعة، أو تصميم البطاقة في الموقع (تغيير الخلفية وإضافة التفسير)
                    Menu {
                        Button { shareImage(v) } label: { Label(L("شارك الصورة الآن"), systemImage: "square.and.arrow.up") }
                        Button { state.open(v.cardURL) } label: { Label(L("صمّم البطاقة: الخلفية والتفسير"), systemImage: "paintbrush") }
                    } label: {
                        Pill(title: L("صورة"), systemImage: "photo", primary: true, height: 44)
                    }
                    .accessibilityLabel(L("شارك آية اليوم كصورة"))
                    Button { Share.present([v.shareText]) } label: {
                        Pill(title: L("نص"), systemImage: "text.alignright", height: 44)
                    }
                    .accessibilityLabel(L("شارك آية اليوم نصًّا"))
                    NavigationLink(value: Screen.tafsir(v.surah, v.ayah)) {
                        Pill(title: L("التفسير"), systemImage: "book", height: 44)
                    }
                    .accessibilityLabel(L("اقرأ تفسير آية اليوم"))
                }
            } else {
                Text(L("جارٍ تحميل آية اليوم…")).font(AppFont.ui(16, 500)).foregroundColor(Palette.muted).padding(.vertical, 12)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .card(Palette.ivory, border: Palette.ivoryBorder, radius: 22)
    }

    /** بطاقة الآية صورةً جاهزة للمشاركة (تُرسم على الجهاز دون إنترنت)؛ وإن تعذّر الرسم فصفحة البطاقة في الموقع */
    @MainActor private func shareImage(_ v: AppState.DailyVerse) {
        let r = ImageRenderer(content: VerseShareCard(verse: v).environment(\.layoutDirection, .rightToLeft))
        r.scale = 3
        if let img = r.uiImage { Share.present([img, v.shareText]) } else { state.open(v.cardURL) }
    }

    // MARK: الأدوات

    private var toolsHeader: some View {
        HStack {
            Text(L("أدواتك")).font(AppFont.ui(16, 700)).foregroundColor(Palette.ink)
            Spacer()
            Button { state.tab = .tools } label: {
                Text(L("كل الأدوات ←")).font(AppFont.ui(13, 700)).foregroundColor(Palette.goldDeep)
            }
        }
        .padding(.horizontal, 4)
    }

    /** أكثر أربع أدوات استخدامًا؛ الباقي في شاشة «الأدوات» */
    private var toolsRow: some View {
        HStack(spacing: 8) {
            NavigationLink(value: Screen.mood(nil)) { ToolTile(title: L("آية لحالك"), systemImage: "heart") }
            NavigationLink(value: Screen.azkar(nil)) { ToolTile(title: L("الأذكار"), systemImage: "sun.and.horizon") }
            NavigationLink(value: Screen.qibla) { ToolTile(title: L("القبلة"), systemImage: "location.north.circle") }
            NavigationLink(value: Screen.tasbeeh) { ToolTile(title: L("المسبحة"), systemImage: "circle.grid.cross") }
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

/** بطاقة آية اليوم كصورة (بهوية التطبيق وخط المجمع) — للإشعار */
struct VerseShareCard: View {
    var verse: AppState.DailyVerse

    var body: some View {
        VStack(spacing: 18) {
            Text(Quran.withNumber(verse.text, verse.ayah))
                .font(AppFont.quran(26))
                .foregroundColor(Color(hex: 0xF5EBD3))
                .multilineTextAlignment(.center)
                .lineSpacing(10)
            Text(verse.ref + L(" · القرآن حول العالم")).font(AppFont.ui(14, 500)).foregroundColor(Palette.goldLight)
        }
        .padding(36)
        .frame(width: 360)
        .background(PatternBackground(color: Color(hex: 0x123640)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.gold.opacity(0.6), lineWidth: 1.5).padding(12))
    }
}


/**
 * نافذة التقييم الرسمية من App Store في لحظة مريحة: بعد قراءة ورد اليوم، ومع سلسلة ٣ أيام على الأقل،
 * وبعد ٧ أيام من أول استخدام، ومرة كل ٤ أشهر على الأكثر (والنظام نفسه يحدّها بثلاث مرات في السنة).
 */
enum RatePrompt {
    private static var askedThisRun = false

    static func due() -> Bool {
        if askedThisRun { return false }
        let now = Date().timeIntervalSince1970
        var first = Store.d.double(forKey: "first_open_at")
        if first == 0 { first = now; Store.d.set(now, forKey: "first_open_at") }
        guard now - first >= 7 * 86400,
              now - Store.d.double(forKey: "rate_asked_at") >= 120 * 86400,
              Reading.readOn(Date()), Reading.streak >= 3 else { return false }
        askedThisRun = true
        Store.d.set(now, forKey: "rate_asked_at")
        return true
    }
}

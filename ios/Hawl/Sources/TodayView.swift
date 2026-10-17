import SwiftUI

/**
 * شاشة «اليوم» — مرتّبة بلا تشتيت (نفس HomeActivity):
 * ١) الترويسة والصلاة القادمة، ٢) بطاقة واحدة «أكمل القراءة» مع حلقة الختمة،
 * ٣) بطاقة في وقتها فقط (رمضان أو الأذكار)، ٤) آية اليوم، ٥) أربع أدوات وباقيها في «الأدوات».
 */
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
                .accessibilityLabel(scheme == .dark ? "الوضع النهاري" : "الوضع الليلي")
                NavigationLink(value: Screen.settings) { heroIcon("gearshape") }
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
                    Text("فعّل مواقيت الصلاة وتنبيه الأذان").font(AppFont.ui(14, 700)).foregroundColor(.white)
                    Spacer()
                    if location.busy { ProgressView().tint(Palette.gold) }
                    else { Text("تفعيل ←").font(AppFont.ui(13, 700)).foregroundColor(Palette.gold) }
                }
                .stripStyle()
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
                                Text(ar(Khatma.percent) + "٪").font(AppFont.ui(17, 700)).foregroundColor(Palette.ink)
                                Text("الختمة").font(AppFont.ui(10)).foregroundColor(Palette.muted)
                            }
                        } else {
                            Circle().fill(Palette.chip)
                            Image(systemName: "book.closed").font(.system(size: 28)).foregroundColor(Palette.goldDeep)
                        }
                    }
                    .frame(width: 80, height: 80)
                }
                .accessibilityLabel(khatma ? "ختمتي " + ar(Khatma.percent) + "٪" : "ختمتي")
                VStack(alignment: .leading, spacing: 3) {
                    Text(last == nil ? "ابدأ القراءة" : "أكمل من حيث توقفت").font(AppFont.ui(12, 700)).foregroundColor(Palette.goldDeep)
                    Text(last == nil ? "المصحف الشريف" : Reading.lastTitle).font(AppFont.ui(18, 700)).foregroundColor(Palette.ink)
                        .lineLimit(2)
                    Text(khatma ? Khatma.todayLine : "ابدأ ختمة: نحسب وردك كل يوم ونذكّرك به")
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
                    Pill(title: last == nil ? "افتح المصحف" : "أكمل القراءة", systemImage: "book", primary: true, height: 48)
                }
                NavigationLink(value: Screen.index) {
                    Pill(title: "الفهرس", systemImage: "list.bullet", height: 48).frame(width: 120)
                }
                .accessibilityLabel("فهرس السور والأجزاء")
            }
            .padding(.top, 14)
        }
        .padding(16)
        .card(radius: 22)
        .shadow(color: Color(hex: 0x123640, alpha: 0.14), radius: 12, y: 6)
    }

    // MARK: بطاقات في وقتها

    /** وضع رمضان: يظهر في رمضان، وقبله بعشرة أيام */
    private var ramadanCard: AnyView? {
        let active = Ramadan.active()
        let until = active ? 0 : Ramadan.daysUntil()
        if !active && (until < 1 || until > 10) { return nil }
        if !active {
            return AnyView(
                VStack(alignment: .leading, spacing: 6) {
                    Label("رمضان على الأبواب", systemImage: "moon").font(AppFont.ui(13, 700)).foregroundColor(Palette.gold)
                    Text("بعد " + ar(until) + (until <= 2 ? " يوم" : " أيام")).font(AppFont.ui(26, 700)).foregroundColor(.white)
                    Text("جهّز ختمة رمضان من الآن، ونذكّرك بوردك كل يوم.").font(AppFont.ui(14)).foregroundColor(Palette.onDarkMuted)
                    NavigationLink(value: Screen.khatma) { goldPill("جهّز ختمتي") }.padding(.top, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18).padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 22).fill(Palette.dark))
            )
        }
        return AnyView(
            VStack(alignment: .leading, spacing: 0) {
                Label("رمضان كريم · " + Ramadan.ordinal(Ramadan.day()), systemImage: "moon")
                    .font(AppFont.ui(13, 700)).foregroundColor(Palette.gold)
                if state.hasLocation {
                    TimelineView(.periodic(from: Date(), by: 1)) { ctx in
                        let ev = Ramadan.nextEvent(ctx.date)
                        VStack(spacing: 4) {
                            Text(ev.iftar ? "الإفطار بعد" : "الإمساك بعد").font(AppFont.ui(14)).foregroundColor(Palette.onDarkMuted)
                            Text(countdown(ev.at.timeIntervalSince(ctx.date))).font(AppFont.ui(40, 700)).foregroundColor(.white)
                                .monospacedDigit()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)
                    }
                    HStack(spacing: 8) {
                        timeCell("الإمساك", formatTime(Ramadan.imsak(Date())), .white)
                        timeCell("الإفطار", formatTime(Ramadan.iftar(Date())), Palette.gold)
                    }
                    .padding(.top, 10)
                }
                HStack(spacing: 8) {
                    NavigationLink(value: Screen.web(Ramadan.tadabburURL(), "تدبّر اليوم")) {
                        Text("تدبّر اليوم").font(AppFont.ui(14, 700)).foregroundColor(Palette.ink)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(Capsule().fill(Palette.card))
                    }
                    NavigationLink(value: Screen.khatma) { goldPill("ختمة رمضان").frame(maxWidth: .infinity) }
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
        if h >= 4 && h < 11 { title = "حان وقت أذكار الصباح" }
        else if h >= 15 && h < 20 { title = "حان وقت أذكار المساء" }
        else { return nil }
        return AnyView(
            NavigationLink(value: Screen.web(Links.azkar, "الأذكار")) {
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
                    NavigationLink(value: Screen.web(v.cardURL, "آية اليوم")) {
                        Pill(title: "صورة", systemImage: "photo", primary: true, height: 44)
                    }
                    .accessibilityLabel("شارك آية اليوم كصورة")
                    Button { Share.present([v.shareText]) } label: {
                        Pill(title: "نص", systemImage: "text.alignright", height: 44)
                    }
                    .accessibilityLabel("شارك آية اليوم نصًّا")
                    NavigationLink(value: Screen.web(v.tafsirURL, "التفسير")) {
                        Pill(title: "التفسير", systemImage: "book", height: 44)
                    }
                    .accessibilityLabel("اقرأ تفسير آية اليوم")
                }
            } else {
                Text("جارٍ تحميل آية اليوم…").font(AppFont.ui(16, 500)).foregroundColor(Palette.muted).padding(.vertical, 12)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .card(Palette.ivory, border: Palette.ivoryBorder, radius: 22)
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

    /** أكثر أربع أدوات استخدامًا؛ الباقي في شاشة «الأدوات» */
    private var toolsRow: some View {
        HStack(spacing: 8) {
            NavigationLink(value: Screen.mood(nil)) { ToolTile(title: "آية لحالك", systemImage: "heart") }
            NavigationLink(value: Screen.web(Links.azkar, "الأذكار")) { ToolTile(title: "الأذكار", systemImage: "sun.and.horizon") }
            NavigationLink(value: Screen.qibla) { ToolTile(title: "القبلة", systemImage: "location.north.circle") }
            NavigationLink(value: Screen.tasbeeh) { ToolTile(title: "المسبحة", systemImage: "circle.grid.cross") }
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
            Text(verse.ref + " · حول العالم").font(AppFont.ui(14, 500)).foregroundColor(Palette.goldLight)
        }
        .padding(36)
        .frame(width: 360)
        .background(PatternBackground(color: Color(hex: 0x123640)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.gold.opacity(0.6), lineWidth: 1.5).padding(12))
    }
}

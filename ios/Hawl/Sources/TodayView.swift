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
            // تخطيط «بينتو» (نفس HomeActivity): الترويسة ← ورد اليوم ← إعلان الموقع ←
            // [الصلاة القادمة | السلسلة + خانة الوقت] ← رمضان ← صلواتي اليوم مع المواقيت ← آية اليوم ← أدواتك
            VStack(spacing: 12) {
                header
                wirdCard.padding(.top, 2)
                SiteNoticeCard().padding(.top, -14)
                nextRow
                if let r = ramadanCard { r }
                if state.hasLocation { prayersCard }
                verseCard
                toolsHeader.padding(.top, 8)
                toolsRow
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Palette.page.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task { await state.refreshVerse() }
        .task { await SiteServices.shared.refresh() }
        .refreshable { await SiteServices.shared.refresh(force: true) }         // اسحب للأسفل: الإعلان فورًا
        .onAppear { if RatePrompt.due() { requestReview() } }          // نافذة تقييم App Store بعد قراءة ورد اليوم
        .onChange(of: phase) { p in if p == .active && RatePrompt.due() { requestReview() } }
    }

    // MARK: الترويسة

    private var greeting: String { Calendar.current.component(.hour, from: Date()) < 12 ? L("صباح الخير") : L("مساء الخير") }

    private var header: some View {
        HStack(spacing: 12) {
            Image(uiImage: UIImage(named: "app_logo_png") ?? UIImage())
                .resizable()
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Palette.gold.opacity(0.4)))
                .accessibilityLabel(L("حول العالم"))
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting).font(AppFont.ui(23, 700)).foregroundColor(Palette.ink)
                Text(hijriToday() + (state.city.isEmpty ? "" : " · " + state.city))
                    .font(AppFont.ui(13)).foregroundColor(Palette.muted).lineLimit(1)
            }
            Spacer(minLength: 4)
            Button {
                state.themeMode = scheme == .dark ? 1 : 2
            } label: { headIcon(scheme == .dark ? "sun.max" : "moon") }
            .accessibilityLabel(scheme == .dark ? L("الوضع النهاري") : L("الوضع الليلي"))
            NavigationLink(value: Screen.settings) { headIcon("gearshape") }
                .accessibilityLabel(L("الإعدادات"))
        }
        .padding(.horizontal, 2)
    }

    private func headIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 17, weight: .medium))
            .foregroundColor(Palette.goldDeep)
            .frame(width: 44, height: 44)
            .card(radius: 15)
    }

    private static let lightGold = Color(hex: 0xE2C48E)
    private static let goldFill = LinearGradient(colors: [Color(hex: 0xF3DFA8), Color(hex: 0xC9A876)], startPoint: .top, endPoint: .bottom)
    private static let prayerFill = LinearGradient(colors: [Color(hex: 0xF3DFA8), Color(hex: 0xD9B46A), Color(hex: 0xB88A3E)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing)

    // MARK: ورد اليوم

    /** الخانة الكبرى: ورد اليوم وحلقة الختمة و«أكمل القراءة» */
    private var wirdCard: some View {
        _ = state.rev
        let last = Reading.lastURL
        let khatma = Khatma.running
        let target = max(1, Khatma.dailyTarget)
        let doneToday = min(target, Khatma.todayCount)
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(khatma ? L("ورد اليوم · ختمتي ") + ar(Khatma.percent) + L("٪")
                         : (last == nil ? L("ابدأ القراءة") : L("أكمل من حيث توقفت")))
                        .font(AppFont.ui(12, 700)).foregroundColor(Self.lightGold)
                    Text(khatma ? ar(doneToday) + L(" من ") + ar(target) + ((3...10).contains(target) ? L(" صفحات") : L(" صفحة"))
                         : (last == nil ? L("المصحف الشريف") : Reading.lastTitle))
                        .font(AppFont.ui(21, 700)).foregroundColor(.white).lineLimit(2)
                    Text(khatma ? Khatma.todayLine : L("ابدأ ختمة: نحسب وردك كل يوم ونذكّرك به"))
                        .font(AppFont.ui(13)).foregroundColor(Palette.onDarkMuted).lineLimit(2)
                }
                Spacer(minLength: 0)
                // الحلقة: نسبة الختمة، أو أيقونة المصحف إن لم تبدأ ختمة
                NavigationLink(value: Screen.khatma) {
                    ZStack {
                        if khatma {
                            Ring(fraction: Double(Khatma.percent) / 100, track: Color.white.opacity(0.15), tint: Self.lightGold)
                            Text(ar(Khatma.percent) + L("٪")).font(AppFont.ui(16, 700)).foregroundColor(.white)
                        } else {
                            Circle().fill(Color.white.opacity(0.1)).overlay(Circle().stroke(Color.white.opacity(0.2)))
                            Image(systemName: "book.closed").font(.system(size: 26)).foregroundColor(Self.lightGold)
                        }
                    }
                    .frame(width: 78, height: 78)
                }
                .accessibilityLabel(khatma ? L("ختمتي ") + ar(Khatma.percent) + L("٪") : L("ختمتي"))
            }
            HStack(spacing: 8) {
                Button {
                    if let u = last { state.open(u) } else { state.openMushaf(page: nil) }
                } label: {
                    Text(last == nil ? L("افتح المصحف") : L("أكمل القراءة")).font(AppFont.ui(15, 700))
                        .foregroundColor(Color(hex: 0x2B1D06))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: 15).fill(Self.goldFill))
                }
                NavigationLink(value: Screen.index) {
                    Text(L("الفهرس")).font(AppFont.ui(14, 700)).foregroundColor(.white)
                        .padding(.horizontal, 18).frame(minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.11)))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.19)))
                }
                .accessibilityLabel(L("فهرس السور والأجزاء"))
            }
            .padding(.top, 16)
        }
        .padding(16)
        .background(PatternBackground().clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous)))
        .shadow(color: Color(hex: 0x123640, alpha: 0.18), radius: 10, y: 5)
    }

    // MARK: الصلاة القادمة والخانات الصغيرة

    /** صف: الصلاة القادمة (ذهبية) بجانب عمود فيه السلسلة وخانة الوقت */
    private var nextRow: some View {
        HStack(spacing: 10) {
            nextPrayerCard.frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(spacing: 10) {
                streakTile.frame(maxHeight: .infinity)
                contextTile.frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(minHeight: 164)
        .fixedSize(horizontal: false, vertical: true)
        .buttonStyle(.plain)
    }

    @ViewBuilder private var nextPrayerCard: some View {
        let dk = Color(hex: 0x2B1D06), dk2 = Color(hex: 0x5A3F10)
        if state.hasLocation {
            TimelineView(.everyMinute) { ctx in
                let nx = Prayer.next(now: ctx.date)
                let idx = nx.0, at = nx.1
                NavigationLink(value: Screen.prayerTimes) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("الصلاة القادمة")).font(AppFont.ui(12, 700)).foregroundColor(dk2)
                        Text(Prayer.displayName(idx, on: at)).font(AppFont.ui(32, 700)).foregroundColor(dk)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text(formatTime(at)).font(AppFont.ui(15, 700)).foregroundColor(dk)
                        Spacer(minLength: 6)
                        Text(Prayer.remaining(at.timeIntervalSince(ctx.date), after: true))
                            .font(AppFont.ui(14, 700)).foregroundColor(dk)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Self.prayerFill))
                }
                .accessibilityLabel("الصلاة القادمة \(Prayer.displayName(idx, on: at)) \(formatTime(at))، اضغط لعرض المواقيت")
            }
        } else {
            NavigationLink(value: Screen.settings) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("مواقيت الصلاة")).font(AppFont.ui(12, 700)).foregroundColor(dk2)
                    Text(L("فعّل المواقيت وتنبيه الأذان")).font(AppFont.ui(18, 700)).foregroundColor(dk)
                    Spacer(minLength: 6)
                    if location.busy { ProgressView().tint(dk) }
                    else { Text(L("تفعيل ←")).font(AppFont.ui(14, 700)).foregroundColor(dk) }
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Self.prayerFill))
            }
        }
    }

    /** السلسلة: أيام متتالية مع القرآن */
    private var streakTile: some View {
        let n = Reading.streak
        let m = n % 100
        let unit = n == 0 ? L("ابدأ اليوم") : n == 1 ? L("يوم مع القرآن") : n == 2 ? L("يومان مع القرآن")
            : (m >= 3 && m <= 10) ? L("أيام مع القرآن") : L("يومًا مع القرآن")
        return NavigationLink(value: Screen.journey) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("متتالية")).font(AppFont.ui(12, 700)).foregroundColor(Palette.goldDeep)
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(ar(n)).font(AppFont.ui(28, 700)).foregroundColor(Palette.ink)
                    Text(unit).font(AppFont.ui(12)).foregroundColor(Palette.muted).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .card(radius: 20)
        }
        .accessibilityLabel(ar(n) + " " + unit)
    }

    /** خانة الوقت: مراجعة الحفظ إن حانت، وإلا الأذكار في وقتها، وإلا «رحلتي» */
    private var contextTile: some View {
        _ = state.rev
        let total = Store.int("hifz_total", 0), next = Store.int("hifz_next", -1)
        let today = Int(floor((Date().timeIntervalSince1970 + Double(TimeZone.current.secondsFromGMT())) / 86400))
        let h = Calendar.current.component(.hour, from: Date())
        let hifz = total > 0 && next >= 0 && today >= next
        let icon: String, title: String, sub: String
        if hifz { icon = "puzzlepiece"; title = L("مراجعة الحفظ"); sub = L("آيات تنتظرك · راجع") }
        else if h >= 4 && h < 11 { icon = "sunrise"; title = L("أذكار الصباح"); sub = L("حان وقتها · ابدأ") }
        else if h >= 15 && h < 20 { icon = "sunset"; title = L("أذكار المساء"); sub = L("حان وقتها · ابدأ") }
        else { icon = "chart.line.uptrend.xyaxis"; title = L("رحلتي"); sub = L("أيامك مع القرآن") }
        let label = HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 22)).foregroundColor(Palette.goldDeep)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(AppFont.ui(14, 700)).foregroundColor(Palette.ink).lineLimit(1)
                Text(sub).font(AppFont.ui(11)).foregroundColor(Palette.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .card(radius: 20)
        .accessibilityElement(children: .combine)
        return Group {
            if hifz {
                Button { state.openMushaf(page: nil, extra: "hifz=1") } label: { label }
            } else if title == L("رحلتي") {
                NavigationLink(value: Screen.journey) { label }
            } else {
                NavigationLink(value: Screen.azkar(nil)) { label }
            }
        }
    }

    /** صلواتي اليوم مع المواقيت: المؤداة ✓، والقادمة ذهبية، والضغط يسجّل الصلاة */
    private var prayersCard: some View {
        _ = state.rev
        return TimelineView(.everyMinute) { ctx in
            let t = Prayer.times(for: ctx.date)
            let today = PrayerLog.day(ctx.date)
            let m = PrayerLog.mask(today)
            let next = (0..<5).first { t[Prayer.alerts[$0]] > ctx.date }
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(L("صلواتي اليوم")).font(AppFont.ui(13, 700)).foregroundColor(Palette.goldDeep)
                    Spacer()
                    NavigationLink(value: Screen.journey) {
                        Text(ar(PrayerLog.count(m)) + L(" من ٥ · رحلتي ←")).font(AppFont.ui(12)).foregroundColor(Palette.muted)
                    }
                }
                HStack(spacing: 5) {
                    ForEach(0..<5, id: \.self) { i in
                        let p = Prayer.alerts[i]
                        let on = m & (1 << i) != 0
                        let due = t[p] <= ctx.date
                        let isNext = i == next
                        let fg: Color = isNext ? Color(hex: 0x2B1D06) : (on || due) ? Self.lightGold : Palette.muted
                        let fg2: Color = isNext ? Color(hex: 0x5A3F10) : (on || due) ? .white : Palette.muted
                        Button {
                            if due || on {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                PrayerLog.toggle(day: today, prayer: i)
                                state.touch()
                            } else {
                                state.show(.prayerTimes)
                            }
                        } label: {
                            VStack(spacing: 1) {
                                Text(Prayer.displayName(p, on: t[p])).font(AppFont.ui(12, 700)).foregroundColor(fg)
                                Text(formatClockShort(t[p])).font(AppFont.ui(12, 500)).foregroundColor(fg2)
                                Text(on ? "✓" : isNext ? L("القادمة") : due ? "○" : " ")
                                    .font(AppFont.ui(on ? 14 : 11, 700))
                                    .foregroundColor(on ? Color(hex: 0x9FD8B8) : fg2)
                            }
                            .lineLimit(1).minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                Group {
                                    if isNext { RoundedRectangle(cornerRadius: 12).fill(Self.goldFill) }
                                    else if on || due { RoundedRectangle(cornerRadius: 12).fill(Palette.primaryGrad) }
                                    else { RoundedRectangle(cornerRadius: 12).fill(Palette.chip) }
                                }
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(PrayerLog.names[i] + " " + formatTime(t[p])
                                            + (on ? L("، صلّيتها") : due ? L("، اضغط لتسجيلها") : L("، لم يدخل وقتها")))
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .card(radius: 20)
        }
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
                    Label(L("رمضان على الأبواب"), systemImage: "moon").font(AppFont.ui(13, 700)).foregroundColor(Palette.gold)
                    Text(L("بعد ") + ar(until) + (until <= 2 ? L(" يوم") : L(" أيام"))).font(AppFont.ui(26, 700)).foregroundColor(.white)
                    Text(L("جهّز ختمة رمضان من الآن، ونذكّرك بوردك كل يوم.")).font(AppFont.ui(14)).foregroundColor(Palette.onDarkMuted)
                    NavigationLink(value: Screen.khatma) { goldPill(L("جهّز ختمتي")) }.padding(.top, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18).padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 22).fill(Palette.darkGrad))
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
            .background(RoundedRectangle(cornerRadius: 22).fill(Palette.darkGrad))
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

    // MARK: آية اليوم

    private var verseCard: some View {
        VStack(spacing: 10) {
            HStack {
                Label(L("آية اليوم"), systemImage: "sparkle").font(AppFont.ui(13, 700)).foregroundColor(Self.lightGold)
                Spacer()
                if let v = state.verse { Text(v.ref).font(AppFont.ui(12)).foregroundColor(Palette.onDarkMuted) }
            }
            if let v = state.verse {
                // نص مجمع الملك فهد بخطه، مع علامة نهاية الآية برقمها كما في المصحف
                Text(Quran.withNumber(v.text, v.ayah))
                    .font(AppFont.quran(v.text.count < 80 ? 25 : (v.text.count < 180 ? 22 : 19)))
                    .foregroundColor(.white)
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
                        Button {
                            // صفحة التصميم في الموقع مباشرة (state.open يحوّل رابط البطاقة إلى المشاركة السريعة)،
                            // وبعد إغلاق القائمة حتى لا تتعارض نافذتان
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { Browser.open(v.cardURL) }
                        } label: { Label(L("صمّم البطاقة: الخلفية والتفسير"), systemImage: "paintbrush") }
                    } label: {
                        glassPill(L("صورة"))
                    }
                    .accessibilityLabel(L("شارك آية اليوم كصورة"))
                    Button { Share.present([v.shareText]) } label: {
                        glassPill(L("نص"))
                    }
                    .accessibilityLabel(L("شارك آية اليوم نصًّا"))
                    NavigationLink(value: Screen.tafsir(v.surah, v.ayah)) {
                        glassPill(L("التفسير"))
                    }
                    .accessibilityLabel(L("اقرأ تفسير آية اليوم"))
                }
            } else {
                Text(L("جارٍ تحميل آية اليوم…")).font(AppFont.ui(16, 500)).foregroundColor(Palette.onDarkMuted).padding(.vertical, 12)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(PatternBackground().clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous)))
    }

    private func glassPill(_ t: String) -> some View {
        Text(t).font(AppFont.ui(14, 700)).foregroundColor(Self.lightGold)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.11)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.19)))
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

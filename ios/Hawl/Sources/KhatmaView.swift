import SwiftUI

/** الختمة الذكية: إعداد الخطة، ومتابعة التقدّم، والتذكير (نفس KhatmaActivity) */
struct KhatmaView: View {
    @EnvironmentObject var state: AppState

    private static let dayNames = ["أحد", "اثنين", "ثلاثاء", "أربعاء", "خميس", "جمعة", "سبت"]
    /** خيار التذكير: صلاة (Prayer.fajr…) أو وقت ثابت أو بلا تذكير */
    private static let remindFixed = -1, remindNone = -2

    @State private var editing = false
    @State private var setupLoaded = false
    @State private var plan = Khatma.Plan()
    @State private var customDays = false
    @State private var customPpd = false
    @State private var remind = remindFixed
    @State private var remindTime = Date()
    @State private var followUp = true
    @State private var celebrate = false
    @State private var confirmStop = false
    @State private var confirmNew = false
    @State private var ask: NumberAsk?
    @State private var askText = ""
    @State private var extendedNote = false
    @State private var pickTime = false

    struct NumberAsk: Identifiable {
        let id = UUID()
        let title: String, hint: String, min: Int, max: Int
        let done: (Int) -> Void
    }

    private var running: Bool { _ = state.rev; return Khatma.running }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !running || editing {
                    setupCard.padding(.top, 14)
                } else {
                    progressCard.padding(.top, 14)
                    todayCard.padding(.top, 14)
                    if extendedNote {
                        note("انتهت مدة الختمة قبل إتمامها، فمدّدنا الموعد بنفس وردك اليومي بدل أن نُثقل عليك. موعدك الجديد: " + Khatma.endDateText)
                            .padding(.top, 14)
                    } else if Khatma.missedDays {
                        note(Khatma.fixedPace ? "فاتك يوم؟ لا بأس، وردك كما هو، وتحرّك موعد الختم قليلًا."
                             : "فاتك يوم؟ لا بأس، وزّعنا الصفحات الباقية على الأيام القادمة بهدوء، وموعد ختمتك كما هو.")
                            .padding(.top, 14)
                    }
                    section("هذا الأسبوع").padding(.top, 20)
                    week.padding(.top, 8)
                    section("خطتك").padding(.top, 20)
                    planCard.padding(.top, 8)
                    Button { confirmStop = true } label: {
                        Text("إنهاء هذه الختمة").font(AppFont.ui(13, 500)).foregroundColor(Palette.muted)
                            .frame(maxWidth: .infinity).padding(.top, 18).padding(.bottom, 4)
                    }
                }
                if !Khatma.history.isEmpty {
                    section("ختماتك السابقة").padding(.top, 20)
                    historyCard.padding(.top, 8)
                }
                Text("تُحتسب الصفحة مقروءة عندما تبقى عليها في المصحف بضع ثوانٍ، فلا يُحسب التصفح السريع. "
                     + "ويصلك تذكير الورد من التطبيق نفسه ولو كان مغلقًا، ولا يصلك إن أتممت وردك.")
                    .font(AppFont.ui(13)).foregroundColor(Palette.muted).lineSpacing(3)
                    .padding(.horizontal, 4).padding(.top, 18)
            }
            .padding(.horizontal, 18).padding(.bottom, 32)
        }
        .background(Palette.page.ignoresSafeArea())
        .navigationTitle(editing ? "تعديل الخطة" : "ختمتي")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Khatma.ensureDay()
            if Khatma.active && Khatma.consumeJustDone() { celebrate = true }
            if Khatma.consumeExtendedNote() { extendedNote = true }
            if !setupLoaded { loadSetup() }
        }
        .alert("ختمت القرآن الكريم، تقبّل الله منك", isPresented: $celebrate) {
            Button("آمين", role: .cancel) { }
        } message: { Text("اللهم ارحمني بالقرآن واجعله لي إمامًا ونورًا وهدًى ورحمة.") }
        .alert("إنهاء الختمة؟", isPresented: $confirmStop) {
            Button("نعم", role: .destructive) { Khatma.stop(); setupLoaded = false; loadSetup() }
            Button("إلغاء", role: .cancel) { }
        } message: { Text("سيُحذف تقدّمك في هذه الختمة.") }
        .alert("بدء ختمة جديدة؟", isPresented: $confirmNew) {
            Button("نعم") { commitNow() }
            Button("إلغاء", role: .cancel) { }
        } message: { Text("ستبدأ ختمة جديدة ويُحذف تقدّم الختمة الحالية.") }
        .alert(ask?.title ?? "", isPresented: Binding(get: { ask != nil }, set: { if !$0 { ask = nil } })) {
            TextField(ask?.hint ?? "", text: $askText).keyboardType(.numberPad)
            Button("تم") {
                if let a = ask, let v = Int(Self.westernDigits(askText).trimmingCharacters(in: .whitespaces)), v >= a.min && v <= a.max { a.done(v) }
                ask = nil
            }
            Button("إلغاء", role: .cancel) { ask = nil }
        }
        .sheet(isPresented: $pickTime) {
            NavigationStack {
                DatePicker("", selection: $remindTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel).labelsHidden()
                    .environment(\.locale, Locale(identifier: "ar"))
                    .navigationTitle("وقت التذكير").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("تم") { remind = Self.remindFixed; pickTime = false } } }
            }
            .presentationDetents([.medium])
            .environment(\.layoutDirection, .rightToLeft)
        }
    }

    // MARK: المتابعة

    private var progressCard: some View {
        _ = state.rev
        let next = Khatma.nextPage
        let ahead = Khatma.aheadBy
        let status: String
        if ahead > 0 { status = "متقدّم على خطتك بـ " + ar(ahead) + " صفحة، بارك الله فيك" }
        else if ahead < 0 { status = "متأخر " + ar(-ahead) + " صفحة عن الخطة" + (Khatma.fixedPace ? "، وتحرّك موعد الختم قليلًا" : "، وزّعناها على أيامك القادمة") }
        else { status = "على خطتك تمامًا" }
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("تقدّمك").font(AppFont.ui(16, 700)).foregroundColor(Palette.ink)
                Spacer()
                Text(ar(Khatma.read) + " من ٦٠٤ صفحة").font(AppFont.ui(13)).foregroundColor(Palette.muted)
            }
            ProgressView(value: Double(Khatma.percent), total: 100)
                .tint(Palette.goldDeep)
                .scaleEffect(x: 1, y: 2.4, anchor: .center)
                .padding(.vertical, 12)
                .accessibilityLabel("التقدّم " + ar(Khatma.percent) + "٪")
            HStack(alignment: .top) {
                Text(ar(Khatma.percent) + "٪ مكتمل").font(AppFont.ui(13)).foregroundColor(Palette.muted)
                Spacer()
                Text("الختم المتوقع: " + Khatma.endDateText).font(AppFont.ui(13)).foregroundColor(Palette.muted).multilineTextAlignment(.trailing)
            }
            Text("وصلت إلى: " + Khatma.whereIs(next) + " · صفحة " + ar(next)).font(AppFont.ui(14, 500)).foregroundColor(Palette.ink)
                .padding(.top, 10)
            Text(status).font(AppFont.ui(13, 500)).foregroundColor(ahead >= 0 ? Palette.goldDeep : Palette.muted).padding(.top, 4)
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .card()
    }

    private var todayCard: some View {
        _ = state.rev
        let next = Khatma.nextPage
        return VStack(alignment: .leading, spacing: 0) {
            if !Khatma.readingToday {
                Text("يوم راحة 🌿").font(AppFont.ui(13, 700)).foregroundColor(Palette.gold)
                Text("لا ورد اليوم حسب خطتك").font(AppFont.ui(22, 700)).foregroundColor(.white).padding(.top, 8).padding(.bottom, 4)
                Text("وإن قرأت احتُسب لك وخفّ وردك القادم.").font(AppFont.ui(14)).foregroundColor(Palette.onDarkMuted)
                goldButton("تابع القراءة من صفحة " + ar(next), next)
            } else {
                let r = Khatma.todayRange
                let left = Khatma.todayRemaining
                let fromName = Khatma.surahName(r.0), toName = Khatma.surahName(r.1)
                let open = left == 0 ? next : max(r.0, next)
                Text(left == 0 ? "أتممت ورد اليوم ✓" : "ورد اليوم").font(AppFont.ui(13, 700)).foregroundColor(Palette.gold)
                Text("من صفحة " + ar(r.0) + " إلى " + ar(r.1)).font(AppFont.ui(22, 700)).foregroundColor(.white)
                    .padding(.top, 8).padding(.bottom, 2)
                Text(fromName == toName ? "سورة \(fromName)" : "من سورة \(fromName) إلى سورة \(toName)")
                    .font(AppFont.ui(14, 500)).foregroundColor(Palette.onDarkSoft)
                Text(ar(Khatma.dailyTarget) + " صفحة · " + (left == 0 ? "بارك الله فيك" : "بقي " + ar(left)))
                    .font(AppFont.ui(14)).foregroundColor(Palette.onDarkMuted).padding(.top, 4)
                goldButton(left == 0 ? "تابع القراءة من صفحة " + ar(open) : "افتح المصحف على الصفحة " + ar(open), open)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 18)
        .background(RoundedRectangle(cornerRadius: 20).fill(Palette.dark))
    }

    private func goldButton(_ label: String, _ page: Int) -> some View {
        Button { state.openMushaf(page: page) } label: {
            Text(label).font(AppFont.ui(15, 700)).foregroundColor(Palette.widgetDark)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Capsule().fill(Palette.gold))
        }
        .padding(.top, 14)
    }

    private func note(_ s: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "leaf").foregroundColor(Palette.goldDeep)
            Text(s).font(AppFont.ui(14)).foregroundColor(Palette.ink).lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .card(Palette.ivory, border: Palette.ivoryBorder, radius: 16)
    }

    /** آخر ٧ أيام: ✓ أتم الورد، • قرأ بعضه، — يوم راحة */
    private var week: some View {
        _ = state.rev
        let t = Khatma.today()
        return HStack(spacing: 0) {
            ForEach((t - 6)...t, id: \.self) { d in
                let isToday = d == t
                let off = !Khatma.isReadingDay(d)
                let st = Khatma.dayState(d)
                let mark = st == 2 ? "✓" : (st == 1 ? "•" : (off ? "—" : ""))
                let fg: Color = st == 2 || isToday ? .white : (off ? Palette.muted : Palette.goldDeep)
                let bg: Color = st == 2 ? Palette.goldDeep : (isToday ? Palette.primary : (off ? Palette.page : Palette.chip))
                VStack(spacing: 4) {
                    Text(mark).font(AppFont.ui(13, 700)).foregroundColor(fg)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(bg))
                        .overlay(Circle().stroke(off && !isToday ? Palette.line : Color.clear))
                    Text(Self.dayNames[Khatma.dow(d) - 1]).font(AppFont.ui(11)).foregroundColor(Palette.muted)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 12)
        .card()
    }

    private var planCard: some View {
        _ = state.rev
        let pace = Khatma.pace
        let rem = Reminders.enabled(Reminders.wird) ? Reminders.wirdLabel + (Reminders.followUp ? " + تذكير ثانٍ" : "") : "بلا تذكير"
        return VStack(spacing: 0) {
            infoRow("الورد", "نحو " + ar(pace) + " صفحة يوميًا" + Self.juzHint(pace))
            infoRow("أيام القراءة", Self.daysText(Khatma.offMask))
            infoRow("إن فاتني يوم", Khatma.fixedPace ? "يتمدّد الموعد بنفس الورد" : "يُوزَّع الباقي على الأيام")
            infoRow("التذكير", rem)
            Button { editing = true; setupLoaded = false; loadSetup() } label: { Pill(title: "تعديل الخطة", height: 46) }
                .padding(.top, 12)
        }
        .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 16)
        .card()
    }

    private func infoRow(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).font(AppFont.ui(14)).foregroundColor(Palette.muted).frame(maxWidth: .infinity, alignment: .leading)
            Text(v).font(AppFont.ui(14, 500)).foregroundColor(Palette.ink).multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .layoutPriority(1.8)
        }
        .padding(.vertical, 6)
    }

    private var historyCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(Khatma.history.prefix(5).enumerated()), id: \.offset) { _, e in
                infoRow("ختمة \(Khatma.dateText(e.1))", "خلال \(ar(max(1, e.1 - e.0 + 1))) يومًا")
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .card()
    }

    // MARK: الإعداد

    /** تعبئة الإعداد: من الخطة الحالية عند التعديل، أو بقيم افتراضية */
    private func loadSetup() {
        setupLoaded = true
        customDays = false
        customPpd = false
        var p = Khatma.Plan()
        if editing && Khatma.running {
            p.mode = Khatma.mode
            p.ppd = Khatma.pace
            p.days = max(1, Khatma.endDay - Khatma.today() + 1)
            p.offMask = Khatma.offMask
            p.extend = Khatma.fixedPace && Khatma.mode == Khatma.modeDays
            p.label = Khatma.label
            customDays = true
            customPpd = ![1, 2, 3, 5, 10, 20, 40].contains(p.ppd)
        } else {
            p.mode = Khatma.modeDays
            p.days = 30
            p.ppd = 20
            p.offMask = 0
            p.extend = false
            p.label = "شهر"
            p.startPage = 1
        }
        plan = p
        followUp = Reminders.followUp
        remindTime = Calendar.current.date(bySettingHour: Reminders.hour(Reminders.wird), minute: Reminders.minute(Reminders.wird),
                                           second: 0, of: Date()) ?? Date()
        if !Reminders.enabled(Reminders.wird) && editing { remind = Self.remindNone }
        else if Reminders.byPrayer(Reminders.wird) { remind = Reminders.wirdPrayer }
        else { remind = Geo.has && !editing ? Prayer.isha : Self.remindFixed }
    }

    private var setupCard: some View {
        let remaining = editing ? Khatma.pages - Khatma.read : Khatma.pages
        let pace = plan.pace(remaining: remaining)
        let end = plan.end(remaining: remaining)
        return VStack(alignment: .leading, spacing: 12) {
            if !editing {
                VStack(alignment: .leading, spacing: 0) {
                    Text(Khatma.completed > 0 ? "ختمت القرآن " + ar(Khatma.completed) + " مرة، تقبّل الله منك" : "ابدأ ختمتك")
                        .font(AppFont.ui(13, 700)).foregroundColor(Palette.gold)
                    Text("خطة على مقاسك").font(AppFont.ui(22, 700)).foregroundColor(.white).padding(.top, 8).padding(.bottom, 4)
                    Text("اختر المدة أو الورد اليومي، وأيام قراءتك ووقت تذكيرك، ونحسب لك الباقي.")
                        .font(AppFont.ui(14)).foregroundColor(Palette.onDarkMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 20).fill(Palette.dark))
            }

            VStack(alignment: .leading, spacing: 0) {
                // ١) طريقة الختمة
                label("طريقة الختمة")
                grid(2, [
                    choice("حسب المدة", plan.mode == Khatma.modeDays) { plan.mode = Khatma.modeDays },
                    choice("حسب الورد اليومي", plan.mode == Khatma.modePages) { plan.mode = Khatma.modePages },
                ])

                // ٢) المدة أو الورد
                if plan.mode == Khatma.modeDays {
                    label(editing ? "أختم خلال (من اليوم)" : "أختم خلال")
                    grid(3, daysChoices)
                } else {
                    label("وردي اليومي")
                    grid(3, ppdChoices)
                }

                // ٣) نقطة البداية (للختمة الجديدة)
                if !editing {
                    label("أبدأ من")
                    grid(startChoices.count == 3 ? 3 : 2, startChoices)
                    if plan.startPage > 1 {
                        Text("تبدأ من " + Khatma.whereIs(plan.startPage) + "، وبعد آخر المصحف نكمل من أوله حتى تتم الختمة.")
                            .font(AppFont.ui(12)).foregroundColor(Palette.muted).padding(.top, 6)
                    }
                }

                // ٤) أيام القراءة
                label("أيام القراءة (اضغط لجعل اليوم راحة)")
                grid(4, [7, 1, 2, 3, 4, 5, 6].map { d -> AnyView in
                    let on = (plan.offMask & (1 << d)) == 0
                    return choice(Self.dayNames[d - 1], on) {
                        let m = plan.offMask ^ (1 << d)
                        if m != 0b11111110 { plan.offMask = m }      // يبقى يوم قراءة واحد على الأقل
                    }
                })

                // ٥) سياسة فوات يوم (لوضع المدة)
                if plan.mode == Khatma.modeDays {
                    label("إن فاتني يوم")
                    grid(2, [
                        choice("أزيد وردي لأختم في موعدي", !plan.extend) { plan.extend = false },
                        choice("أمدّد الموعد بنفس الورد", plan.extend) { plan.extend = true },
                    ])
                }

                // ٦) التذكير
                label("ذكّرني بالورد")
                grid(3, remindChoices)
                if remind != Self.remindNone {
                    Toggle(isOn: $followUp) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("تذكير ثانٍ لطيف").font(AppFont.ui(15, 700)).foregroundColor(Palette.ink)
                            Text("بعد ٣ ساعات إن لم تُتمّ وردك، ولا يصل بعد ١١ مساءً").font(AppFont.ui(12)).foregroundColor(Palette.muted)
                        }
                    }
                    .tint(Palette.goldDeep)
                    .padding(.top, 8)
                }
                if !Geo.has {
                    Text("فعّل مواقيت الصلاة من الإعدادات ليصبح التذكير بعد الصلاة متاحًا.")
                        .font(AppFont.ui(12)).foregroundColor(Palette.muted).padding(.top, 6)
                }

                // الملخّص
                Text("وردك نحو \(ar(pace)) صفحة يوميًا\(Self.juzHint(pace))\nتختم بإذن الله يوم \(Khatma.dateText(end))")
                    .font(AppFont.ui(15, 700)).foregroundColor(Palette.ink).lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .card(Palette.ivory, border: Palette.ivoryBorder, radius: 16)
                    .padding(.top, 16)

                Button { commit() } label: { Pill(title: editing ? "احفظ التعديل" : "ابدأ الختمة", primary: true, height: 52) }
                    .padding(.top, 14)
                if editing {
                    Button { editing = false; setupLoaded = false; loadSetup() } label: {
                        Text("إلغاء").font(AppFont.ui(14, 500)).foregroundColor(Palette.muted).frame(maxWidth: .infinity).padding(.top, 14)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 16)
            .card()
        }
    }

    private var daysChoices: [AnyView] {
        var items: [AnyView] = []
        if Ramadan.active() { items.append(dayChoice("حتى آخر رمضان", Ramadan.daysLeftInRamadan())) }
        let ds = [7, 10, 15, 30, 60, 90, 180, 365]
        let ns = ["أسبوع", "١٠ أيام", "١٥ يومًا", "شهر", "شهران", "٣ أشهر", "٦ أشهر", "سنة"]
        for i in 0..<ds.count { items.append(dayChoice(ns[i], ds[i])) }
        items.append(choiceTap(customDays ? ar(plan.days) + " يومًا" : "مدة أخرى…", customDays, tap: {
            askNumber("كم يومًا؟", "من ١ إلى ٧٣٠ يومًا", 1, 730) { v in
                plan.days = v; plan.label = ar(v) + " يومًا"; customDays = true
            }
        }))
        return items
    }

    private var ppdChoices: [AnyView] {
        var items: [AnyView] = []
        let ps = [1, 2, 3, 5, 10, 20, 40]
        let ns = ["صفحة", "صفحتان", "٣ صفحات", "ربع جزء", "نصف جزء", "جزء", "جزءان"]
        for i in 0..<ps.count {
            let p = ps[i], n = ns[i]
            items.append(choice(n, !customPpd && plan.ppd == p) { plan.ppd = p; plan.label = n + " يوميًا"; customPpd = false })
        }
        items.append(choiceTap(customPpd ? ar(plan.ppd) + " صفحة" : "عدد آخر…", customPpd, tap: {
            askNumber("كم صفحة يوميًا؟", "من ١ إلى ١٢٠ صفحة", 1, 120) { v in
                plan.ppd = v; plan.label = ar(v) + " صفحة يوميًا"; customPpd = true
            }
        }))
        return items
    }

    private var startChoices: [AnyView] {
        var items: [AnyView] = [choice("الفاتحة", plan.startPage == 1) { plan.startPage = 1 }]
        let last = Khatma.lastMushafPage()
        if last > 1 { items.append(choice("حيث توقفت · صفحة " + ar(last), plan.startPage == last) { plan.startPage = last }) }
        let other = plan.startPage != 1 && plan.startPage != last
        items.append(choiceTap(other ? "صفحة " + ar(plan.startPage) : "صفحة أخرى…", other, tap: {
            askNumber("من أي صفحة تبدأ؟", "من ١ إلى ٦٠٤", 1, 604) { v in plan.startPage = v }
        }))
        return items
    }

    private var remindChoices: [AnyView] {
        var items: [AnyView] = []
        if Geo.has {
            items.append(choice("بعد الفجر", remind == Prayer.fajr) { remind = Prayer.fajr })
            items.append(choice("بعد العصر", remind == Prayer.asr) { remind = Prayer.asr })
            items.append(choice("بعد العشاء", remind == Prayer.isha) { remind = Prayer.isha })
        }
        items.append(choiceTap(remind == Self.remindFixed ? formatTime(remindTime) : "وقت محدد…", remind == Self.remindFixed, tap: {
            pickTime = true
        }))
        items.append(choice("بلا تذكير", remind == Self.remindNone) { remind = Self.remindNone })
        return items
    }

    private func dayChoice(_ name: String, _ days: Int) -> AnyView {
        choice(name, !customDays && plan.days == days) { plan.days = days; plan.label = name; customDays = false }
    }

    private func commit() {
        if !editing && Khatma.running && Khatma.read > 0 { confirmNew = true } else { commitNow() }
    }

    private func commitNow() {
        if editing && Khatma.running { Khatma.replan(plan) } else { Khatma.start(plan) }
        applyReminder()
        editing = false
        setupLoaded = false
        state.changed()
    }

    private func applyReminder() {
        let c = Calendar.current.dateComponents([.hour, .minute], from: remindTime)
        let h = c.hour ?? 21, m = c.minute ?? 0
        if remind == Self.remindNone {
            Reminders.set(Reminders.wird, on: false, hour: h, minute: m)
            Store.d.set(false, forKey: "wird_follow")
            return
        }
        if remind == Self.remindFixed {
            Store.d.set(-1, forKey: "wird_prayer")
            Reminders.set(Reminders.wird, on: true, hour: h, minute: m)
        } else {
            Store.d.set(remind, forKey: "wird_prayer")
            Store.d.set(true, forKey: "wird_on")
        }
        Store.d.set(followUp, forKey: "wird_follow")
        Task { _ = await Notifications.requestPermission(); state.changed() }
    }

    // MARK: أدوات الواجهة

    /** زر اختيار يفتح نافذة (عدد أو وقت) */
    private func choiceTap(_ s: String, _ selected: Bool, tap: @escaping () -> Void) -> AnyView {
        choiceView(s, selected, tap)
    }

    /** زر اختيار يغيّر الحالة */
    private func choice(_ s: String, _ selected: Bool, _ select: @escaping () -> Void) -> AnyView {
        choiceView(s, selected, select)
    }

    private func choiceView(_ s: String, _ selected: Bool, _ action: @escaping () -> Void) -> AnyView {
        AnyView(
            Button(action: action) {
                Text(s).font(AppFont.ui(13, selected ? 700 : 500))
                    .foregroundColor(selected ? .white : Palette.ink)
                    .multilineTextAlignment(.center).lineLimit(3)
                    .padding(6)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 20).fill(selected ? Palette.primary : Palette.card))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(selected ? Color.clear : Palette.fieldBorder))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(s + (selected ? "، مختار" : ""))
        )
    }

    private func grid(_ cols: Int, _ items: [AnyView]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: cols), spacing: 8) {
            ForEach(0..<items.count, id: \.self) { items[$0] }
        }
    }

    private func label(_ s: String) -> some View {
        Text(s).font(AppFont.ui(14, 700)).foregroundColor(Palette.goldDeep).padding(.horizontal, 2).padding(.top, 16).padding(.bottom, 8)
    }

    private func section(_ s: String) -> some View {
        Text(s).font(AppFont.ui(14, 700)).foregroundColor(Palette.goldDeep).padding(.horizontal, 4)
    }

    private func askNumber(_ title: String, _ hint: String, _ min: Int, _ max: Int, _ done: @escaping (Int) -> Void) {
        askText = ""
        ask = NumberAsk(title: title, hint: hint, min: min, max: max, done: done)
    }

    static func westernDigits(_ s: String) -> String {
        String(s.map { ch -> Character in
            if let v = ch.wholeNumberValue, !ch.isASCII { return Character(String(v)) }
            return ch
        })
    }

    private static func juzHint(_ pace: Int) -> String {
        switch pace {
        case 5: return " (ربع جزء)"
        case 10: return " (نصف جزء)"
        case 20: return " (جزء)"
        case 40: return " (جزءان)"
        default: return ""
        }
    }

    private static func daysText(_ mask: Int) -> String {
        if mask == 0 { return "كل يوم" }
        let days = (1...7).filter { (mask & (1 << $0)) != 0 }.map { dayNames[$0 - 1] }
        return "عدا " + days.joined(separator: " و")
    }
}

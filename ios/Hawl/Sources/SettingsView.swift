import SwiftUI
import UserNotifications

/** الإعدادات والتنبيهات بتصميم هوية الموقع (نفس SettingsActivity؛ notificationsOnly = «الأدوات» ← «التنبيهات») */
struct SettingsView: View {
    var notificationsOnly: Bool
    @EnvironmentObject var state: AppState
    @ObservedObject private var location = LocationService.shared
    @State private var permissionDenied = false
    @State private var editing: TimeEdit?
    @State private var versionTaps = 0
    @State private var showDiag = false
    @State private var now = Date()

    struct TimeEdit: Identifiable { let kind: String; var id: String { kind } }

    private let items: [(String, String, String)] = [
        (Reminders.verse, "آية اليوم", "آية كل صباح مع تفسيرها وزر مشاركتها"),
        (Reminders.wird, "الورد اليومي", "تذكير بقراءة وردك وإكمال ختمتك"),
        (Reminders.azkarAM, "أذكار الصباح", "حصّن يومك بذكر الله"),
        (Reminders.azkarPM, "أذكار المساء", "اختم نهارك بذكر الله"),
        (Reminders.kahf, "سورة الكهف", "كل جمعة، نورٌ لك ما بين الجمعتين"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                remindersSection
                adhanSection
                if !notificationsOnly {
                    readingSection
                    generalSection
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 36)
        }
        .background(Palette.page.ignoresSafeArea())
        .navigationTitle(notificationsOnly ? "التنبيهات" : "الإعدادات")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { e in
            TimePickerSheet(kind: e.kind) { editing = nil }
                .environmentObject(state)
                .environment(\.layoutDirection, .rightToLeft)
                .presentationDetents([.medium])
        }
        .alert("تشخيص صفحة المصحف", isPresented: $showDiag) {
            Button("حسنًا", role: .cancel) { }
        } message: {
            Text(Store.string("bridge_diag", "لا يوجد تشخيص بعد — افتح صفحة من الموقع ثم عد هنا"))
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    // MARK: التذكيرات

    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            section("التذكيرات اليومية")
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, it in
                    if i > 0 { divider }
                    row(it.1, it.2, isOn: reminderBinding(it.0))
                    Button { editing = TimeEdit(kind: it.0) } label: {
                        Text(Reminders.timeLabel(it.0)).font(AppFont.ui(13, 700)).foregroundColor(Palette.ink)
                            .padding(.horizontal, 14).frame(minHeight: 38)
                            .background(Capsule().fill(Palette.chip))
                    }
                    .opacity(state.flag(it.0 + "_on") ? 1 : 0.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 12)
                }
                divider
                row("الأذكار مرتبطة بالصلاة", "الصباح بعد الفجر بربع ساعة، والمساء بعد العصر، حسب مدينتك",
                    isOn: state.toggle("azkar_by_prayer", true, needsNotifications: false))
                divider
                row("تنبيه الإفطار في رمضان", "دعاء الإفطار عند أذان المغرب، يعمل تلقائيًا في رمضان",
                    isOn: state.toggle("iftar_on", true, denied: { permissionDenied = true }))
                divider
                row("أخبار وتنبيهات حول العالم", "ما يرسله صاحب التطبيق من أخبار وتنبيهات",
                    isOn: state.toggle("news_on", true, denied: { permissionDenied = true }))
            }
            .padding(.horizontal, 16)
            .card()
            if permissionDenied { permissionHint }
            Button {
                Task {
                    if await Notifications.requestPermission() {
                        Toast.show("جارٍ جلب آية اليوم…")
                        await Notifications.testVerse()
                    } else { permissionDenied = true }
                }
            } label: {
                Text("جرّب إشعار آية اليوم الآن").font(AppFont.ui(14, 500)).foregroundColor(Palette.goldDeep)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
    }

    private func reminderBinding(_ kind: String) -> Binding<Bool> {
        Binding(get: { state.flag(kind + "_on") }, set: { on in
            if !on { state.setFlag(kind + "_on", false); return }
            Task {
                if await Notifications.requestPermission() {
                    state.setFlag(kind + "_on", true)
                    permissionDenied = false
                    Toast.show(kind == Reminders.kahf ? "سيصلك التذكير كل " + Reminders.timeLabel(kind)
                               : "سيصلك التذكير يوميًا " + (Reminders.byPrayer(kind) ? Reminders.timeLabel(kind) : "الساعة " + Reminders.timeLabel(kind)))
                } else { permissionDenied = true }
            }
        })
    }

    private var permissionHint: some View {
        Button {
            if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
        } label: {
            Text("الإشعارات متوقفة لهذا التطبيق، فعّلها من إعدادات الجوال ›").font(AppFont.ui(13, 700)).foregroundColor(Palette.goldDeep)
                .padding(.top, 10)
        }
    }

    // MARK: الأذان

    private var adhanSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            section("الأذان ومواقيت الصلاة")
            VStack(spacing: 0) {
                row("تنبيه الأذان", "عند دخول كل صلاة مع فضلها، حسب طريقة الحساب أدناه", isOn: adhanBinding)
                if state.flag("adhan_on") { adhanHealth }
                divider
                row("تنبيه الشروق", "انتهاء وقت الفجر، وفضل الجلوس للذكر وصلاة الضحى",
                    isOn: state.toggle("sunrise_on", true, denied: { permissionDenied = true }))
                divider
                row("تذكير الصيام المسنون", "ليلة الاثنين والخميس والأيام البيض وعرفة وعاشوراء",
                    isOn: state.toggle("fasting_on", true, denied: { permissionDenied = true }))
                divider
                HStack {
                    Label(state.hasLocation ? (state.city.isEmpty ? "موقعك الحالي" : state.city) + " · " + hijriToday() : "لم يُحدَّد الموقع بعد",
                          systemImage: "mappin.and.ellipse")
                        .font(AppFont.ui(13)).foregroundColor(Palette.muted).lineLimit(2)
                    Spacer()
                    Button { location.requestLocation() } label: {
                        if location.busy { ProgressView() } else {
                            Text("تحديث الموقع").font(AppFont.ui(13, 700)).foregroundColor(Palette.goldDeep)
                        }
                    }
                    .padding(.vertical, 10)
                }
                if location.denied {
                    Button("نحتاج موقعك لحساب مواقيت الصلاة بدقة — السماح من الإعدادات ›") {
                        if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                    }
                    .font(AppFont.ui(12, 700)).foregroundColor(Palette.goldDeep).padding(.bottom, 8)
                } else if location.failed {
                    Text("تعذّر تحديد الموقع، فعّل خدمة الموقع ثم حاول مرة أخرى").font(AppFont.ui(12)).foregroundColor(Palette.muted)
                        .padding(.bottom, 8)
                }
                prayerGrid.padding(.bottom, 14)
                divider
                NavigationLink { MethodPicker().environmentObject(state) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("طريقة حساب المواقيت").font(AppFont.ui(15, 500)).foregroundColor(Palette.ink)
                            Text((state.calcMethod == 0 ? "تلقائي حسب دولتك · " : "") + Prayer.currentMethod().name + "\n" + Prayer.currentMethod().detail)
                                .font(AppFont.ui(12)).foregroundColor(Palette.muted).multilineTextAlignment(.leading)
                        }
                        Spacer()
                        Text("تغيير ›").font(AppFont.ui(13)).foregroundColor(Palette.muted)
                    }
                    .frame(minHeight: 60)
                }
                divider
                NavigationLink(value: Screen.qibla) {
                    HStack {
                        Label("بوصلة القبلة", systemImage: "location.north.circle").font(AppFont.ui(15, 500)).foregroundColor(Palette.ink)
                        Spacer()
                        Text("افتح ›").font(AppFont.ui(13)).foregroundColor(Palette.muted)
                    }
                    .frame(minHeight: 52)
                }
            }
            .padding(.horizontal, 16)
            .card()
        }
    }

    /** الأذان يحتاج إذن التنبيهات والموقع */
    private var adhanBinding: Binding<Bool> {
        Binding(get: { state.flag("adhan_on") }, set: { on in
            if !on { state.setFlag("adhan_on", false); return }
            Task {
                guard await Notifications.requestPermission() else { permissionDenied = true; return }
                if !state.hasLocation { location.requestLocation() }
                state.setFlag("adhan_on", true)
                Toast.show("تم تفعيل تنبيه الأذان ✓")
            }
        })
    }

    private var adhanHealth: some View {
        let until = Store.d.double(forKey: "notif_until")
        let msg: String
        if !state.hasLocation { msg = "حدّد موقعك ليُجدول الأذان في مدينتك" }
        else if until > 0 {
            msg = "✓ التنبيه مضبوط ليصل في وقته بالدقيقة · مجدول حتى " + hijriShort(Date(timeIntervalSince1970: until))
                + "، ويتجدد كلما فتحت التطبيق"
        } else { msg = "✓ التنبيه مضبوط ليصل في وقته بالدقيقة" }
        return Text(msg).font(AppFont.ui(13, 500)).foregroundColor(msg.hasPrefix("✓") ? Palette.gold : Palette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 10)
    }

    private var prayerGrid: some View {
        Group {
            if state.hasLocation {
                let t = Prayer.times(for: now)
                let prayers = Prayer.alerts
                let next = prayers.firstIndex { t[$0] > now }
                HStack(spacing: 5) {
                    ForEach(Array(prayers.enumerated()), id: \.offset) { k, p in
                        let isNext = k == next
                        VStack(spacing: 4) {
                            Text(Prayer.names[p]).font(AppFont.ui(12, isNext ? 700 : 400))
                                .foregroundColor(isNext ? Color(hex: 0x0E2C31) : Palette.muted)
                            Text(formatClockShort(t[p])).font(AppFont.ui(14, 700))
                                .foregroundColor(isNext ? Color(hex: 0x0E2C31) : Palette.ink)
                        }
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 12).fill(isNext ? Palette.gold : Palette.chip))
                    }
                }
            } else {
                Text("حدّد موقعك لعرض مواقيت الصلاة").font(AppFont.ui(14)).foregroundColor(Palette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: القراءة

    private var readingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            section("القراءة")
            VStack(alignment: .leading, spacing: 0) {
                row("إبقاء الشاشة مضاءة", "لا تنطفئ الشاشة أثناء القراءة والاستماع",
                    isOn: state.toggle("keep_screen", true, needsNotifications: false))
                divider
                Text("حجم الخط: " + ar(state.textZoom) + "٪").font(AppFont.ui(16, 700)).foregroundColor(Palette.ink).padding(.top, 14)
                Text("حجم النص في صفحات القراءة والتفسير").font(AppFont.ui(13)).foregroundColor(Palette.muted)
                Slider(value: Binding(get: { Double(state.textZoom) }, set: { state.textZoom = Int($0) }), in: 80...160, step: 10)
                    .tint(Palette.goldDeep)
                    .accessibilityLabel("حجم الخط")
                    .padding(.bottom, 6)
                divider
                Text("المظهر").font(AppFont.ui(16, 700)).foregroundColor(Palette.ink).padding(.top, 14).padding(.bottom, 10)
                HStack(spacing: 8) {
                    ForEach(Array(["تلقائي", "نهاري", "ليلي"].enumerated()), id: \.offset) { i, n in
                        Button { state.themeMode = i } label: {
                            Text(n).font(AppFont.ui(14, 500)).foregroundColor(state.themeMode == i ? .white : Palette.ink)
                                .frame(maxWidth: .infinity, minHeight: 42)
                                .background(Capsule().fill(state.themeMode == i ? Palette.primary : Palette.card))
                                .overlay(Capsule().stroke(state.themeMode == i ? Color.clear : Palette.fieldBorder))
                        }
                    }
                }
                .padding(.bottom, 14)
            }
            .padding(.horizontal, 16)
            .card()
            Text("أضف ويدجت «آية اليوم» و«مواقيت الصلاة» و«ختمتي» و«رمضان»: اضغط مطولًا على مكان فارغ في الشاشة الرئيسية ← زر + ← حول العالم.")
                .font(AppFont.ui(13)).foregroundColor(Palette.muted).padding(.horizontal, 6).padding(.top, 10)
        }
    }

    // MARK: عام

    private var generalSection: some View {
        VStack(spacing: 10) {
            section("عام").frame(maxWidth: .infinity, alignment: .leading)
            Button { Share.present([state.shareAppText]) } label: {
                Pill(title: "شارك التطبيق مع من تحب", systemImage: "square.and.arrow.up", primary: true, height: 54)
            }
            HStack(spacing: 10) {
                NavigationLink(value: Screen.web(Links.contact, "أرسل ملاحظة")) { Pill(title: "أرسل ملاحظة", systemImage: "envelope", height: 50) }
                Button { state.showTour = true } label: { Pill(title: "جولة في المميزات", systemImage: "sparkles", height: 50) }
            }
            Text("✦  الإصدار " + ar(WebConfig.version) + "  ✦").font(AppFont.ui(13, 500)).foregroundColor(Palette.muted)
                .padding(.top, 20)
                .onTapGesture {
                    // لصاحب الموقع: ٧ لمسات تستبعد زيارات هذا الجوال من الإحصاءات
                    versionTaps += 1
                    if versionTaps < 7 { return }
                    versionTaps = 0
                    let on = !Store.bool("internal_device", false)
                    Store.d.set(on, forKey: "internal_device")
                    Toast.show(on ? "تم: زيارات هذا الجوال لن تُحسب في الإحصاءات" : "عادت زيارات هذا الجوال تُحسب في الإحصاءات")
                }
                .onLongPressGesture { showDiag = true }
            NavigationLink(value: Screen.web(Links.privacy, "سياسة الخصوصية")) {
                Text("سياسة الخصوصية").font(AppFont.ui(13, 700)).foregroundColor(Palette.goldDeep)
            }
            Text("صدقة جارية لمحمد بن مفرح الشهري رحمه الله، ولموتى المسلمين").font(AppFont.ui(12)).foregroundColor(Palette.muted)
                .multilineTextAlignment(.center)
        }
        .buttonStyle(.plain)
    }

    // MARK: أدوات

    private func section(_ s: String) -> some View {
        Text(s).font(AppFont.ui(13, 700)).foregroundColor(Palette.goldDeep).padding(.horizontal, 6).padding(.top, 24).padding(.bottom, 10)
    }

    private var divider: some View { Rectangle().fill(Palette.divider).frame(height: 1) }

    private func row(_ title: String, _ sub: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(AppFont.ui(16, 700)).foregroundColor(Palette.ink)
                Text(sub).font(AppFont.ui(13)).foregroundColor(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Palette.goldDeep)
        .padding(.vertical, 12)
    }
}

/** اختيار وقت التذكير */
private struct TimePickerSheet: View {
    let kind: String
    var done: () -> Void
    @EnvironmentObject var state: AppState
    @State private var time = Date()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if Reminders.byPrayer(kind) && kind != Reminders.wird {
                    Text("الوقت مرتبط بالصلاة. أطفئ «الأذكار مرتبطة بالصلاة» لتحديد وقت ثابت.")
                        .font(AppFont.ui(14)).foregroundColor(Palette.muted).multilineTextAlignment(.center).padding()
                } else {
                    DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .environment(\.locale, Locale(identifier: "ar"))
                }
            }
            .padding()
            .navigationTitle("وقت التذكير")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") {
                        if !(Reminders.byPrayer(kind) && kind != Reminders.wird) {
                            let c = Calendar.current.dateComponents([.hour, .minute], from: time)
                            if kind == Reminders.wird { Store.d.set(-1, forKey: "wird_prayer") }   // وقت ثابت بدل الصلاة
                            Task {
                                if await Notifications.requestPermission() {
                                    Reminders.set(kind, on: true, hour: c.hour ?? 7, minute: c.minute ?? 0)
                                    state.changed()
                                }
                            }
                        }
                        done()
                    }
                    .font(AppFont.ui(15, 700))
                }
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { done() }.font(AppFont.ui(15)) }
            }
            .onAppear {
                time = Calendar.current.date(bySettingHour: Reminders.hour(kind), minute: Reminders.minute(kind), second: 0, of: Date()) ?? Date()
            }
        }
    }
}

/** طريقة حساب المواقيت: تلقائية حسب الدولة أو يدوية */
private struct MethodPicker: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(0..<Prayer.methods.count, id: \.self) { i in
                Button {
                    state.calcMethod = i
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(i == 0 ? "تلقائي حسب دولتك (" + (Prayer.methods[Prayer.forCountry(Prayer.country())]?.name ?? "") + ")"
                                 : Prayer.methods[i]?.name ?? "")
                                .font(AppFont.ui(15, 500)).foregroundColor(Palette.ink)
                            if let m = Prayer.methods[i] { Text(m.detail).font(AppFont.ui(12)).foregroundColor(Palette.muted) }
                        }
                        Spacer()
                        if state.calcMethod == i { Image(systemName: "checkmark").foregroundColor(Palette.goldDeep) }
                    }
                }
            }
        }
        .navigationTitle("طريقة حساب المواقيت")
        .navigationBarTitleDisplayMode(.inline)
    }
}

import SwiftUI

@main
struct HawlApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState.shared
    @Environment(\.scenePhase) private var phase
    static var routeOpened = false

    init() {
        // شريط التبويب بخط التطبيق وألوانه
        let item = UITabBarItemAppearance()
        let f = UIFont(name: "Tajawal-Medium", size: 11) ?? .systemFont(ofSize: 11)
        let gold = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0xC9A876) : UIColor(hex: 0x9A7332) }
        let muted = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x8FA6AC) : UIColor(hex: 0x5D747C) }
        item.normal.titleTextAttributes = [.font: f, .foregroundColor: muted]
        item.normal.iconColor = muted
        item.selected.titleTextAttributes = [.font: f, .foregroundColor: gold]
        item.selected.iconColor = gold
        let tab = UITabBarAppearance()
        tab.configureWithDefaultBackground()
        tab.stackedLayoutAppearance = item
        tab.inlineLayoutAppearance = item
        tab.compactInlineLayoutAppearance = item
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        let nav = UINavigationBarAppearance()
        nav.configureWithDefaultBackground()
        if let t = UIFont(name: "Tajawal-Bold", size: 17) { nav.titleTextAttributes = [.font: t] }
        if let t = UIFont(name: "Tajawal-Bold", size: 30) { nav.largeTitleTextAttributes = [.font: t] }
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        WebConfig.prepareRules()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar"))
                .preferredColorScheme(state.colorScheme)
                .tint(Palette.goldDeep)
                .onOpenURL { url in state.open(url) }
        }
        .onChange(of: phase) { p in
            if p == .active { becameActive() }
            if p == .background { Background.schedule() }
        }
    }

    private func becameActive() {
        Task { await state.refreshVerse() }
        state.changed()                              // نجدد التنبيهات القادمة ونحدّث الويدجت كلما فُتح التطبيق
        Announce.checkSoon()
        LocationService.shared.refreshIfStale()
        if let s = AppDelegate.pendingShortcut, let u = URL(string: s) {
            AppDelegate.pendingShortcut = nil
            state.handleDeepLink(u)
        }
        // لقطات المتجر الآلية: تُفتح الشاشة مباشرة من وسيط التشغيل (-open_route khatma) دون نافذة «فتح في…؟»
        if !HawlApp.routeOpened, let r = UserDefaults.standard.string(forKey: "open_route"), !r.isEmpty,
           let u = URL(string: "hawlapp://" + r) {
            HawlApp.routeOpened = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { state.handleDeepLink(u) }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        TabView(selection: $state.tab) {
            NavigationStack(path: $state.todayPath) {
                TodayView().navigationDestination(for: Screen.self) { ScreenView(screen: $0) }
            }
            .tabItem { Label("اليوم", systemImage: "house") }
            .tag(AppState.Tab.today)

            NavigationStack { MushafScreen() }
                .tabItem { Label("المصحف", systemImage: "book") }
                .tag(AppState.Tab.mushaf)

            NavigationStack { ListenScreen() }
                .tabItem { Label("الاستماع", systemImage: "headphones") }
                .tag(AppState.Tab.listen)

            NavigationStack(path: $state.toolsPath) {
                ToolsView().navigationDestination(for: Screen.self) { ScreenView(screen: $0) }
            }
            .tabItem { Label("الأدوات", systemImage: "square.grid.2x2") }
            .tag(AppState.Tab.tools)
        }
        .overlay { ToastOverlay() }
        .sheet(isPresented: $state.showPrayerAzkar) {
            NavigationStack { PrayerAzkarView() }
                .environment(\.layoutDirection, .rightToLeft)
        }
        .fullScreenCover(isPresented: $state.showWelcome) {
            WelcomeView()
                .environmentObject(state)
                .environment(\.layoutDirection, .rightToLeft)
        }
        .sheet(isPresented: $state.showTour) {
            FeaturesView()
                .environment(\.layoutDirection, .rightToLeft)
        }
    }
}

/** الشاشة المطلوبة بالقيمة (من الروابط والإشعارات والويدجت) */
struct ScreenView: View {
    let screen: Screen

    var body: some View {
        switch screen {
        case .web(let url, let title): WebScreen(title: title, url: url)
        case .khatma: KhatmaView()
        case .settings: SettingsView(notificationsOnly: false)
        case .notifications: SettingsView(notificationsOnly: true)
        case .qibla: QiblaView()
        case .tasbeeh: TasbeehView()
        case .mood(let m): MoodView(initial: m)
        case .downloads: DownloadsView()
        case .prayerTimes: PrayerTimesView()
        case .index: IndexView()
        case .prayerAzkar: PrayerAzkarView()
        case .dedicate: DedicateView()
        case .player(let url): PlayerView(url: url)
        }
    }
}

/** تبويب المصحف: الصفحة المطلوبة أو حيث توقف القارئ */
struct MushafScreen: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var page: Int = 0

    var body: some View {
        // الصفحة تُحدَّد مرة عند الفتح أو عند طلب صريح (الفهرس، «أكمل القراءة»)؛ التنقل داخل المصحف لا يعيد تحميله
        MushafWebView(page: page == 0 ? Khatma.lastMushafPage() : page, night: scheme == .dark, zoom: state.textZoom)
            .background(Palette.page.ignoresSafeArea())
            .navigationTitle("المصحف")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink { IndexView() } label: {
                        Label("الفهرس", systemImage: "list.bullet").labelStyle(.titleAndIcon).font(AppFont.ui(15, 700))
                    }
                }
            }
            .keepScreenOn()
            .onAppear {
                if page == 0 { page = Khatma.lastMushafPage() }
                consumeRequest()
            }
            .onChange(of: state.mushafRequest) { _ in consumeRequest() }
    }

    private func consumeRequest() {
        if let p = state.mushafRequest {
            page = p
            state.mushafRequest = nil
        }
    }
}

/** تبويب الاستماع: صفحة القرّاء في الموقع */
struct ListenScreen: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        WebScreen(title: "الاستماع", url: state.listenRequest ?? Links.reciters)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink { DownloadsView() } label: {
                        Label("المحمّلة", systemImage: "arrow.down.circle").labelStyle(.titleAndIcon).font(AppFont.ui(14, 700))
                    }
                }
            }
    }
}

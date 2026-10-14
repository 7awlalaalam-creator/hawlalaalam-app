import SwiftUI

@main
struct HawlApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState.shared
    @Environment(\.scenePhase) private var phase

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
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar"))
                .preferredColorScheme(state.colorScheme)
                .tint(Palette.goldDeep)
        }
        .onChange(of: phase) { p in
            if p == .active {
                Task { await state.refreshVerse() }
                Notifications.reschedule()                 // نجدد أيام الأذان السبعة كلما فُتح التطبيق
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        TabView(selection: $state.tab) {
            NavigationStack { TodayView() }
                .tabItem { Label("اليوم", systemImage: "house") }
                .tag(AppState.Tab.today)
            NavigationStack { MushafScreen() }
                .tabItem { Label("المصحف", systemImage: "book") }
                .tag(AppState.Tab.mushaf)
            NavigationStack { WebScreen(title: "الاستماع", url: URL(string: "https://7awlalaalam.com/quran/quran-reciters-ar.html")!) }
                .tabItem { Label("الاستماع", systemImage: "headphones") }
                .tag(AppState.Tab.listen)
            NavigationStack { ToolsView() }
                .tabItem { Label("الأدوات", systemImage: "square.grid.2x2") }
                .tag(AppState.Tab.tools)
        }
        .sheet(isPresented: $state.showPrayerAzkar) {
            NavigationStack { PrayerAzkarView() }
                .environment(\.layoutDirection, .rightToLeft)
        }
    }
}

/** تبويب المصحف: الصفحة المطلوبة أو آخر صفحة قُرئت */
struct MushafScreen: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var page: Int = 0

    var body: some View {
        // الصفحة تُحدَّد مرة عند الفتح أو عند طلب صريح (الفهرس، «أكمل القراءة»)؛
        // التنقل داخل المصحف لا يعيد تحميله
        MushafWebView(page: page == 0 ? max(1, state.lastPage) : page, night: scheme == .dark)
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
            .onAppear {
                if page == 0 { page = max(1, state.lastPage) }
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

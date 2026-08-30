import SwiftUI

/// 全局页面路由：跨 Tab 导航（首页"开始拍摄"→相机、"查看全部"→图库等）。
/// 之前的做法是发 NotificationCenter 通知——但全工程没有任何监听者，
/// 首页按钮点了没反应。Router 是可观察的真状态源，注入环境后任何页面可用。
@MainActor
final class AppRouter: ObservableObject {
    @Published var selectedTab: MainTabView.Tab = .home

    func openCamera() { selectedTab = .camera }
    func openGallery() { selectedTab = .gallery }
    func openSettings() { selectedTab = .settings }
}

struct MainTabView: View {
    @AppStorage("detectionMode") private var detectionMode: DetectionMode = .fast
    @AppStorage("autoCaptureEnabled") private var autoCaptureEnabled = false  // §12：MVP 默认手动拍摄，自动拍照作为可选开关
    @AppStorage("captureDelay") private var captureDelay: Double = 1.0
    @AppStorage("colorScheme") private var colorScheme: String = "system"
    @AppStorage("aiAdviceEnabled") private var aiAdviceEnabled: Bool = false
    @StateObject private var router = AppRouter()
    @State private var showCapture = false

    enum Tab: String, Hashable {
        case gallery, home, settings, camera
    }

    private var resolvedScheme: ColorScheme? {
        switch colorScheme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some View {
        TabView(selection: $router.selectedTab) {
            HomeView()
                .tabItem {
                    Label("首页", systemImage: "house.fill")
                }
                .tag(Tab.home)

            GalleryView()
                .tabItem {
                    Label("图库", systemImage: router.selectedTab == .gallery ? "photo.on.rectangle.fill" : "photo.on.rectangle")
                }
                .tag(Tab.gallery)

            Color.clear
                .tabItem {
                    Image(systemName: "camera.fill")
                        .environment(\.symbolVariants, .none)
                    Text("拍摄")
                }
                .tag(Tab.camera)

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: router.selectedTab == .settings ? "gearshape.fill" : "gearshape")
                }
                .tag(Tab.settings)
        }
        .tint(DesignSystem.Colors.primary)
        .preferredColorScheme(resolvedScheme)
        .environmentObject(router)
        .onAppear {
            PhotoStorageService.shared.loadRecordsIfNeeded()
        }
        .onChange(of: router.selectedTab) { _, newTab in
            if newTab == .camera {
                showCapture = true
                DispatchQueue.main.async {
                    router.selectedTab = .home
                }
            }
        }
        .fullScreenCover(isPresented: $showCapture) {
            CaptureView(
                detectionMode: detectionMode,
                isAutoCaptureEnabled: autoCaptureEnabled,
                captureDelay: captureDelay
            )
            .preferredColorScheme(.dark)
        }
    }
}

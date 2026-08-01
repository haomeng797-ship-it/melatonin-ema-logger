import SwiftUI
import UserNotifications

/// 接管通知的前台展示与点击跳转。
///
/// 用单例 + AppDelegate 注册，而不是在视图的 .task 里注册：如果 app 是被
/// 通知点击冷启动的，系统会在启动瞬间投递回调，那时视图还不存在。
/// 在 .task 里注册意味着这一路径的回调会被静默丢弃。
@Observable
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    /// 点击通知后置为 true，界面据此弹出快速记录卡
    var openQuickEntry = false

    // app 在前台时也显示横幅，否则测试时会误以为通知没发出去
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    // 用户点了通知：直接进入快速记录，不让他先看一整屏设置
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run { openQuickEntry = true }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 启动最早期就接管，冷启动路径才不会丢回调
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        return true
    }
}

@main
struct EMALoggerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView(router: NotificationRouter.shared)
        }
    }
}

import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingManualLogin = false
    @State private var showingQRCodeLogin = false
    /// 任务流视觉 Demo 的临时入口（demo 分支专用，不进 main）。
    @State private var showingFlowDemo = false

    var body: some View {
        Group {
            switch appState.route {
            case .loading:
                Color(uiColor: .systemBackground)
            case .signedOut:
                ServiceEntryView(
                    onManualLogin: { showingManualLogin = true },
                    onQRCodeLogin: { showingQRCodeLogin = true },
                )
            case .signedIn:
                ChatShellView()
            }
        }
        // 视觉 Demo 的调试入口：与登录态无关，点按钮打开，方便在模拟器/真机上随时对照。
        .overlay(alignment: .bottomTrailing) {
            Button {
                showingFlowDemo = true
            } label: {
                Label("任务流 Demo", systemImage: "square.grid.3x3")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.black.opacity(0.08), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 16)
            .padding(.bottom, 156)
        }
        // 带 --flow-demo 启动参数时直接进入 Demo，方便截图与录屏验证；
        // 正常启动仍然只显示右下角的入口按钮。
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("--flow-demo") {
                showingFlowDemo = true
            }
        }
        .sheet(isPresented: $showingFlowDemo) {
            SpecRuneFlowDemoView()
        }
        .sheet(isPresented: $showingManualLogin) {
            ManualLoginView(appState: appState) {
                appState.activateSignedInRoute()
                showingManualLogin = false
            }
        }
        .sheet(isPresented: $showingQRCodeLogin) {
            QRCodeLoginView(appState: appState) {
                appState.activateSignedInRoute()
                showingQRCodeLogin = false
            }
        }
        .announcementGate(
            server: appState.serverURL,
            route: appState.route,
            blocked: showingManualLogin || showingQRCodeLogin
        )
        .overlay(alignment: .top) {
            if appState.route == .signedIn, let error = appState.restoreConnectionError {
                HStack(spacing: 12) {
                    AppSymbol("wifi.exclamationmark")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "暂时无法连接，正在显示本地内容")).font(.footnote.weight(.medium))
                        Text(error).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Menu {
                        Button(String(localized: "立即重试"), action: retryServerConnection)
                        Button(String(localized: "返回登录"), action: appState.returnToLogin)
                    } label: { AppSymbol("ellipsis").frame(width: 36, height: 36) }
                }
                .padding(14).glassEffect(.regular, in: .rect(cornerRadius: 20))
                .padding(.horizontal, 22).padding(.top, 70).frame(maxWidth: 540)
            }
        }
        .tint(AppTheme.primaryText(colorScheme))
        .background(AppTheme.appBackground(colorScheme))
    }

    private func retryServerConnection() {
        Task {
            await appState.retryServerConnection()
        }
    }
}

#Preview {
    RootView()
        .environment(AppState())
}

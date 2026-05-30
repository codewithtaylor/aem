import SwiftUI
import WebKit
import UIKit

struct WebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.websiteDataStore = WKWebsiteDataStore.default()
        let handler = WeakScriptHandler(context.coordinator)
        config.userContentController.add(handler, name: "share")
        config.userContentController.add(handler, name: "exportJSON")
        config.userContentController.add(handler, name: "haptic")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.bounces = true
        webView.allowsBackForwardNavigationGestures = false
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        if let url = Bundle.main.url(forResource: "index", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class WeakScriptHandler: NSObject, WKScriptMessageHandler {
        weak var delegate: WKScriptMessageHandler?
        init(_ delegate: WKScriptMessageHandler) { self.delegate = delegate }
        func userContentController(_ c: WKUserContentController, didReceive msg: WKScriptMessage) {
            delegate?.userContentController(c, didReceive: msg)
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated,
               let url = action.request.url,
               url.scheme != "file" {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }

            if message.name == "share", let text = body["text"] as? String {
                present(items: [text])
            } else if message.name == "exportJSON",
                      let json = body["json"] as? String,
                      let filename = body["filename"] as? String {
                let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                try? json.write(to: tmpURL, atomically: true, encoding: .utf8)
                present(items: [tmpURL])
            } else if message.name == "haptic", let type = body["type"] as? String {
                DispatchQueue.main.async { Self.fireHaptic(type) }
            }
        }

        private static func fireHaptic(_ type: String) {
            switch type {
            case "light":   UIImpactFeedbackGenerator(style: .light).impactOccurred()
            case "medium":  UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            case "rigid":   UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            case "success": UINotificationFeedbackGenerator().notificationOccurred(.success)
            case "warning": UINotificationFeedbackGenerator().notificationOccurred(.warning)
            default: break
            }
        }

        private func present(items: [Any]) {
            DispatchQueue.main.async {
                guard let wv = self.webView,
                      let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                      let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return }

                let av = UIActivityViewController(activityItems: items, applicationActivities: nil)
                av.popoverPresentationController?.sourceView = wv
                av.popoverPresentationController?.sourceRect = CGRect(
                    x: wv.bounds.midX, y: wv.bounds.midY, width: 0, height: 0
                )
                root.present(av, animated: true)
            }
        }
    }
}

import SwiftUI
import WebKit

struct VditorWebEditorView: NSViewRepresentable {
    @Binding var text: String
    var command: VditorEditorCommand?
    var baseFontSize: Double
    var onChange: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "editor")
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView

        if let editorURL = Bundle.module.url(
            forResource: "index",
            withExtension: "html",
            subdirectory: "vditor-editor"
        ), let resourceURL = Bundle.module.resourceURL {
            webView.loadFileURL(editorURL, allowingReadAccessTo: resourceURL)
        } else {
            webView.loadHTMLString(
                "<html><body style=\"font-family:-apple-system;padding:24px\">Vditor 资源未找到</body></html>",
                baseURL: nil
            )
        }

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applyFontSize(baseFontSize)
        context.coordinator.applyTextIfNeeded(text)
        context.coordinator.applyCommandIfNeeded(command)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: VditorWebEditorView
        weak var webView: WKWebView?
        private var isReady = false
        private var lastAppliedText: String?
        private var lastFontSize: Double?
        private var lastCommandID: UUID?

        init(_ parent: VditorWebEditorView) {
            self.parent = parent
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "editor",
                  let payload = message.body as? [String: Any],
                  let type = payload["type"] as? String
            else { return }

            if type == "ready" {
                isReady = true
                applyFontSize(parent.baseFontSize)
                applyTextIfNeeded(parent.text, force: true)
                return
            }

            if type == "change", let value = payload["value"] as? String {
                lastAppliedText = value
                parent.text = value
                parent.onChange(value)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            applyFontSize(parent.baseFontSize)
        }

        func applyTextIfNeeded(_ value: String, force: Bool = false) {
            guard isReady else {
                lastAppliedText = nil
                return
            }
            guard force || lastAppliedText != value else { return }
            lastAppliedText = value
            evaluate("window.setMarkdown(\(value.javaScriptStringLiteral));")
        }

        func applyFontSize(_ value: Double) {
            guard isReady, lastFontSize != value else { return }
            lastFontSize = value
            evaluate("window.setEditorOptions({ fontSize: \(value) });")
        }

        func applyCommandIfNeeded(_ command: VditorEditorCommand?) {
            guard isReady,
                  let command,
                  lastCommandID != command.id
            else { return }
            lastCommandID = command.id
            evaluate("window.runModuCommand(\(command.javaScriptPayload));")
        }

        private func evaluate(_ script: String) {
            webView?.evaluateJavaScript(script) { _, error in
                if let error {
                    NSLog("Vditor evaluateJavaScript failed: %@", error.localizedDescription)
                }
            }
        }
    }
}

struct VditorEditorCommand: Equatable {
    let id = UUID()
    let kind: String
    let prefix: String
    let suffix: String
    let text: String
    let placeholder: String

    static func wrap(prefix: String, suffix: String, placeholder: String) -> VditorEditorCommand {
        VditorEditorCommand(
            kind: "wrap",
            prefix: prefix,
            suffix: suffix,
            text: "",
            placeholder: placeholder
        )
    }

    static func line(prefix: String, placeholder: String) -> VditorEditorCommand {
        VditorEditorCommand(
            kind: "line",
            prefix: prefix,
            suffix: "",
            text: "",
            placeholder: placeholder
        )
    }

    static func insert(_ text: String) -> VditorEditorCommand {
        VditorEditorCommand(
            kind: "insert",
            prefix: "",
            suffix: "",
            text: text,
            placeholder: ""
        )
    }

    static func scrollToHeading(_ title: String) -> VditorEditorCommand {
        VditorEditorCommand(
            kind: "scrollToHeading",
            prefix: "",
            suffix: "",
            text: title,
            placeholder: ""
        )
    }

    var javaScriptPayload: String {
        let payload = [
            "id": id.uuidString,
            "kind": kind,
            "prefix": prefix,
            "suffix": suffix,
            "text": text,
            "placeholder": placeholder,
        ]
        guard let data = try? JSONEncoder().encode(payload),
              let encoded = String(data: data, encoding: .utf8)
        else { return "{}" }
        return encoded
    }
}

private extension String {
    var javaScriptStringLiteral: String {
        guard let data = try? JSONEncoder().encode(self),
              let encoded = String(data: data, encoding: .utf8)
        else { return "\"\"" }
        return encoded
    }
}

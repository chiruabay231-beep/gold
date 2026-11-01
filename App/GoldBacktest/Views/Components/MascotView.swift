import SwiftUI
import WebKit

/// One animated mascot picture (an SVG from the app's resources), on a clear background.
/// SwiftUI cannot play SVG animations, so a small web view shows it; it takes no touches.
struct MascotView: UIViewRepresentable {
    /// Resource name without the extension, e.g. "girl-happy".
    let picture: String

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.isUserInteractionEnabled = false
        load(view, context: context)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        if context.coordinator.shown != picture { load(view, context: context) }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator { var shown = "" }

    private func load(_ view: WKWebView, context: Context) {
        context.coordinator.shown = picture
        guard let url = Bundle.main.url(forResource: picture, withExtension: "svg") else { return }
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;height:100%;background:transparent;overflow:hidden}img{width:100%;height:100%;object-fit:contain;display:block}</style>
        </head><body><img src="\(url.lastPathComponent)"></body></html>
        """
        view.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
    }
}

// SPDX-License-Identifier: MIT
import AppKit
import Observation
import SwiftUI
import WebKit
import X1ScanCore

/// The built-in help (Help > X1 Scan Help, ⌘?): the pages of docs/help in
/// the application's language, a list of pages or of search results, and
/// the page shown. The Markdown is turned into HTML when a page is shown
/// (docs/decisions.md, "Built-in help").
@MainActor
@Observable
final class HelpModel {
    let library: HelpLibrary?
    /// Why the help could not be loaded, when it could not.
    let loadError: String?
    private(set) var pageID: String
    /// Scrolled to once the page is shown, then cleared.
    private(set) var anchor: String?
    /// Increases at each `open`, so that opening the same page again scrolls again.
    private(set) var revision = 0
    var query = ""

    init(library: Result<HelpLibrary, any Error>) {
        switch library {
        case .success(let loaded):
            self.library = loaded
            loadError = nil
        case .failure(let error):
            self.library = nil
            loadError = String(describing: error)
        }
        pageID = HelpLibrary.pageIDs[0]
    }

    /// The help of the application's language, from the copy of docs/help in its resources.
    static func load(bundle: Bundle = .main) -> Result<HelpLibrary, any Error> {
        Result {
            guard let directory = bundle.resourceURL?.appending(path: "help") else { throw CocoaError(.fileNoSuchFile) }
            return try HelpLibrary(directory: directory, language: HelpLibrary.language(for: bundle.preferredLocalizations),
                                   shortcuts: Strings.helpShortcutsTable)
        }
    }

    var results: [HelpSearchResult] { library?.search(query) ?? [] }

    func open(page: String, anchor: String? = nil) {
        guard library?.page(page) != nil else { return }
        selectedResult = nil
        pageID = page
        self.anchor = anchor
        revision += 1
    }

    /// The search result shown last (the results list's selection).
    private(set) var selectedResult: HelpSearchResult?

    func open(_ result: HelpSearchResult) {
        open(page: result.pageID, anchor: result.anchor)
        selectedResult = result
    }

    func anchorShown() { anchor = nil }

    /// A link clicked in a page: another page of the help, or a web address.
    func follow(_ url: URL) {
        if url.scheme == HelpWebView.scheme {
            var target = url.path(percentEncoded: false)
            if target.hasPrefix("/") { target.removeFirst() }
            if let fragment = url.fragment(percentEncoded: false) { target += "#" + fragment }
            if let place = HelpLibrary.resolve(target, from: pageID) { open(page: place.page, anchor: place.anchor) }
        } else if url.scheme == "https" || url.scheme == "http" {
            NSWorkspace.shared.open(url)
        }
    }
}

@MainActor
final class HelpWindowController: NSWindowController {
    let model: HelpModel

    init(model: HelpModel) {
        self.model = model
        let hosting = NSHostingController(rootView: HelpView(model: model))
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "help.window.title", defaultValue: "X1 Scan Help", comment: "Title of the built-in help's window")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 860, height: 600))
        window.minSize = NSSize(width: 560, height: 360)
        window.setFrameAutosaveName("HelpWindow")
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func show(page: String, anchor: String? = nil) {
        model.open(page: page, anchor: anchor)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct HelpView: View {
    @Bindable var model: HelpModel

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            if let library = model.library, let html = library.html(for: model.pageID, iconURL: { HelpIcons.dataURL($0) }) {
                HelpWebView(html: html, anchor: model.anchor, revision: model.revision,
                            follow: { model.follow($0) }, anchorShown: { model.anchorShown() })
            } else {
                ContentUnavailableView(String(localized: "The help could not be loaded.", comment: "Help window: the pages are missing from the application"),
                                       systemImage: "questionmark.circle", description: Text(model.loadError ?? ""))
            }
        }
        .searchable(text: $model.query, placement: .sidebar,
                    prompt: Text("Search the help", comment: "Placeholder of the help window's search field"))
    }

    @ViewBuilder private var sidebar: some View {
        if model.query.trimmingCharacters(in: .whitespaces).isEmpty {
            List(model.library?.pages ?? [], id: \.id, selection: pageSelection) { page in
                Text(page.title).tag(page.id)
            }
        } else if model.results.isEmpty {
            ContentUnavailableView.search(text: model.query)
        } else {
            // A selection, so that the arrows and Return go through the results.
            List(model.results, id: \.self, selection: resultSelection) { result in
                VStack(alignment: .leading, spacing: 1) {
                    Text(result.title)
                    if result.title != result.pageTitle {
                        Text(result.pageTitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .tag(result)
            }
        }
    }

    private var resultSelection: Binding<HelpSearchResult?> {
        Binding(get: { model.selectedResult },
                set: { if let result = $0 { model.open(result) } })
    }

    private var pageSelection: Binding<String?> {
        Binding(get: { model.pageID }, set: { if let id = $0 { model.open(page: id) } })
    }
}

/// The page, in a web view that follows the light or dark appearance.
/// Links between pages (`crop.md#frame`) are opened by the help model,
/// never loaded by the web view.
struct HelpWebView: NSViewRepresentable {
    /// The base of the pages: relative links resolve to `x1help://help/<page>.md#anchor`.
    static let scheme = "x1help"
    static let base = URL(string: "x1help://help/")!

    var html: String
    var anchor: String?
    var revision: Int
    var follow: (URL) -> Void
    var anchorShown: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        view.navigationDelegate = context.coordinator
        view.underPageBackgroundColor = .textBackgroundColor
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.follow = follow
        coordinator.anchorShown = anchorShown
        coordinator.anchor = anchor
        if coordinator.html != html {
            coordinator.html = html
            view.loadHTMLString(html, baseURL: Self.base)
        } else if coordinator.revision != revision {
            coordinator.scroll(view)
        }
        coordinator.revision = revision
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var html: String?
        var anchor: String?
        var revision = -1
        var follow: (URL) -> Void = { _ in }
        var anchorShown: () -> Void = {}

        func scroll(_ view: WKWebView) {
            let script: String
            if let anchor {
                // The anchor is a plain id from the page's own Markdown; quoted as a JSON string.
                let quoted = (try? String(data: JSONEncoder().encode(anchor), encoding: .utf8)) ?? "\"\""
                script = "var e = document.getElementById(\(quoted)); if (e) { e.scrollIntoView(); } else { window.scrollTo(0, 0); }"
            } else {
                script = "window.scrollTo(0, 0);"
            }
            view.evaluateJavaScript(script, completionHandler: nil)
            anchorShown()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            scroll(webView)
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            // The page itself, loaded from its HTML; every click is handled by the model.
            guard action.navigationType == .linkActivated, let url = action.request.url else {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            follow(url)
        }
    }
}

/// The help's pages in the results of the Help menu's search field
/// (`NSUserInterfaceItemSearching`), under the menu commands: choosing one
/// opens the help window at that place.
final class HelpSearch: NSObject, NSUserInterfaceItemSearching, @unchecked Sendable {
    /// Immutable after init; read from the search thread AppKit chooses.
    private let library: HelpLibrary
    private let open: @MainActor (HelpSearchResult) -> Void
    private let openAll: @MainActor (String) -> Void

    init(library: HelpLibrary, open: @escaping @MainActor (HelpSearchResult) -> Void,
         openAll: @escaping @MainActor (String) -> Void) {
        self.library = library
        self.open = open
        self.openAll = openAll
    }

    func searchForItems(withSearch searchString: String, resultLimit: Int,
                        matchedItemHandler handleMatchedItems: @escaping ([Any]) -> Void) {
        handleMatchedItems(library.search(searchString, limit: resultLimit))
    }

    func localizedTitles(forItem item: Any) -> [String] {
        guard let result = item as? HelpSearchResult else { return [] }
        return [result.title == result.pageTitle ? result.title : "\(result.title) — \(result.pageTitle)"]
    }

    func performAction(forItem item: Any) {
        guard let result = item as? HelpSearchResult else { return }
        let open = open
        Task { @MainActor in open(result) }
    }

    func showAllHelpTopics(forSearch searchString: String) {
        let openAll = openAll
        Task { @MainActor in openAll(searchString) }
    }
}

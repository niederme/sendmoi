import SwiftUI

#if os(iOS)
import UIKit
typealias PlatformViewController = UIViewController
typealias PlatformHostingController<Content: View> = UIHostingController<Content>
#elseif os(macOS)
import AppKit
typealias PlatformViewController = NSViewController
typealias PlatformHostingController<Content: View> = NSHostingController<Content>
#endif

final class ShareViewController: PlatformViewController {
    private let model = ShareExtensionModel()

    #if os(macOS)
    private let preferredExtensionSize = NSSize(width: 520, height: 460)
    #endif

    #if os(macOS)
    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: preferredExtensionSize))
    }
    #endif

    override func viewDidLoad() {
        super.viewDidLoad()

        model.attach(extensionContext: extensionContext)
        let hostingController = PlatformHostingController(rootView: ShareView(model: model))

        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        #if os(iOS)
        hostingController.didMove(toParent: self)
        #elseif os(macOS)
        preferredContentSize = preferredExtensionSize
        #endif
        model.loadInitialContent()
    }
}

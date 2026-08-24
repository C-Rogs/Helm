import SwiftUI
import UIKit

public struct ExportShareItem: Identifiable {
    public let id = UUID()
    public let url: URL

    public init(url: URL) {
        self.url = url
    }
}

public struct ShareSheet: UIViewControllerRepresentable {
    public let items: [Any]

    public init(items: [Any]) {
        self.items = items
    }

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

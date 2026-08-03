import DesignSystem
import SwiftUI

struct StaleSessionBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .helmType(.body, color: HelmColor.fg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(HelmSpacing.md)
            .helmPanelChrome(.elevated)
    }
}

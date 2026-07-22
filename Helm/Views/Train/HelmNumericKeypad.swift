import DesignSystem
import SwiftUI
import UIKit

struct HelmNumericKeypad: UIViewRepresentable {
    let allowsDecimal: Bool
    let onDigit: (String) -> Void
    let onBackspace: () -> Void
    let onDone: () -> Void

    func makeUIView(context: Context) -> HelmNumericKeypadView {
        let view = HelmNumericKeypadView(allowsDecimal: allowsDecimal)
        view.onDigit = onDigit
        view.onBackspace = onBackspace
        view.onDone = onDone
        return view
    }

    func updateUIView(_ uiView: HelmNumericKeypadView, context: Context) {
        uiView.allowsDecimal = allowsDecimal
        uiView.onDigit = onDigit
        uiView.onBackspace = onBackspace
        uiView.onDone = onDone
        uiView.setNeedsLayout()
    }
}

final class HelmNumericKeypadView: UIView {
    var allowsDecimal = true
    var onDigit: ((String) -> Void)?
    var onBackspace: (() -> Void)?
    var onDone: (() -> Void)?

    private let stack = UIStackView()

    init(allowsDecimal: Bool) {
        self.allowsDecimal = allowsDecimal
        super.init(frame: .zero)
        backgroundColor = UIColor(HelmColor.surface)
        layer.cornerRadius = HelmRadius.md
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        clipsToBounds = true
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])
        rebuildKeys()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeFirstResponder: Bool { false }

    private func rebuildKeys() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let rows: [[String]] = [
            ["1", "2", "3"],
            ["4", "5", "6"],
            ["7", "8", "9"],
            allowsDecimal ? [".", "0", "⌫"] : ["", "0", "⌫"]
        ]
        for row in rows {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = 8
            rowStack.distribution = .fillEqually
            for key in row {
                if key.isEmpty {
                    rowStack.addArrangedSubview(UIView())
                    continue
                }
                rowStack.addArrangedSubview(makeKey(title: key))
            }
            stack.addArrangedSubview(rowStack)
        }
        stack.addArrangedSubview(makeKey(title: "Done", prominent: true))
    }

    private func makeKey(title: String, prominent: Bool = false) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: prominent ? 18 : 24, weight: .semibold)
        button.setTitleColor(prominent ? UIColor.black : UIColor.white, for: .normal)
        button.backgroundColor = prominent
            ? UIColor(HelmColor.accent)
            : UIColor(HelmColor.surfaceElevated)
        button.layer.cornerRadius = 10
        button.heightAnchor.constraint(equalToConstant: prominent ? 48 : 52).isActive = true
        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            switch title {
            case "⌫":
                self.onBackspace?()
            case "Done":
                self.onDone?()
            default:
                self.onDigit?(title)
            }
        }, for: .touchUpInside)
        return button
    }
}

#Preview("Numpad") {
    HelmNumericKeypad(
        allowsDecimal: true,
        onDigit: { _ in },
        onBackspace: {},
        onDone: {}
    )
    .frame(height: 320)
    .helmTheme()
}

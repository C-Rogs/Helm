import SwiftUI
import UIKit

public struct HelmNumpad: UIViewRepresentable {
    public let allowsDecimal: Bool
    public let onDigit: (String) -> Void
    public let onBackspace: () -> Void
    public let onNext: () -> Void

    public init(
        allowsDecimal: Bool,
        onDigit: @escaping (String) -> Void,
        onBackspace: @escaping () -> Void,
        onNext: @escaping () -> Void
    ) {
        self.allowsDecimal = allowsDecimal
        self.onDigit = onDigit
        self.onBackspace = onBackspace
        self.onNext = onNext
    }

    public func makeUIView(context: Context) -> HelmNumpadView {
        let view = HelmNumpadView(allowsDecimal: allowsDecimal)
        view.onDigit = onDigit
        view.onBackspace = onBackspace
        view.onNext = onNext
        return view
    }

    public func updateUIView(_ uiView: HelmNumpadView, context: Context) {
        uiView.allowsDecimal = allowsDecimal
        uiView.onDigit = onDigit
        uiView.onBackspace = onBackspace
        uiView.onNext = onNext
        uiView.setNeedsLayout()
    }
}

public final class HelmNumpadView: UIView {
    public var allowsDecimal = true
    public var onDigit: ((String) -> Void)?
    public var onBackspace: (() -> Void)?
    public var onNext: (() -> Void)?

    private let stack = UIStackView()

    public init(allowsDecimal: Bool) {
        self.allowsDecimal = allowsDecimal
        super.init(frame: .zero)
        backgroundColor = UIColor(HelmColor.canvas)
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: HelmSpacing.sm),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -HelmSpacing.sm),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: HelmSpacing.sm),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -HelmSpacing.sm)
        ])
        rebuildKeys()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var canBecomeFirstResponder: Bool { false }

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
        stack.addArrangedSubview(makeKey(title: "NEXT", prominent: true))
    }

    private func makeKey(title: String, prominent: Bool = false) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        if prominent {
            button.titleLabel?.font = UIFont(name: "SpaceGrotesk-Bold", size: 17)
                ?? .systemFont(ofSize: 17, weight: .semibold)
        } else {
            button.titleLabel?.font = UIFont(name: "JetBrainsMono-SemiBold", size: 24)
                ?? .monospacedSystemFont(ofSize: 24, weight: .semibold)
        }
        button.setTitleColor(
            prominent ? UIColor(HelmColor.buttonPrimaryForeground) : UIColor(HelmColor.fg),
            for: .normal
        )
        button.backgroundColor = prominent
            ? UIColor(HelmColor.buttonPrimaryBackground)
            : UIColor(HelmColor.surfaceElevated)
        button.layer.cornerRadius = HelmRadius.sm
        button.heightAnchor.constraint(equalToConstant: prominent ? 48 : 52).isActive = true
        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            switch title {
            case "⌫":
                HapticEngine.shared.play(.selection)
                self.onBackspace?()
            case "NEXT":
                self.onNext?()
            default:
                HapticEngine.shared.play(.selection)
                self.onDigit?(title)
            }
        }, for: .touchUpInside)
        return button
    }
}

#Preview("Numpad") {
    HelmNumpad(
        allowsDecimal: true,
        onDigit: { _ in },
        onBackspace: {},
        onNext: {}
    )
    .frame(height: 320)
    .helmTheme()
}

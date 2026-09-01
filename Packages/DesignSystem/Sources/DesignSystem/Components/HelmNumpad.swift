import SwiftUI
import UIKit

public enum HelmNumpadMetrics {
    public static let keyHeight: CGFloat = 52
    public static let prominentKeyHeight: CGFloat = 48
    public static let rowSpacing: CGFloat = 8

    public static var preferredHeight: CGFloat {
        preferredHeight(showsAction: true)
    }

    public static func preferredHeight(showsAction: Bool) -> CGFloat {
        let padding = HelmSpacing.sm * 2
        let rowHeights = keyHeight * 4 + (showsAction ? prominentKeyHeight : 0)
        let spacing = rowSpacing * (showsAction ? 4 : 3)
        return padding + rowHeights + spacing
    }
}

public struct HelmNumpad: UIViewRepresentable {
    public let allowsDecimal: Bool
    public let actionTitle: String?
    public let onDigit: (String) -> Void
    public let onBackspace: () -> Void
    public let onAction: (() -> Void)?

    public init(
        allowsDecimal: Bool,
        actionTitle: String? = nil,
        onDigit: @escaping (String) -> Void,
        onBackspace: @escaping () -> Void,
        onAction: (() -> Void)? = nil
    ) {
        self.allowsDecimal = allowsDecimal
        self.actionTitle = actionTitle
        self.onDigit = onDigit
        self.onBackspace = onBackspace
        self.onAction = onAction
    }

    public func makeUIView(context: Context) -> HelmNumpadView {
        HapticEngine.shared.prepare()
        let view = HelmNumpadView(allowsDecimal: allowsDecimal, actionTitle: actionTitle)
        view.onDigit = onDigit
        view.onBackspace = onBackspace
        view.onAction = onAction
        return view
    }

    public func updateUIView(_ uiView: HelmNumpadView, context: Context) {
        let prefersSystemFonts = context.environment.helmPrefersSystemFonts
        HelmFontPreferences.prefersSystemFonts = prefersSystemFonts
        uiView.updateConfiguration(
            allowsDecimal: allowsDecimal,
            actionTitle: actionTitle,
            prefersSystemFonts: prefersSystemFonts
        )
        uiView.onDigit = onDigit
        uiView.onBackspace = onBackspace
        uiView.onAction = onAction
    }
}

public final class HelmNumpadView: UIView {
    public var allowsDecimal = true
    public var actionTitle: String?
    public var onDigit: ((String) -> Void)?
    public var onBackspace: (() -> Void)?
    public var onAction: (() -> Void)?

    private let stack = UIStackView()
    private var appliedPrefersSystemFonts = HelmFontPreferences.prefersSystemFonts

    public override var intrinsicContentSize: CGSize {
        CGSize(
            width: UIView.noIntrinsicMetric,
            height: HelmNumpadMetrics.preferredHeight(showsAction: actionTitle != nil)
        )
    }

    public init(allowsDecimal: Bool, actionTitle: String? = nil) {
        self.allowsDecimal = allowsDecimal
        self.actionTitle = actionTitle
        super.init(frame: .zero)
        backgroundColor = UIColor(HelmColor.canvas)
        stack.axis = .vertical
        stack.spacing = HelmNumpadMetrics.rowSpacing
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

    public func updateConfiguration(
        allowsDecimal: Bool,
        actionTitle: String?,
        prefersSystemFonts: Bool = HelmFontPreferences.prefersSystemFonts
    ) {
        let needsRebuild = self.allowsDecimal != allowsDecimal
            || self.actionTitle != actionTitle
            || appliedPrefersSystemFonts != prefersSystemFonts
        self.allowsDecimal = allowsDecimal
        self.actionTitle = actionTitle
        appliedPrefersSystemFonts = prefersSystemFonts
        HelmFontPreferences.prefersSystemFonts = prefersSystemFonts
        invalidateIntrinsicContentSize()
        guard needsRebuild else { return }
        rebuildKeys()
    }

    func rebuildKeys() {
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
        if let actionTitle {
            stack.addArrangedSubview(makeKey(title: actionTitle, prominent: true))
        }
    }

    private func makeKey(title: String, prominent: Bool = false) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        if prominent {
            if appliedPrefersSystemFonts {
                button.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
            } else {
                button.titleLabel?.font = UIFont(name: "SpaceGrotesk-Bold", size: 17)
                    ?? .systemFont(ofSize: 17, weight: .semibold)
            }
        } else {
            if appliedPrefersSystemFonts {
                button.titleLabel?.font = .systemFont(ofSize: 24, weight: .semibold)
            } else {
                button.titleLabel?.font = UIFont(name: "JetBrainsMono-SemiBold", size: 24)
                    ?? .monospacedSystemFont(ofSize: 24, weight: .semibold)
            }
        }
        button.setTitleColor(
            prominent ? UIColor(HelmColor.buttonPrimaryForeground) : UIColor(HelmColor.fg),
            for: .normal
        )
        button.backgroundColor = prominent
            ? UIColor(HelmColor.buttonPrimaryBackground)
            : UIColor(HelmColor.surfaceElevated)
        button.layer.cornerRadius = HelmRadius.sm
        button.heightAnchor.constraint(equalToConstant: prominent ? HelmNumpadMetrics.prominentKeyHeight : HelmNumpadMetrics.keyHeight).isActive = true
        button.addAction(UIAction { [weak self, weak button] _ in
            guard let button else { return }
            self?.applyKeyPressed(button, pressed: true)
            if !prominent {
                HapticEngine.shared.play(.selection)
            }
        }, for: .touchDown)
        button.addAction(UIAction { [weak self, weak button] _ in
            guard let button else { return }
            self?.applyKeyPressed(button, pressed: true)
            if !prominent {
                HapticEngine.shared.play(.selection)
            }
        }, for: .touchDragEnter)
        button.addAction(UIAction { [weak self, weak button] _ in
            guard let button else { return }
            self?.applyKeyPressed(button, pressed: false)
        }, for: [.touchDragExit, .touchCancel, .touchUpOutside])
        button.addAction(UIAction { [weak self, weak button] _ in
            guard let self else { return }
            if let button {
                self.applyKeyPressed(button, pressed: false)
            }
            switch title {
            case "⌫":
                self.onBackspace?()
            default:
                if prominent {
                    self.onAction?()
                } else {
                    self.onDigit?(title)
                }
            }
        }, for: .touchUpInside)
        return button
    }

    private func applyKeyPressed(_ button: UIButton, pressed: Bool) {
        let scale = pressed ? 0.96 : 1.0
        let alpha: CGFloat = pressed ? 0.78 : 1
        let animations = {
            button.alpha = alpha
            button.transform = CGAffineTransform(scaleX: scale, y: scale)
        }
        if pressed {
            UIView.animate(
                withDuration: HelmMotion.pressIn,
                delay: 0,
                options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState],
                animations: animations
            )
        } else {
            UIView.animate(
                withDuration: HelmMotion.pressResponse,
                delay: 0,
                usingSpringWithDamping: CGFloat(HelmMotion.pressDamping),
                initialSpringVelocity: 0.4,
                options: [.allowUserInteraction, .beginFromCurrentState],
                animations: animations
            )
        }
    }
}

#Preview("Numpad") {
    HelmNumpad(
        allowsDecimal: true,
        onDigit: { _ in },
        onBackspace: {}
    )
    .frame(height: HelmNumpadMetrics.preferredHeight(showsAction: false))
    .helmTheme()
}

#Preview("Numpad with Done") {
    HelmNumpad(
        allowsDecimal: false,
        actionTitle: "Done",
        onDigit: { _ in },
        onBackspace: {},
        onAction: {}
    )
    .frame(height: HelmNumpadMetrics.preferredHeight(showsAction: true))
    .helmTheme()
}

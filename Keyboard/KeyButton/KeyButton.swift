import UIKit

final class KeyButton: UIButton {
    
    let keyButtonView: UIView = UIView()
    let keyTextLabel: UILabel = UILabel()
    let keyImageView: UIImageView = UIImageView()
    
    let keyboardEvent: KeyboardEvent
    let viewController: KeyboardViewController
    
    init(keyboardEvent: KeyboardEvent, viewController: KeyboardViewController) {
        self.keyboardEvent = keyboardEvent
        self.viewController = viewController
        
        super.init(frame: .zero)
        backgroundColor = .clearTappable
        
        switch keyboardEvent {
        case .backspace, .shift, .shiftDown:
            setupKeyButtonView()
            setupKeyImageView(constant: 11)
        case .switchInputMethod:
            setupKeyButtonView()
            setupKeyImageView()
        case .none, .keyALeft, .keyLRight, .keyZLeft, .keyBackspaceLeft:
            break
        default:
            setupKeyButtonView()
            setupKeyTextLabel()
        }
        
        setupKeyActions()
    }
    
    deinit {
        invalidateBackspaceTimers()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var intrinsicContentSize: CGSize {
        return CGSize(width: width, height: height)
    }
    
    private lazy var shapeLayer: CAShapeLayer = {
        let caLayer: CAShapeLayer = CAShapeLayer()
        caLayer.shadowOpacity = 0.5
        caLayer.shadowRadius = 1
        caLayer.shadowOffset = .zero
        caLayer.shadowColor = UIColor.black.cgColor
        caLayer.shouldRasterize = true
        caLayer.rasterizationScale = UIScreen.main.scale
        return caLayer
    }()
    private lazy var previewLabel: UILabel = UILabel()

    // touchesBegan / touchesEnded / touchesMoved
    // 在 SwiftUI 里面使用 gestures 来实现
    // 参考 https://developer.apple.com/documentation/swiftui/gestures and https://developer.apple.com/documentation/swiftui/adding-interactivity-with-gestures
    // NSHostingView see https://developer.apple.com/documentation/swiftui/nshostingview

    // touchesBegan 只涉及到 UI 的变化, 没有按键逻辑上的代码
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        switch keyboardEvent {
        case .text(_):
            // .phone: iPhones and iPods
            // .regular: 表示竖屏 see https://developer.apple.com/documentation/uikit/uitraitcollection
            // 若是 SwiftUI, 可参见 https://stackoverflow.com/questions/57652242/how-to-detect-whether-targetenvironment-is-ipados-in-swiftui
            if viewController.traitCollection.userInterfaceIdiom == .phone && viewController.traitCollection.verticalSizeClass == .regular {
                // 初始化为没有按键预览
                self.previewLabel.text = nil
                self.previewLabel.removeFromSuperview()
                
                let keyWidth: CGFloat = keyButtonView.frame.width
                let keyHeight: CGFloat = keyButtonView.frame.height
                let bottomCenter: CGPoint = CGPoint(x: keyButtonView.frame.origin.x + keyWidth / 2, y: keyButtonView.frame.maxY)
                // startBezierPath 的控制点长这个样子
                //    +-----------E---+
                //    +   |       |   +
                //    C...D       F...+
                //    +               +
                //    +               +
                //    +...B       H...G
                //    +   |       |   +
                //    +---A---o-------+
                let startPath: UIBezierPath = startBezierPath(origin: bottomCenter, keyWidth: keyWidth, keyHeight: keyHeight, keyCornerRadius: 5)
                // previewBezierPath 的控制点长这个样子
                // 看起来
                //    +-------------------G---+
                //    +   |               |   +
                //    E...F               H...+
                //    +                       +
                //    +                       +
                //    D                       J
                //     .                     .
                //       .                 .
                //        C               K
                //        +               +
                //        +               +
                //        +...B       M...L
                //        +   |       |   +
                //        +---A---o-------+
                let previewPath: UIBezierPath = previewBezierPath(origin: bottomCenter, previewCornerRadius: 10, keyWidth: keyWidth, keyHeight: keyHeight, keyCornerRadius: 5)
                // startPath -> shapeLayer.path = startPath.cgPath
                // previewPath -> animation.toValue = previewPath.cgPath -> shapeLayer.add(animation, forKey: animation.keyPath)
                //     shapeLayer -> layer.addSublayer(shapeLayer)
                // 这里应该是按键的形状, 从类似与 startPath 定义的形状开始, 通过动画变成了 previewPath 定义的形状
                // 需要继续学习 Core Animation 搞清楚具体如何使用
                shapeLayer.path = startPath.cgPath
                shapeLayer.fillColor = buttonColor.cgColor
                
                let animation = CABasicAnimation(keyPath: "path")
                animation.duration = 0.01
                animation.toValue = previewPath.cgPath
                animation.fillMode = .forwards
                animation.isRemovedOnCompletion = false
                animation.timingFunction = CAMediaTimingFunction(name: .default)
                shapeLayer.add(animation, forKey: animation.keyPath)
                // var layer: CALayer 定义在 UIView 里面 see https://developer.apple.com/documentation/uikit/uiview
                layer.addSublayer(shapeLayer)
                
                let labelHeight: CGFloat = previewPath.bounds.height - keyHeight - 8
                previewLabel = UILabel(frame: CGRect(x: keyButtonView.frame.origin.x - 5, y: keyButtonView.frame.origin.y - labelHeight - 8, width: keyWidth + 10, height: labelHeight))
                previewLabel.textAlignment = .center
                previewLabel.adjustsFontForContentSizeCategory = true
                previewLabel.font = .preferredFont(forTextStyle: .largeTitle)
                previewLabel.textColor = buttonTintColor
                addSubview(previewLabel)
                
                showPreviewText()
            } else {
                keyButtonView.backgroundColor = self.highlightButtonColor
            }
        case .space:
            keyButtonView.backgroundColor = self.highlightButtonColor
            // spaceTouchPoint 会在 touchesMoved 里面用到, 用于计算是否移动光标
            spaceTouchPoint = touches.first?.location(in: self) ?? .zero
            performedDraggingOnSpace = false
        case .backspace:
            keyButtonView.backgroundColor = self.highlightButtonColor
            backspaceTouchPoint = touches.first?.location(in: self) ?? .zero
        default:
            break
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        
        invalidateBackspaceTimers()
        
        if keyboardEvent == .space {
            // 在 touchesMoved 里, 如果移动距离足够, performedDraggingOnSpace 会设为 true
            guard !performedDraggingOnSpace else {
                // 当手指离开空格键的时候, 若移动量不足, 重置 spaceTouchPoint 并将空格键的 UI 还原
                spaceTouchPoint = .zero
                changeColorToNormal()
                return
            }
            switch viewController.keyboardLayout {
            case .jyutping, .jyutpingUppercase:
                // 当前有候选字, 空格键将上屏第一个候选, 然后播放按键音
                if !viewController.candidates.isEmpty {
                    let candidate: Candidate = viewController.candidates[0]
                    viewController.textDocumentProxy.insertText(candidate.text)
                    AudioFeedback.perform(audioFeedback: .modify)
                    // lazy var candidateSequence: [Candidate] = [] 定义在 KeyboardViewController.swift 里面
                    viewController.candidateSequence.append(candidate) // 不太理解
                    // 这个 currentInputText 是当前输入的*拼音*字符, 可以将其理解为一个 buffer. 这句话就是把上屏的这个候选词的拼音从这个 buffer 里去掉, 接下来继续处理 buffer 里剩余的拼音
                    // var currentInputText: String = ""
                    viewController.currentInputText = String(viewController.currentInputText.dropFirst(candidate.input.count))
                    if viewController.currentInputText.isEmpty {
                        var combinedCandidate: Candidate = viewController.candidateSequence[0]
                        _ = viewController.candidateSequence.dropFirst().map { oneCandidate in
                            combinedCandidate += oneCandidate
                        }
                        viewController.candidateSequence = []
                        viewController.imeQueue.async {
                            self.viewController.lexiconManager.handle(candidate: combinedCandidate)
                        }
                    }
                } else if !viewController.currentInputText.isEmpty {
                    viewController.textDocumentProxy.insertText(viewController.currentInputText)
                    viewController.currentInputText = ""
                    AudioFeedback.perform(audioFeedback: .modify)
                } else {
                    viewController.textDocumentProxy.insertText(" ")
                    AudioFeedback.play(for: .space)
                }
                if viewController.keyboardLayout == .jyutpingUppercase && !viewController.isCapsLocked {
                    viewController.keyboardLayout = .jyutping
                }
            case .alphabeticUppercase:
                viewController.textDocumentProxy.insertText(" ")
                AudioFeedback.play(for: .space)
                if !viewController.isCapsLocked {
                    viewController.keyboardLayout = .alphabetic
                }
            default:
                viewController.textDocumentProxy.insertText(" ")
                AudioFeedback.play(for: .space)
            }
            spaceTouchPoint = .zero
            changeColorToNormal()
        }
        switch keyboardEvent {
        case .backspace:
            changeColorToNormal()
        case .text(_):
            if viewController.traitCollection.userInterfaceIdiom == .phone && viewController.traitCollection.verticalSizeClass == .regular {
                removePreview()
            } else {
                changeColorToNormal()
            }
        default:
            break
        }
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        if keyboardEvent == .space {
            guard let location: CGPoint = touches.first?.location(in: self) else { return }
            let distance: CGFloat = location.x - spaceTouchPoint.x
            guard abs(distance) > 8 else { return }
            viewController.currentInputText = ""
            if distance > 0 {
                viewController.textDocumentProxy.adjustTextPosition(byCharacterOffset: 1)
            } else {
                viewController.textDocumentProxy.adjustTextPosition(byCharacterOffset: -1)
            }
            spaceTouchPoint = location
            performedDraggingOnSpace = true
        }
        if keyboardEvent == .backspace {
            guard viewController.keyboardLayout == .jyutping else { return }
            guard let location: CGPoint = touches.first?.location(in: self) else { return }
            let distance: CGFloat = location.x - backspaceTouchPoint.x
            guard distance < -44 else { return }
            viewController.currentInputText = ""
        }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        
        invalidateBackspaceTimers()
        
        switch keyboardEvent {
        case .backspace:
            changeColorToNormal()
        case .space:
            spaceTouchPoint = .zero
            changeColorToNormal()
        case .text(_):
            if viewController.traitCollection.userInterfaceIdiom == .phone && viewController.traitCollection.verticalSizeClass == .regular {
                removePreview()
            } else {
                changeColorToNormal()
            }
        default:
            break
        }
    }
    
    private func changeColorToNormal() {
        UIView.animate(withDuration: 0,
                   delay: 0.03,
                   animations: { self.keyButtonView.backgroundColor = self.buttonColor }
        )
    }
    
    private func showPreviewText() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            self.previewLabel.text = self.keyText
        }
    }
    private func removePreview() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            self.previewLabel.text = nil
            self.previewLabel.removeFromSuperview()
            self.shapeLayer.removeFromSuperlayer()
        }
    }
    
    var slowBackspaceTimer: Timer?
    var fastBackspaceTimer: Timer?
    private func invalidateBackspaceTimers() {
        slowBackspaceTimer?.invalidate()
        fastBackspaceTimer?.invalidate()
    }
    
    private lazy var performedDraggingOnSpace: Bool = false
    private lazy var spaceTouchPoint: CGPoint = .zero
    private lazy var backspaceTouchPoint: CGPoint = .zero
}

import UIKit
import OpenCC

// KeyboardViewController: UIInputViewController 是键盘的唯一（？）视图，创建一个第三方键盘也就是实现这个 view controller
// see https://developer.apple.com/documentation/uikit/uiinputviewcontroller
//    var inputViewStyle: UIInputView.Style { get } // 这是 UIInputViewController 的一个成员
//        默认值 .default 只会模糊背景, 不会对其染色; 可以使用 .keyboard, 这个会模糊背景并且对其染色, 目前看来 jyutping 使用的是 .default, 自己令设背景色
// see https://dev.taio.app/#/cn/editor/toolbar
// UPDATE: 好像并不能使用这个, 因为 KeyboardViewController 并不是由我来初始化的, 而这个 inputViewStyle 是只读的

// 重点关注
// var view: UIView!
//     └─ keyboardStackView （通过 view.addSubview(_:) 添加）
//        ├─ toolBar
//        └─ keysRows
final class KeyboardViewController: UIInputViewController {
    
    lazy var toolBar: ToolBar = ToolBar(viewController: self)
    lazy var settingsView: UIView = UIView()
    lazy var candidateBoard: CandidateBoard = CandidateBoard()
    lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
    lazy var settingsTableView: UITableView = UITableView(frame: .zero, style: .grouped)
    
    lazy var keyboardStackView: UIStackView = {
        let stackView = UIStackView(frame: .zero)
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.distribution = .equalSpacing
        return stackView
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.addSubview(keyboardStackView)
        keyboardStackView.translatesAutoresizingMaskIntoConstraints = false
        keyboardStackView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        keyboardStackView.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        keyboardStackView.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        keyboardStackView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        
        setupToolBarActions()
        
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(CandidateCollectionViewCell.self, forCellWithReuseIdentifier: "CandidateCell")
        collectionView.backgroundColor = self.view.backgroundColor
        
        settingsTableView.dataSource = self
        settingsTableView.delegate = self
        settingsTableView.register(SwitchTableViewCell.self, forCellReuseIdentifier: "SwitchTableViewCell")                
        settingsTableView.register(NormalTableViewCell.self, forCellReuseIdentifier: "CharactersTableViewCell")
        settingsTableView.register(NormalTableViewCell.self, forCellReuseIdentifier: "ToneStyleTableViewCell")
        settingsTableView.register(NormalTableViewCell.self, forCellReuseIdentifier: "ClearLexiconTableViewCell")
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if askingDifferentKeyboardLayout {
            keyboardLayout = answeredKeyboardLayout
        } else {
            setupKeyboard()
            didKeyboardEstablished = true
        }
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        isDarkAppearance = textDocumentProxy.keyboardAppearance == .dark || traitCollection.userInterfaceStyle == .dark
        appearance = detectAppearance()
        if didKeyboardEstablished {
            setupKeyboard()
        }
    }
    
    private lazy var didKeyboardEstablished: Bool = false
    private lazy var askingDifferentKeyboardLayout: Bool = false
    
    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        let asked: KeyboardLayout = askedKeyboardLayout
        if answeredKeyboardLayout != asked {
            answeredKeyboardLayout = asked
            askingDifferentKeyboardLayout = true
            if didKeyboardEstablished {
                keyboardLayout = answeredKeyboardLayout
            }
        }
        if !textDocumentProxy.hasText && !currentInputText.isEmpty {
            // User just tapped Clear Button in TextField
            currentInputText = ""
        }
    }
    
    private lazy var answeredKeyboardLayout: KeyboardLayout = .jyutping
    
    var askedKeyboardLayout: KeyboardLayout {
        switch textDocumentProxy.keyboardType {
        case .numberPad, .asciiCapableNumberPad:
            return traitCollection.userInterfaceIdiom == .pad ? .numeric : .numberPad
        case .decimalPad:
            return traitCollection.userInterfaceIdiom == .pad ? .numeric : .decimalPad
        case .asciiCapable, .emailAddress, .twitter, .URL:
            return .alphabetic
        case .numbersAndPunctuation:
            return .numeric
        default:
            return .jyutping
        }
    }
    
    lazy var isCapsLocked: Bool = false
    
    var keyboardLayout: KeyboardLayout = .jyutping {
        didSet {
            setupKeyboard()
            guard didKeyboardEstablished else {
                didKeyboardEstablished = true
                return
            }
            if !keyboardLayout.isJyutpingMode {
                if !currentInputText.isEmpty {
                    textDocumentProxy.insertText(currentInputText)
                }
                currentInputText = ""
            }
        }
    }
    
    let imeQueue: DispatchQueue = DispatchQueue(label: "im.cantonese.ime", qos: .userInitiated)
    // currentInputText 是当前输入的*拼音*字符, 可以将其理解为一个 buffer
    var currentInputText: String = "" {
        didSet {
            DispatchQueue.main.async {
                // 当输入缓冲区变化的时候, 更新 toolBar 的显示
                self.toolBar.update()
            }
            if currentInputText.isEmpty {
                // 如果缓冲区空了, 候选词直接设为空
                candidates = []
            } else {
                // 如果缓冲区还有内容, 就调用引擎获取新的候选词
                imeQueue.async {
                    self.suggestCandidates()
                }
            }
            // 这里应该是把缓冲区的字符标记为已选择, 表示还没有上屏
            let range: NSRange = NSRange(location: currentInputText.count, length: 0)
            textDocumentProxy.setMarkedText(currentInputText, selectedRange: range)
        }
    }
    
    lazy var candidateSequence: [Candidate] = []
    
    var candidates: [Candidate] = [] {
        didSet {
            DispatchQueue.main.async {
                self.collectionView.reloadData()
                self.collectionView.setContentOffset(.zero, animated: true)
            }
        }
    }
    
    let lexiconManager: LexiconManager = LexiconManager()
    private let engine: Engine = Engine()
    private func suggestCandidates() {
        let userdbCandidates: [Candidate] = lexiconManager.suggest(for: currentInputText)
        let engineCandidates: [Candidate] = engine.suggest(for: currentInputText)
        let combined: [Candidate] = userdbCandidates + engineCandidates
        if logogram < 2 {
            candidates = combined.deduplicated()
        } else {
            let converted: [Candidate] = combined.map { Candidate(text: converter.convert($0.text), footnote: $0.footnote, input: $0.input, lexiconText: $0.lexiconText) }
            candidates = converted.deduplicated()
        }
    }
    
    private func setupToolBarActions() {
        toolBar.settingsButton.addTarget(self, action: #selector(handleSettingsButtonEvent), for: .allTouchEvents)
        toolBar.yueEngSwitch.addTarget(self, action: #selector(handleYueEngSwitch), for: .valueChanged)
        toolBar.downArrowButton.addTarget(self, action: #selector(handleDownArrowEvent), for: .allTouchEvents)
        toolBar.keyboardDownButton.addTarget(self, action: #selector(dismissInputMethod), for: .allTouchEvents)
    }
    @objc private func handleDownArrowEvent() {
        keyboardLayout = .candidateBoard
    }
    @objc private func dismissInputMethod() {
        dismissKeyboard()
    }
    @objc private func handleSettingsButtonEvent() {
        keyboardLayout = .settingsView
    }
    @objc private func handleYueEngSwitch() {
        isCapsLocked = false
        switch toolBar.yueEngSwitch.selectedSegmentIndex {
        case 0:
            keyboardLayout = .jyutping
        case 1:
            keyboardLayout = .alphabetic
        default:
            break
        }
    }
    
    private var converter: ChineseConverter = {
        let options: ChineseConverter.Options = {
            let logogram: Int = UserDefaults.standard.integer(forKey: "logogram")
            // 0: The key "logogram" doesn‘t exist.
            // 1: 傳統漢字
            // 2: 傳統漢字香港字形
            // 3: 傳統漢字臺灣字形
            // 4: 大陸簡化字
            switch logogram {
            case 2:
                return [.hkStandard]
            case 3:
                return [.twStandard]
            case 4:
                return [.simplify]
            default:
                return [.traditionalize]
            }
        }()
        let openccBundle: Bundle = Bundle(url: Bundle.main.bundleURL.appendingPathComponent("OpenCC.bundle"))!
        let converter: ChineseConverter = try! ChineseConverter(bundle: openccBundle, options: options)
        return converter
    }()
    func updateConverter() {
        logogram = UserDefaults.standard.integer(forKey: "logogram")
        let options: ChineseConverter.Options = {
            switch logogram {
            case 2:
                return [.hkStandard]
            case 3:
                return [.twStandard]
            case 4:
                return [.simplify]
            default:
                return [.traditionalize]
            }
        }()
        let openccBundle: Bundle = Bundle(url: Bundle.main.bundleURL.appendingPathComponent("OpenCC.bundle"))!
        let converter: ChineseConverter = try! ChineseConverter(bundle: openccBundle, options: options)
        self.converter = converter
    }
    private lazy var logogram: Int = UserDefaults.standard.integer(forKey: "logogram")
    private(set) lazy var toneStyle: Int = UserDefaults.standard.integer(forKey: "tone_style")
    func updateToneStyle() {
        // 0: The key "tone_style" doesn‘t exist.
        // 1: Normal
        // 2: No tones
        // 3: Superscript
        // 4: Subscript
        // 4: Mixed Yam Yeung
        toneStyle = UserDefaults.standard.integer(forKey: "tone_style")
    }
    
    private(set) lazy var isDarkAppearance: Bool = textDocumentProxy.keyboardAppearance == .dark || traitCollection.userInterfaceStyle == .dark
    
    private(set) lazy var appearance: Appearance = detectAppearance()
    
    private func detectAppearance() -> Appearance {
        switch traitCollection.userInterfaceStyle {
        case .light:
            switch textDocumentProxy.keyboardAppearance {
            case .light, .default:
                return .lightModeLightAppearance
            case .dark:
                return .lightModeDarkAppearance
            default:
                return .lightModeDarkAppearance
            }
        case .dark:
            switch textDocumentProxy.keyboardAppearance {
            case .light, .default:
                return .darkModeLightAppearance
            case .dark:
                return .darkModeDarkAppearance
            default:
                return .darkModeLightAppearance
            }
        case .unspecified:
            switch textDocumentProxy.keyboardAppearance {
            case .light, .default:
                return .lightModeLightAppearance
            case .dark:
                return .darkModeDarkAppearance
            default:
                return .lightModeDarkAppearance
            }
        @unknown default:
            return .lightModeDarkAppearance
        }
    }
}

enum Appearance {
    case lightModeLightAppearance
    case lightModeDarkAppearance
    case darkModeLightAppearance
    case darkModeDarkAppearance
}

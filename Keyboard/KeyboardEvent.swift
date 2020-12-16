enum KeyboardEvent: Equatable {
    case
    none,
    text(String),
    backspace,
    newLine, // return, enter
    space,
    shift,
    shiftDown,
    switchInputMethod,
    switchTo(KeyboardLayout),
    
    // 分别是左边缘到 a 之间的空白处, l 到右边缘之间的空白处,
    // shift 和 z 之间的空白处, 以及 m 和退格键之间的空白处
    // 虽然在 UI 上和键盘背景一致, 但做了特殊处理, 来相应相邻按键的事件
    // 不过在相应的时候, 动画和系统键盘有一点点不同
    keyALeft,
    keyLRight,
    keyZLeft,
    keyBackspaceLeft
}

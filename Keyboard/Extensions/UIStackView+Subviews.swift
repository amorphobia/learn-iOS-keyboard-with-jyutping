import UIKit

extension UIStackView {
        
        /// Use `addArrangedSubview` to add subviews to the end of the `arrangedSubviews` array.
        /// - Parameter subviews: The views to be added to the array of views arranged by the stack.

        // Swift 下划线用法
        //   1. 参数中的下划线用于忽略外部参数名
        //   2. 函数中的下划线，由于我们对 map 的返回值不感兴趣，将其返回值分配给下划线来避免编译警告
        func addMultipleArrangedSubviews(_ subviews: [UIView]) {
                _ = subviews.map { addArrangedSubview($0) }
        }
        
        /// Remove all arranged subviews from the stack.
        func removeAllArrangedSubviews() {
                _ = arrangedSubviews.map {
                        $0.removeFromSuperview()
                }
        }
}

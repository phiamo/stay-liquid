import UIKit

/// Forwards touches to the native tab bar and bottom accessory only; web content receives everything else.
final class TabsBarPassthroughView: UIView {
    weak var tabBar: UITabBar?
    weak var accessoryContentView: UIView?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled else { return nil }

        if let accessoryContentView, !accessoryContentView.isHidden, accessoryContentView.alpha > 0.01 {
            let converted = convert(point, to: accessoryContentView)
            if let hit = accessoryContentView.hitTest(converted, with: event) {
                return hit
            }
        }

        if let tabBar, !tabBar.isHidden, tabBar.alpha > 0.01 {
            let converted = convert(point, to: tabBar)
            if tabBar.point(inside: converted, with: event) {
                return tabBar.hitTest(converted, with: event)
            }
        }

        return nil
    }
}

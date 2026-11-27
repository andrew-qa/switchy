import Foundation

public enum LayoutCycler {
    /// Which input source an action should select, given the enabled sources in menu order.
    /// Returns nil when there is nothing sensible to select.
    public static func target(for action: SwitchAction, among ids: [String], current: String?) -> String? {
        switch action {
        case .select(let id):
            return ids.contains(id) ? id : nil
        case .next, .previous:
            guard !ids.isEmpty else { return nil }
            let forward = action == .next
            guard let current, let index = ids.firstIndex(of: current) else {
                return forward ? ids.first : ids.last
            }
            let step = forward ? 1 : -1
            return ids[(index + step + ids.count) % ids.count]
        }
    }
}

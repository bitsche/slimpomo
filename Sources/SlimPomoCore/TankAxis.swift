import Foundation

/// The one vertical axis of the timer tank. The water line and the depth scale both read it,
/// so a tick and the water at the same level always sit at the same height.
public enum TankAxis {
    /// Distance from the tank top to the water line at 100%.
    public static let fullInset = 12.0
    /// Distance from the tank bottom to the water line at 0%. A thin strip of water always stays visible.
    public static let emptyInset = 8.0
    /// Levels that carry a tick, top to bottom.
    public static let tickLevels = [1.0, 0.5, 0.0]

    /// Distance from the tank top to the mean surface of the front wave. Level runs 0 (empty) to 1 (full).
    public static func y(level: Double, height: Double) -> Double {
        let clamped = min(max(level, 0), 1)
        let yFull = fullInset
        let yEmpty = height - emptyInset
        return yEmpty - clamped * (yEmpty - yFull)
    }
}

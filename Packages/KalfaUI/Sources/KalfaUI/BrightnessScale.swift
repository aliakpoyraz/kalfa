import Foundation

/// The arithmetic behind Kalfa's brightness scale, kept free of any display so
/// it can be tested.
///
/// A level runs from `lowest` to 100. From 0 up it is backlight. Below zero the
/// backlight has nothing left to give and the picture is darkened instead: the
/// level then maps to the share of the signal that is let through, which never
/// falls under the floor.
public enum BrightnessScale {

    /// The bottom of the scale: a third of the slider lies below zero.
    public static let lowest: Double = -50

    /// The hardware reading under which the backlight counts as "at the bottom".
    /// Monitors round, and a panel that reports 1 after being told 0 is still
    /// as dim as it goes.
    public static let bottomTolerance: Double = 1.5

    /// Share of the signal let through, 0…1, for a level.
    ///
    /// - Parameter softwareOnly: the display has no backlight control, so its
    ///   whole 0…100 range is darkening and 100 is the untouched picture.
    public static func factor(level: Double, floor: Double, softwareOnly: Bool) -> Double {
        let floor = min(max(floor, 0), 1)
        if softwareOnly {
            let share = min(max(level, 0), 100) / 100
            return floor + (1 - floor) * share
        }
        guard level < 0 else { return 1 }
        let depth = min(level / lowest, 1)
        return 1 - depth * (1 - floor)
    }

    /// Backlight value for a 0…100 level, on a panel whose backlight must not
    /// go under `minimum` — the built-in display switches off at zero.
    public static func raw(fromPercent percent: Double, minimum: Double) -> Double {
        let share = min(max(percent, 0), 100) / 100
        return minimum + (1 - minimum) * share
    }

    public static func percent(fromRaw raw: Double, minimum: Double) -> Double {
        guard minimum < 1 else { return 0 }
        return min(max((raw - minimum) / (1 - minimum), 0), 1) * 100
    }

    /// The level to come back to after a relaunch or a reconnect.
    ///
    /// A saved darkening returns only while the backlight is still at the
    /// bottom. If the brightness was raised some other way in the meantime, the
    /// person has plainly asked for a brighter screen and gets it.
    public static func restored(hardware: Double, savedDim: Double?, allowsBelowZero: Bool) -> Double {
        guard allowsBelowZero, let savedDim, savedDim < 0, hardware <= bottomTolerance else { return hardware }
        return max(savedDim, lowest)
    }
}

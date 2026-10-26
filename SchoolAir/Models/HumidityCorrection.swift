import Foundation

/// EXPERIMENT, not a feature. Kept out of the advisory logic on purpose.
///
/// Particle sensors over-read in humid air because water droplets scatter the laser.
/// The EPA fitted a correction for PurpleAir sensors (Barkjohn, Gantt and Clements, 2021),
/// which use the same sensor family, against regulatory monitors on 24-hour averages.
/// Our box is a different configuration and our nearest monitor is across town, so we do
/// not claim the correction transfers. We store raw and adjusted side by side and label the
/// adjusted number "experimental".
enum HumidityCorrection {
    /// PM2.5(adjusted) = 0.524 × PM2.5(cf1) − 0.0862 × RH + 5.75
    /// - cf1: the sensor's "standard" PM2.5 value (`pm25std`).
    /// - rh: relative humidity in percent from the SHT45.
    static func adjustedPM25(cf1: Double, rh: Double) -> Double {
        max(0, 0.524 * cf1 - 0.0862 * rh + 5.75)
    }
}

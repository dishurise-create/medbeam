import Foundation

/// Switches for features that exist in the code but are turned off in the App Store version.
enum FeatureFlags {
    /// Pharmacy ratings and opening hours from Google Places. Off for release: it needs a
    /// Google API key with billing, which normal users can't set up. Pharmacy cards link to
    /// Apple Maps instead, which shows hours and reviews.
    static let googleRatingsAndHours = false
}

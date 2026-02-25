import Database
import SwiftUI

#if os(tvOS)
public enum EPGGuideLayout {
    public static let pointsPerMinute: CGFloat = 4.0
    public static let rowHeight: CGFloat = 80.0
    public static let headerHeight: CGFloat = 50.0
    public static let sidebarWidth: CGFloat = 240.0
    public static let minBlockWidth: CGFloat = 60.0
    public static let titleFontSize: CGFloat = 26.0
    public static let subtitleFontSize: CGFloat = 22.0
    public static let channelNameFontSize: CGFloat = 24.0
    public static let hourMarkFontSize: CGFloat = 24.0
}
#else
public enum EPGGuideLayout {
    public static let pointsPerMinute: CGFloat = 2.0
    public static let rowHeight: CGFloat = 50.0
    public static let headerHeight: CGFloat = 36.0
    public static let sidebarWidth: CGFloat = 160.0
    public static let minBlockWidth: CGFloat = 40.0
    public static let titleFontSize: CGFloat = 13.0
    public static let subtitleFontSize: CGFloat = 11.0
    public static let channelNameFontSize: CGFloat = 12.0
    public static let hourMarkFontSize: CGFloat = 12.0
}
#endif

extension EPGGuideLayout {
    /// Width in points for a program block, clamped to the visible window.
    public static func blockWidth(startTime: Int, endTime: Int, windowStart: Int, windowEnd: Int) -> CGFloat {
        let clampedStart = max(startTime, windowStart)
        let clampedEnd = min(endTime, windowEnd)
        let minutes = CGFloat(clampedEnd - clampedStart) / 60.0
        return max(minutes * pointsPerMinute, minBlockWidth)
    }

    /// X offset from the left edge of the grid for a given timestamp.
    public static func xOffset(for timestamp: Int, relativeTo windowStart: Int) -> CGFloat {
        CGFloat(timestamp - windowStart) / 60.0 * pointsPerMinute
    }

    /// Total grid width for the time window.
    public static func totalWidth(windowStart: Int, windowEnd: Int) -> CGFloat {
        CGFloat(windowEnd - windowStart) / 60.0 * pointsPerMinute
    }

    /// Snaps a timestamp down to the nearest hour boundary.
    public static func snapToHour(_ timestamp: Int) -> Int {
        timestamp - (timestamp % 3600)
    }
}

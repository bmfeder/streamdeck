import Database
import SwiftUI

struct EPGProgramBlockView: View {
    let program: EpgProgramRecord
    let isCurrent: Bool
    let width: CGFloat
    let isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(program.title)
                .font(.system(size: EPGGuideLayout.titleFontSize, weight: .medium))
                .lineLimit(1)
            Text(timeRangeText)
                .font(.system(size: EPGGuideLayout.subtitleFontSize))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(width: width, height: EPGGuideLayout.rowHeight, alignment: .leading)
        .background(isCurrent ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    isFocused ? Color.accentColor : Color.secondary.opacity(0.3),
                    lineWidth: isFocused ? 2 : 0.5
                )
        )
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .shadow(radius: isFocused ? 6 : 0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }

    private var timeRangeText: String {
        let start = Date(timeIntervalSince1970: Double(program.startTime))
        let end = Date(timeIntervalSince1970: Double(program.endTime))
        return "\(start.formatted(.dateTime.hour().minute())) – \(end.formatted(.dateTime.hour().minute()))"
    }
}

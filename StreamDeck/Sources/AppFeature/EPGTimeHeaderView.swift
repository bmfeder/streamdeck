import SwiftUI

struct EPGTimeHeaderView: View {
    let windowStart: Int
    let windowEnd: Int
    let currentTime: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(hourMarks, id: \.self) { epoch in
                Text(Date(timeIntervalSince1970: Double(epoch)), format: .dateTime.hour().minute(.twoDigits))
                    .font(.system(size: EPGGuideLayout.hourMarkFontSize, weight: .semibold))
                    .frame(
                        width: EPGGuideLayout.pointsPerMinute * 60,
                        height: EPGGuideLayout.headerHeight,
                        alignment: .leading
                    )
                    .padding(.leading, 8)
            }
        }
    }

    private var hourMarks: [Int] {
        var marks: [Int] = []
        var t = windowStart
        while t < windowEnd {
            marks.append(t)
            t += 3600
        }
        return marks
    }
}

/// Escapes SQL LIKE metacharacters (%, _, \) in user input
/// so they are treated as literal characters in LIKE patterns.
func escapeLikePattern(_ pattern: String) -> String {
    pattern
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "%", with: "\\%")
        .replacingOccurrences(of: "_", with: "\\_")
}

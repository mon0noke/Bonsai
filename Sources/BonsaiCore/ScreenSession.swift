public enum ScreenSession {
    /// Invalid/migrated preferences cannot strand a screen-covering overlay.
    public static func duration(_ stored:Int)->Int {[60,120,300].contains(stored) ? stored:60}
}

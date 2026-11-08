import Defaults

extension Defaults.Keys {
    /// Tells you where sound plays when the output changes.
    static let everydaySoundOutput = Key<Bool>("everydaySoundOutput", default: true)
    /// Tells you when a drive or memory card is connected or can be unplugged.
    static let everydayDrives = Key<Bool>("everydayDrives", default: true)
    /// Tells you when the microphone or camera starts being used.
    static let everydayMicCamera = Key<Bool>("everydayMicCamera", default: true)
    /// Tells you when the internet goes away and when it comes back.
    static let everydayInternet = Key<Bool>("everydayInternet", default: true)
    /// Tells you when your screen starts being shared, recorded or mirrored.
    static let everydayScreenShare = Key<Bool>("everydayScreenShare", default: true)
}

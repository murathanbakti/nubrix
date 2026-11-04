import Defaults

extension Defaults.Keys {
    static let devEnabled = Key<Bool>("devEnabled", default: false)
    static let devPorts = Key<[Int]>("devPorts", default: DevPortCatalog.defaultPorts)
}

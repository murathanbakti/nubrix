import Defaults

extension Defaults.Keys {
    static let devEnabled = Key<Bool>("devEnabled", default: true)
    static let devPorts = Key<[Int]>("devPorts", default: DevPortCatalog.defaultPorts)
}

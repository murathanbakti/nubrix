import Foundation

struct DevPortInfo {
    let label: String
    let isDatabase: Bool
}

enum DevPortCatalog {
    static let defaultPorts = [3000, 3001, 4000, 4200, 5000, 5173, 5432, 6379, 8000, 8080, 8888, 9000, 27017]

    private static let known: [Int: DevPortInfo] = [
        3000: DevPortInfo(label: "Node / Next", isDatabase: false),
        3001: DevPortInfo(label: "Dev server", isDatabase: false),
        3306: DevPortInfo(label: "MySQL", isDatabase: true),
        4000: DevPortInfo(label: "Dev server", isDatabase: false),
        4200: DevPortInfo(label: "Angular", isDatabase: false),
        4321: DevPortInfo(label: "Astro", isDatabase: false),
        5000: DevPortInfo(label: "Flask / Dev", isDatabase: false),
        5173: DevPortInfo(label: "Vite", isDatabase: false),
        5432: DevPortInfo(label: "Postgres", isDatabase: true),
        6379: DevPortInfo(label: "Redis", isDatabase: true),
        8000: DevPortInfo(label: "Django / Python", isDatabase: false),
        8080: DevPortInfo(label: "HTTP alt", isDatabase: false),
        8888: DevPortInfo(label: "Jupyter", isDatabase: false),
        9000: DevPortInfo(label: "Dev server", isDatabase: false),
        9200: DevPortInfo(label: "Elasticsearch", isDatabase: false),
        27017: DevPortInfo(label: "MongoDB", isDatabase: true)
    ]

    static func info(for port: Int) -> DevPortInfo {
        known[port] ?? DevPortInfo(label: "Port \(port)", isDatabase: false)
    }

    static func parse(_ text: String) -> [Int]? {
        let parts = text.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" }).map(String.init)
        var seen = Set<Int>()
        var ports: [Int] = []
        for part in parts {
            guard let value = Int(part), (1...65535).contains(value) else { return nil }
            if seen.insert(value).inserted { ports.append(value) }
        }
        return ports.isEmpty ? nil : ports
    }
}

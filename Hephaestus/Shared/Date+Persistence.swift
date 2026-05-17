import Foundation

extension Date {
    static func persistenceTimestampNow() -> Date {
        Date().normalizedForPersistence()
    }

    func normalizedForPersistence() -> Date {
        Date(timeIntervalSince1970: timeIntervalSince1970.rounded(.down))
    }
}

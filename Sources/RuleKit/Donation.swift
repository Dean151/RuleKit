//
//  Donation.swift
//

import Foundation

extension Event {
    /// Represent a specific donation for this event, allowing to know at what date and app version they were triggered at
    public struct Donation: Sendable, Codable {
        public let id: UUID
        /// The version of the main bundle when the donation was made
        public let appVersion: Version?
        /// The date of when the donation was made
        public let date: Date

        private init(id: UUID, appVersion: Version?, date: Date) {
            self.id = id
            self.appVersion = appVersion
            self.date = date
        }

        static var now: Donation {
            .init(id: UUID(), appVersion: .current, date: .now)
        }
    }

    /// Represent multiple donations for a specific event.
    /// Since a lot of donations might occurs, and to prevent storing them all, only count, first and last are available.
    public struct Donations: Sendable, Codable {
        static let empty = Donations(count: 0, first: nil, last: nil)

        public let count: Int
        public let first: Donation?
        public let last: Donation?
    }
}

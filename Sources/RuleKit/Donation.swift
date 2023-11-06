//
//  Donation.swift
//  RuleKit
//
//  MIT License
//
//  Copyright (c) 2023 Thomas Durand
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import Foundation

extension RuleKit.Event {
    /// Represent a specific donation for this event, allowing to know at what date and app version they were triggered at
    public struct Donation: Sendable, Codable {
        public let id: UUID
        /// The version of the main bundle when the donation was made
        public let appVersion: RuleKit.AppVersion?
        /// The date of when the donation was made
        public let date: Date

        private init(id: UUID, appVersion: RuleKit.AppVersion?, date: Date) {
            self.id = id
            self.appVersion = appVersion
            self.date = date
        }

        static var now: Donation {
            .init(id: UUID(), appVersion: .current, date: Date())
        }
    }

    /// Represent multiple donations for a specific event.
    /// Since a lot of donations might occurs, and to prevent storing them all, only count, first and last are available.
    public struct Donations: Sendable, Codable {
        static let empty = Donations(count: 0, first: nil, last: nil)

        /// The amount of time this donation have been made since last reset
        public let count: Int
        /// The first donation made since last reset
        public let first: Donation?
        /// The last donation made since last reset
        public let last: Donation?
    }
}

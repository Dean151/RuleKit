//
//  Event.swift
//

import Foundation

public struct Event: Sendable, RawRepresentable, ExpressibleByStringLiteral {
    public let rawValue: String

    public var donations: Event.Donations {
        get async {
            await RuleKit.internal.donations(for: self)
        }
    }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }

    public func donate() async {
        await RuleKit.internal.donate(self)
    }

    public func sendDonation() {
        Task(priority: .utility) {
            await donate()
        }
    }

    public func reset() async {
        await RuleKit.internal.reset(self)
    }

    public func resetDonation() {
        Task(priority: .utility) {
            await reset()
        }
    }
}

public struct DonatedEvent {
    public let event: Event
    public let donations: Event.Donations
}

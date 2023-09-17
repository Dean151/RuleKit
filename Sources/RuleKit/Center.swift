//
//  Center.swift
//

import Foundation
import OSLog

@MainActor
public final class RuleKit {
    static var `internal` = RuleKit()

    let logger = Logger(subsystem: "RuleKit", category: "logs")

    private var _store: Store?
    var store: Store {
        get throws {
            guard let _store else {
                throw Store.Error.storeNotInitialized
            }
            return _store
        }
    }

    var rules: [Notification.Name: any Rule] = [:]

    private init() {}

    func configure(storeLocation: Store.Location) throws {
        guard _store == nil else {
            throw Store.Error.storeAlreadyConfigured
        }
        _store = try storeLocation.createStore()
    }

    func triggerFulfilledRules() async throws {
        for (notification, rule) in rules {
            guard await rule.isFulfilled else {
                continue
            }
            let queue = rule.firstOption(ofType: DispatchQueueOption.self)?.queue ?? .main
            queue.async {
                NotificationCenter.default.post(name: notification, object: nil)
            }
            try await store.persist(triggerOf: notification)
        }
    }

    func donations(for event: Event) async -> Event.Donations {
        (try? await store.donations(for: event)) ?? .empty
    }

    func lastTrigger(for notification: Notification.Name) async -> Date? {
        try? await store.lastTrigger(of: notification)
    }

    func donate(_ event: Event) async {
        do {
            let previous = try await store.donations(for: event)
            // Must implement first since it might be used twice (and result having different dates)
            let donation = Event.Donation.now
            let donations = Event.Donations(
                count: previous.count + 1,
                first: previous.first ?? donation,
                last: donation
            )
            try await store.persist(donations, for: event)
            try await triggerFulfilledRules()
        } catch {
            logger.error("Donation failed for event \(event.rawValue) with error: \(error)")
        }
    }

    func reset(_ event: Event) async {
        do {
            try await store.persist(.empty, for: event)
        } catch {
            logger.error("Reseting donations failed for event \(event.rawValue) with error: \(error)")
        }
    }
}

// MARK: Public front

extension RuleKit {
    /// Configure once the RuleKit in order to start donating and fetching event donations.
    /// You cannot configure more than once, or storeAlreadyConfigured error will be thrown
    /// - Parameter storeLocation: Configure where the store file should be located. Allow to share the store in an app group if you requires it, and also arbitrary store location.
    public static func configure(storeLocation: Store.Location) throws {
        try RuleKit.internal.configure(storeLocation: storeLocation)
    }

    public static func setRule(triggering notification: Notification.Name, options: [any RuleOption] = [], _ rule: Rule) {
        RuleKit.internal.rules[notification] = options.isEmpty ? rule : RuleWithOptions(options: options, notification: notification, rule: rule)
    }
}

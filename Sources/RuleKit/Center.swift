//
//  Center.swift
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

    var rules: [(rule: any Rule, trigger: any Trigger)] = []

    private init() {}

    func configure(storeLocation: Store.Location) throws {
        guard _store == nil else {
            throw Store.Error.storeAlreadyConfigured
        }
        _store = try storeLocation.createStore()
    }

    func triggerFulfilledRules() async throws {
        for (rule, trigger) in rules {
            guard await rule.isFulfilled else {
                continue
            }
            let queue = rule.firstOption(ofType: DispatchQueueOption.self)?.queue ?? .main
            queue.async {
                trigger.execute()
            }
            try await store.persist(triggerOf: trigger)
        }
    }

    func donations(for event: Event) async -> Event.Donations {
        (try? await store.donations(for: event)) ?? .empty
    }

    func lastTrigger(for trigger: any Trigger) async -> Date? {
        try? await store.lastTrigger(of: trigger)
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

    /// - Parameter name: A unique name that will be used as an identifier for registering already triggered rules.
    /// - Parameter notification: A notification to trigger when the rules are fulfilled.
    /// - Parameter options: Some facultative options to attach to the rule set
    /// - Parameter rule: The ruleset that need to be fulfilled to trigger the notification
    /// When name is not provided, notification.rawValue is used instead
    public static func setRule(_ name: String? = nil, triggering notification: Notification.Name, options: [any RuleKitOption] = [], _ rule: Rule) {
        let trigger = NotificationCenterTrigger(rawValue: name, notification: notification)
        let rule = options.isEmpty ? rule : RuleWithOptions(options: options, trigger: trigger, rule: rule)
        RuleKit.internal.rules.append((rule, trigger))
    }

    /// - Parameter name: A unique name that will be used as an identifier for registering already triggered rules.
    /// - Parameter callback: A closure callback to trigger when the rules are fulfilled.
    /// - Parameter options: Some facultative options to attach to the rule set
    /// - Parameter rule: The ruleset that need to be fulfilled to trigger the closure
    public static func setRule(_ name: String, triggering callback: @escaping @Sendable () -> Void, options: [any RuleKitOption] = [], _ rule: Rule) {
        let trigger = CallbackTrigger(rawValue: name, callback: callback)
        let rule = options.isEmpty ? rule : RuleWithOptions(options: options, trigger: trigger, rule: rule)
        RuleKit.internal.rules.append((rule, trigger))
    }

    /// - Parameter name: A unique name that will be used as an identifier for registering already triggered rules.
    /// - Parameter callback: A closure callback to trigger when the rules are fulfilled.
    /// - Parameter options: Some facultative options to attach to the rule set
    /// - Parameter rule: The ruleset that need to be fulfilled to trigger the closure
    @available(*, deprecated, message: "Use setRule(_:, callback:, options:, rule:) instead")
    public static func setRule(triggering callback: @escaping @Sendable () -> Void, name: String, options: [any RuleKitOption] = [], _ rule: Rule) {
        setRule(name, triggering: callback, options: options, rule)
    }
}

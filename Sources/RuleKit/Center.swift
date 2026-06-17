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

    private var _store: (any RuleStore)?
    var store: any RuleStore {
        get throws {
            guard let _store else {
                throw Store.Error.storeNotInitialized
            }
            return _store
        }
    }

    var rules: [(rule: any Rule, trigger: any Trigger)] = []

    init(store: (any RuleStore)? = nil) {
        self._store = store
    }

    func configure(storeLocation: Store.Location) throws {
        guard _store == nil else {
            throw Store.Error.storeAlreadyConfigured
        }
        _store = try storeLocation.createStore()
    }

    func triggerFulfilledRules() async {
        guard let store = try? store else {
            return
        }
        await withTaskGroup(of: Void.self) { [store, logger] group in
            for (rule, trigger) in rules {
                group.addTask {
                    guard await rule.isFulfilled else {
                        return
                    }
                    // Atomically claim the trigger before firing: this records the
                    // fire and enforces any frequency throttle in a single step, so
                    // concurrent donations cannot race between checking the throttle
                    // and recording the fire and thus both fire.
                    let throttle = rule.firstOption(ofType: TriggerFrequencyOption.self)?.frequency.component
                    do {
                        guard try await store.claimTrigger(for: trigger, notBefore: throttle) else {
                            return
                        }
                    } catch {
                        // Isolate per-rule failures: a claim error (e.g. disk I/O)
                        // must skip only this rule, not cancel sibling rules in the group.
                        logger.error("Claiming trigger \(trigger.rawValue) failed with error: \(error)")
                        return
                    }
                    // Apply any delay only after the trigger is claimed, so the
                    // actual firing is delayed while throttled rules are skipped
                    // immediately. A cancelled delay skips firing this time.
                    if let delay = rule.firstOption(ofType: DelayOption.self) {
                        do {
                            try await delay.wait()
                        } catch {
                            return
                        }
                    }
                    // Fire on the chosen queue and await the execution, so this
                    // structured task does not complete before the trigger has run.
                    let queue = rule.firstOption(ofType: DispatchQueueOption.self)?.queue ?? .main
                    await withCheckedContinuation { continuation in
                        queue.async {
                            trigger.execute()
                            continuation.resume()
                        }
                    }
                }
            }
        }
    }

    func donations(for event: Event) async -> Event.Donations {
        (try? await store.donations(for: event)) ?? .empty
    }

    func donate(_ event: Event) async {
        do {
            try await store.incrementDonation(for: event)
            await triggerFulfilledRules()
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

    func register(rule: any Rule, trigger: any Trigger) {
        if rules.contains(where: { $0.trigger.rawValue == trigger.rawValue }) {
            logger.warning("A rule is already registered for trigger name \"\(trigger.rawValue, privacy: .public)\". Both rules will share the same trigger record and frequency throttle; use a distinct name to keep them independent.")
        }
        rules.append((rule, trigger))
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

    /// - Parameter name: A unique identifier used to record this rule's fires (and to enforce its frequency throttle). Defaults to `notification.rawValue`. Reusing a name across rules makes them share one trigger record and throttle; a warning is logged when a collision is detected.
    /// - Parameter notification: A notification to trigger when the rules are fulfilled.
    /// - Parameter options: Some facultative options to attach to the rule set
    /// - Parameter rule: The ruleset that need to be fulfilled to trigger the notification
    public static func setRule(_ name: String? = nil, triggering notification: Notification.Name, options: [any RuleKitOption] = [], _ rule: Rule) {
        let trigger = NotificationCenterTrigger(rawValue: name, notification: notification)
        let rule = options.isEmpty ? rule : RuleWithOptions(options: options, trigger: trigger, rule: rule)
        RuleKit.internal.register(rule: rule, trigger: trigger)
    }

    /// - Parameter name: A unique identifier used to record this rule's fires (and to enforce its frequency throttle). Reusing a name across rules makes them share one trigger record and throttle; a warning is logged when a collision is detected.
    /// - Parameter callback: A closure callback to trigger when the rules are fulfilled.
    /// - Parameter options: Some facultative options to attach to the rule set
    /// - Parameter rule: The ruleset that need to be fulfilled to trigger the closure
    public static func setRule(_ name: String, triggering callback: @escaping @Sendable () -> Void, options: [any RuleKitOption] = [], _ rule: Rule) {
        let trigger = CallbackTrigger(rawValue: name, callback: callback)
        let rule = options.isEmpty ? rule : RuleWithOptions(options: options, trigger: trigger, rule: rule)
        RuleKit.internal.register(rule: rule, trigger: trigger)
    }
}

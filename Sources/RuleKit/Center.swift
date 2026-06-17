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

    /// Delayed triggers whose delay is still running. They fire detached from the
    /// donation that scheduled them, so donating never blocks on a rule's delay.
    /// Keyed so each task can remove itself once it finishes.
    var pendingTriggers: [UUID: Task<Void, Never>] = [:]

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
                group.addTask { [weak self] in
                    guard await rule.isFulfilled else {
                        return
                    }
                    let throttle = rule.firstOption(ofType: TriggerFrequencyOption.self)?.frequency.component
                    guard let delay = rule.firstOption(ofType: DelayOption.self) else {
                        // No delay: claim and fire within the donation's structured
                        // task group, so the donation reflects an immediate trigger.
                        await RuleKit.claimAndFire(rule: rule, trigger: trigger, throttle: throttle, store: store, logger: logger)
                        return
                    }
                    // Skip a rule that is already throttled before waiting out its
                    // delay (cheap, non-authoritative; the claim later re-checks
                    // atomically), so throttled rules are still dropped immediately.
                    do {
                        if try await store.isThrottled(for: trigger, notBefore: throttle) {
                            return
                        }
                    } catch {
                        logger.error("Reading throttle for trigger \(trigger.rawValue) failed with error: \(error)")
                        return
                    }
                    // A delayed trigger fires detached from this donation, so donating
                    // never blocks on the delay. The claim still happens after the
                    // delay (see `claimAndFire`), keeping the throttle window intact if
                    // the delay is interrupted.
                    await self?.scheduleDelayedTrigger(rule: rule, trigger: trigger, delay: delay, throttle: throttle, store: store)
                }
            }
        }
    }

    /// Spawns a detached task that waits out `delay` and then claims and fires the
    /// trigger. The task is tracked in `pendingTriggers` and removes itself when done.
    private func scheduleDelayedTrigger(rule: any Rule, trigger: any Trigger, delay: DelayOption, throttle: Calendar.Component?, store: any RuleStore) {
        let id = UUID()
        let logger = self.logger
        let task = Task.detached(priority: .utility) { [weak self] in
            // A cancelled delay (task cancellation, or the app being killed mid-delay)
            // leaves the throttle window untouched because nothing is claimed.
            do {
                try await delay.wait()
            } catch {
                await self?.finishPendingTrigger(id)
                return
            }
            await RuleKit.claimAndFire(rule: rule, trigger: trigger, throttle: throttle, store: store, logger: logger)
            await self?.finishPendingTrigger(id)
        }
        pendingTriggers[id] = task
    }

    private func finishPendingTrigger(_ id: UUID) {
        pendingTriggers[id] = nil
    }

    /// Awaits every not-yet-fired delayed trigger. Intended for tests that need to
    /// observe a delayed trigger's effect deterministically.
    func waitForPendingTriggers() async {
        for task in Array(pendingTriggers.values) {
            await task.value
        }
    }

    /// Cancels and forgets every pending delayed trigger.
    func cancelPendingTriggers() {
        for task in pendingTriggers.values {
            task.cancel()
        }
        pendingTriggers.removeAll()
    }

    /// Atomically claims the trigger and, if the claim succeeds, fires it on the
    /// configured queue. Awaits the execution so callers can observe completion.
    private static func claimAndFire(rule: any Rule, trigger: any Trigger, throttle: Calendar.Component?, store: any RuleStore, logger: Logger) async {
        // Atomically claim the trigger: this records the fire and enforces any
        // frequency throttle in a single step, so concurrent donations cannot race
        // between checking the throttle and recording the fire and thus both fire.
        do {
            guard try await store.claimTrigger(for: trigger, notBefore: throttle) else {
                return
            }
        } catch {
            // Isolate per-rule failures: a claim error (e.g. disk I/O) must skip
            // only this rule, not cancel sibling rules.
            logger.error("Claiming trigger \(trigger.rawValue) failed with error: \(error)")
            return
        }
        let queue = rule.firstOption(ofType: DispatchQueueOption.self)?.queue ?? .main
        await withCheckedContinuation { continuation in
            queue.async {
                trigger.execute()
                continuation.resume()
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

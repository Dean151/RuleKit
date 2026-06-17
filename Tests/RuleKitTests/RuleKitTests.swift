//
//  RuleKitTests.swift
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

import Testing
import Foundation
@testable import RuleKit

extension RuleKit.Event {
    static let testEvent: Self = "test.event"
}

/// A thread-safe counter for tallying how many times a trigger actually fired.
/// Legitimate `@unchecked Sendable`: all access is serialized by the lock.
final class FireCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

/// A thread-safe ordered log of trigger fires, used to assert relative firing order.
final class FireRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var fires: [String] = []

    func record(_ label: String) {
        lock.lock()
        fires.append(label)
        lock.unlock()
    }

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return fires
    }
}

/// A store whose `claimTrigger` throws for one specific trigger name and succeeds
/// for all others, so a single rule's claim failure can be simulated in isolation.
actor FailingStore: RuleStore {
    struct InjectedError: Error {}

    let failingTriggerName: String

    init(failingTriggerName: String) {
        self.failingTriggerName = failingTriggerName
    }

    @discardableResult
    func incrementDonation(for event: RuleKit.Event) throws -> RuleKit.Event.Donations {
        .empty
    }

    func donations(for event: RuleKit.Event) throws -> RuleKit.Event.Donations {
        .empty
    }

    func persist(_ donations: RuleKit.Event.Donations, for event: RuleKit.Event) throws {}

    func isThrottled(for trigger: any Trigger, notBefore component: Calendar.Component?) throws -> Bool {
        false
    }

    func claimTrigger(for trigger: any Trigger, notBefore component: Calendar.Component?) throws -> Bool {
        if trigger.rawValue == failingTriggerName {
            throw InjectedError()
        }
        return true
    }
}

/// An in-memory store that mimics the real throttle semantics (a claimed trigger
/// stays throttled) and counts how many claims were attempted, so the firing
/// pipeline's ordering can be observed without touching the filesystem.
actor SpyStore: RuleStore {
    private(set) var claimCount = 0
    private var claimedTriggers: Set<String> = []

    @discardableResult
    func incrementDonation(for event: RuleKit.Event) throws -> RuleKit.Event.Donations {
        .empty
    }

    func donations(for event: RuleKit.Event) throws -> RuleKit.Event.Donations {
        .empty
    }

    func persist(_ donations: RuleKit.Event.Donations, for event: RuleKit.Event) throws {}

    func isThrottled(for trigger: any Trigger, notBefore component: Calendar.Component?) throws -> Bool {
        guard component != nil else {
            return false
        }
        return claimedTriggers.contains(trigger.rawValue)
    }

    func claimTrigger(for trigger: any Trigger, notBefore component: Calendar.Component?) throws -> Bool {
        claimCount += 1
        if component != nil, claimedTriggers.contains(trigger.rawValue) {
            return false
        }
        claimedTriggers.insert(trigger.rawValue)
        return true
    }
}

/// A sleeper that always throws, simulating a delay interrupted by task
/// cancellation or the app being killed mid-delay.
struct ThrowingSleeper: Sleeper {
    struct Interrupted: Error {}
    func sleep() async throws {
        throw Interrupted()
    }
}

// The public API routes through the shared `RuleKit.internal` singleton (a global
// rule list and a single store file), so these tests are serialized and each one
// starts from a clean rule set. The exception is `ruleClaimFailureDoesNotSuppressOtherRules`,
// which drives its own isolated `RuleKit` instance.
@Suite(.serialized)
@MainActor
struct RuleKitTests {
    static let testNotification = Notification.Name("test.notification")
    static let testCallback = "test.callback"

    init() async throws {
        // Configure once; later calls throw storeAlreadyConfigured, which we ignore.
        try? RuleKit.configure(storeLocation: .applicationDefault)
        // The rule list is global; start every test from a clean slate so rules
        // registered by other tests cannot fire during this one.
        RuleKit.internal.rules.removeAll()
        await RuleKit.Event.testEvent.reset()
    }

    @Test("A notification rule posts its notification when fulfilled")
    func notificationRuleTriggers() async {
        RuleKit.setRule(triggering: Self.testNotification, .allOf([
            .event(.testEvent) {
                $0.donations.count > 0
            },
            .condition {
                true
            }
        ]))

        await confirmation("Notification is posted") { posted in
            let token = NotificationCenter.default.addObserver(forName: Self.testNotification, object: nil, queue: nil) { _ in
                posted()
            }
            defer { NotificationCenter.default.removeObserver(token) }
            await RuleKit.Event.testEvent.donate()
        }

        let count = await RuleKit.Event.testEvent.donations.count
        #expect(count == 1)
    }

    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    @Test("A delayed rule fires no sooner than its delay")
    func delayedNotificationRuleRespectsDelay() async {
        let duration = Duration.seconds(5)
        RuleKit.setRule(
            triggering: Self.testNotification,
            options: [.delay(for: duration)],
            .allOf([
                .event(.testEvent) {
                    $0.donations.count > 0
                },
                .condition {
                    true
                }
            ])
        )

        let clock = ContinuousClock()
        let elapsed = await clock.measure {
            await confirmation("Notification is posted after the delay") { posted in
                let token = NotificationCenter.default.addObserver(forName: Self.testNotification, object: nil, queue: nil) { _ in
                    posted()
                }
                defer { NotificationCenter.default.removeObserver(token) }
                await RuleKit.Event.testEvent.donate()
            }
        }
        // The measured duration should be at least the delay configured in the rule.
        #expect(elapsed >= duration)
    }

    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    @Test("Rules are evaluated in parallel, so a rule without a delay fires first")
    func rulesAreEvaluatedInParallel() async {
        let duration = Duration.seconds(5)
        let recorder = FireRecorder()

        RuleKit.setRule("\(Self.testCallback).delayed", triggering: {
            recorder.record("delayed")
        }, options: [.delay(for: duration)], .anyOf([
            .event(.testEvent) {
                $0.donations.count > 0
            }
        ]))

        RuleKit.setRule("\(Self.testCallback).immediate", triggering: {
            recorder.record("immediate")
        }, options: [], .anyOf([
            .event(.testEvent) {
                $0.donations.count > 0
            }
        ]))

        // `donate` awaits the whole task group, so both rules have fired by the time
        // it returns; the rule without the delay option must have fired first.
        await RuleKit.Event.testEvent.donate()
        #expect(recorder.values == ["immediate", "delayed"])
    }

    @Test("A notification rule built with the result builder posts its notification")
    func notificationRuleTriggersWithResultBuilder() async {
        RuleKit.setRule(triggering: Self.testNotification, .allOf {
            EventRule(event: .testEvent) {
                $0.donations.count > 0
            }
            ConditionRule {
                true
            }
        })

        await confirmation("Notification is posted") { posted in
            let token = NotificationCenter.default.addObserver(forName: Self.testNotification, object: nil, queue: nil) { _ in
                posted()
            }
            defer { NotificationCenter.default.removeObserver(token) }
            await RuleKit.Event.testEvent.donate()
        }

        let count = await RuleKit.Event.testEvent.donations.count
        #expect(count == 1)
    }

    @Test("A callback rule invokes its callback when fulfilled")
    func callbackRuleTriggers() async {
        let counter = FireCounter()
        RuleKit.setRule(Self.testCallback, triggering: {
            counter.increment()
        }, .anyOf([
            .event(.testEvent) {
                $0.donations.count > 0
            }
        ]))

        await RuleKit.Event.testEvent.donate()

        #expect(counter.value == 1)
        let count = await RuleKit.Event.testEvent.donations.count
        #expect(count == 1)
    }

    @Test("A callback rule built with the result builder invokes its callback")
    func callbackRuleTriggersWithResultBuilder() async {
        let counter = FireCounter()
        RuleKit.setRule(Self.testCallback, triggering: {
            counter.increment()
        }, .anyOf {
            EventRule(event: .testEvent) {
                $0.donations.count > 0
            }
        })

        await RuleKit.Event.testEvent.donate()

        #expect(counter.value == 1)
        let count = await RuleKit.Event.testEvent.donations.count
        #expect(count == 1)
    }

    @Test("A frequency throttle fires exactly once under concurrent donations")
    func concurrentDonationsRespectTriggerFrequency() async {
        // Unique event + rule name so a previous run's persisted `lastTrigger`
        // (which `reset()` does not clear) cannot throttle this run, and so no
        // other registered rule listens to this event.
        let runID = UUID().uuidString
        let event = RuleKit.Event(rawValue: "test.concurrent.event.\(runID)")
        let ruleName = "test.concurrent.rule.\(runID)"

        let counter = FireCounter()
        RuleKit.setRule(
            ruleName,
            triggering: { counter.increment() },
            options: [.triggerFrequency(.daily)],
            .event(event) { $0.donations.count > 0 }
        )

        // Fire many donations concurrently; each `donate` awaits its own firing,
        // so once the group completes every fire has happened.
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<50 {
                group.addTask {
                    await event.donate()
                }
            }
        }

        #expect(
            counter.value == 1,
            "Expected exactly one fire under a daily throttle regardless of concurrency."
        )
    }

    @Test("A file-scheme directory URL is accepted as a store location")
    func urlStoreLocationAcceptsDirectory() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let location = RuleKit.Store.Location.url(directory)
        let resolved = try location.url
        #expect(resolved == directory)
    }

    @Test("A non-directory URL is rejected as a store location")
    func urlStoreLocationRejectsNonDirectory() {
        let file = URL(fileURLWithPath: "\(NSTemporaryDirectory())RuleKitNotADirectory", isDirectory: false)
        let location = RuleKit.Store.Location.url(file)
        #expect(throws: RuleKit.Store.Error.self) {
            _ = try location.url
        }
    }

    @Test("A rule whose claim fails does not suppress its sibling rules")
    func ruleClaimFailureDoesNotSuppressOtherRules() async {
        let failingName = "test.finding3.failing"
        let healthyName = "test.finding3.healthy"

        // Drive a dedicated RuleKit instance with an injected failing store, so the
        // rules' fulfillment does not depend on the shared singleton's store.
        let kit = RuleKit(store: FailingStore(failingTriggerName: failingName))

        let failingCounter = FireCounter()
        let healthyCounter = FireCounter()

        kit.register(
            rule: ConditionRule { true },
            trigger: CallbackTrigger(rawValue: failingName, callback: { failingCounter.increment() })
        )
        kit.register(
            rule: ConditionRule { true },
            trigger: CallbackTrigger(rawValue: healthyName, callback: { healthyCounter.increment() })
        )

        // `donate` awaits firing, so the healthy rule has fired by the time it returns.
        await kit.donate("test.finding3.event")

        #expect(healthyCounter.value == 1, "The healthy rule must fire even though a sibling rule's claim failed.")
        #expect(failingCounter.value == 0, "The rule whose claim threw must not fire.")
    }

    @Test("An interrupted delay does not consume the throttle window")
    func interruptedDelayPreservesThrottleWindow() async {
        let store = SpyStore()
        let kit = RuleKit(store: store)
        let counter = FireCounter()
        let trigger = CallbackTrigger(rawValue: "test.interrupted.delay", callback: { counter.increment() })

        // A throttled, delayed rule whose delay is interrupted before it completes.
        kit.register(
            rule: RuleWithOptions(
                options: [.triggerFrequency(.daily), DelayOption(sleeper: ThrowingSleeper())],
                trigger: trigger,
                rule: ConditionRule { true }
            ),
            trigger: trigger
        )

        await kit.donate("test.interrupted.delay.event")

        #expect(counter.value == 0, "An interrupted delay must not fire the trigger.")
        #expect(
            await store.claimCount == 0,
            "An interrupted delay must not claim the trigger, so its throttle window stays open."
        )
    }
}

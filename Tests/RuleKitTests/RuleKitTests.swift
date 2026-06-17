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

import XCTest
import RuleKit

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

@MainActor
final class RuleKitTests: XCTestCase {
    static let testNotification = Notification.Name("test.notification")
    static let testCallback = "test.callback"

    override class func setUp() {
        do {
            try RuleKit.configure(storeLocation: .applicationDefault)
        } catch {}
    }

    func testNotificationRuleTriggering() async throws {
        await RuleKit.Event.testEvent.reset()
        RuleKit.setRule(triggering: Self.testNotification, .allOf([
            .event(.testEvent) {
                $0.donations.count > 0
            },
            .condition {
                true
            }
        ]))
        let expectation = expectation(forNotification: Self.testNotification, object: nil)
        await RuleKit.Event.testEvent.donate()
        await fulfillment(of: [expectation])
        let count = await RuleKit.Event.testEvent.donations.count
        XCTAssertEqual(1, count)
    }
    
    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    func testNotificationRuleTriggeringDelayed() async throws {
        let duration = Duration.seconds(5)
        await RuleKit.Event.testEvent.reset()
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
        let expectation = expectation(forNotification: Self.testNotification, object: nil)
        let clock = ContinuousClock()
        let measuredDuration = await clock.measure {
            await RuleKit.Event.testEvent.donate()
            await fulfillment(of: [expectation])
        }
        // Measured duration should be at least the duration in the Rule Options
        XCTAssertTrue(measuredDuration >= duration)
    }

    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    func testParallelizedTrigger() async throws {
        let duration = Duration.seconds(5)
        await RuleKit.Event.testEvent.reset()
        
        let delayExpectation = XCTestExpectation()
        RuleKit.setRule("\(Self.testCallback).delayed", triggering: {
            print("Rule with DelayOption triggered")
            delayExpectation.fulfill()
        }, options: [.delay(for: duration)], .anyOf([
            .event(.testEvent) {
                $0.donations.count > 0
            }
        ]))

        let expectation = XCTestExpectation()
        RuleKit.setRule("\(Self.testCallback).immediate", triggering: {
            print("Rule without DelayOption triggered")
            expectation.fulfill()
        }, options: [], .anyOf([
            .event(.testEvent) {
                $0.donations.count > 0
            }
        ]))
        
        await RuleKit.Event.testEvent.donate()
        // If the rules are checked in parallel, then the rule without delay option should
        // get triggered before the rule with the delay option.
        await fulfillment(of: [expectation, delayExpectation], enforceOrder: true)
    }

    func testNotificationRuleTriggeringResultBuilder() async throws {
        await RuleKit.Event.testEvent.reset()
        RuleKit.setRule(triggering: Self.testNotification, .allOf {
            EventRule(event: .testEvent) {
                $0.donations.count > 0
            }
            ConditionRule {
                true
            }
        })
        let expectation = expectation(forNotification: Self.testNotification, object: nil)
        await RuleKit.Event.testEvent.donate()
        await fulfillment(of: [expectation])
        let count = await RuleKit.Event.testEvent.donations.count
        XCTAssertEqual(1, count)
    }

    func testCallbackRuleTriggering() async throws {
        await RuleKit.Event.testEvent.reset()
        let expectation = XCTestExpectation()
        RuleKit.setRule(Self.testCallback, triggering: {
            expectation.fulfill()
        }, .anyOf([
            .event(.testEvent) {
                $0.donations.count > 0
            }
        ]))
        await RuleKit.Event.testEvent.donate()
        await fulfillment(of: [expectation])
        let count = await RuleKit.Event.testEvent.donations.count
        XCTAssertEqual(1, count)
    }

    func testCallbackRuleTriggeringResultBuilder() async throws {
        await RuleKit.Event.testEvent.reset()
        let expectation = XCTestExpectation()
        RuleKit.setRule(Self.testCallback, triggering: {
            expectation.fulfill()
        }, .anyOf {
            EventRule(event: .testEvent) {
                $0.donations.count > 0
            }
        })
        await RuleKit.Event.testEvent.donate()
        await fulfillment(of: [expectation])
        let count = await RuleKit.Event.testEvent.donations.count
        XCTAssertEqual(1, count)
    }

    /// Findings 2–4: under concurrent donations, the `.triggerFrequency` throttle is
    /// a check-then-act race. The frequency gate reads `lastTrigger` inside the rule
    /// evaluation, but the trigger is only *recorded* after firing and after several
    /// suspension points. Many concurrent donations can all read a stale (nil)
    /// `lastTrigger`, pass the gate, and fire — so a `.daily`-throttled rule fires
    /// more than once.
    ///
    /// Expected behaviour: exactly one fire. This test is expected to FAIL today,
    /// demonstrating the TOCTOU race; it should pass once trigger claiming is atomic.
    func testConcurrentDonationsRespectTriggerFrequency() async throws {
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

        // Fire many donations concurrently to widen the race window.
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<50 {
                group.addTask {
                    await event.donate()
                }
            }
        }

        // Triggers are dispatched fire-and-forget onto a DispatchQueue (default
        // `.main`), so the task group can complete before they actually run.
        // Yield the main thread long enough for the dispatched blocks to drain.
        try await Task.sleep(nanoseconds: 1_000_000_000)

        let fires = counter.value
        XCTAssertEqual(
            fires,
            1,
            "Expected exactly one fire under a daily throttle regardless of concurrency, but the trigger fired \(fires) times (TOCTOU race in trigger gating)."
        )
    }
}

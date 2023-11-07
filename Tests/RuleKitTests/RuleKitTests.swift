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

final class RuleKitTests: XCTestCase {
    static let testNotification = Notification.Name("test.notification")
    static let testCallback = "test.callback"

    @MainActor 
    override class func setUp() {
        do {
            try RuleKit.configure(storeLocation: .applicationDefault)
        } catch {}
    }

    func testNotificationRuleTriggering() async throws {
        await RuleKit.Event.testEvent.reset()
        await RuleKit.setRule(triggering: Self.testNotification, .allOf([
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

    func testNotificationRuleTriggeringResultBuilder() async throws {
        await RuleKit.Event.testEvent.reset()
        await RuleKit.setRule(triggering: Self.testNotification, .allOf {
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
        await RuleKit.setRule(Self.testCallback, triggering: {
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
        await RuleKit.setRule(Self.testCallback, triggering: {
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
}

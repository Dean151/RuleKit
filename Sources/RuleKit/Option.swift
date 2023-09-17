//
//  Option.swift
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

public protocol RuleOption {
    /// If this returns true, the rule will never be fulfilled, and the notification prevented
    /// Defaults to false
    func preventRuleFulfillment(for notification: Notification.Name) async -> Bool
}
extension RuleOption {
    public func preventRuleFulfillment(for notification: Notification.Name) async -> Bool {
        false
    }
}

// MARK: - TriggerFrequency

public struct TriggerFrequencyOption: RuleOption {
    public enum Frequency {
        case hourly
        case daily
        case weekly
        case monthly
        case quarterly
        case yearly

        var component: Calendar.Component {
            switch self {
            case .hourly:
                return .hour
            case .daily:
                return .day
            case .weekly:
                return .weekOfYear
            case .monthly:
                return .month
            case .quarterly:
                return .quarter
            case .yearly:
                return .year
            }
        }
    }

    let frequency: Frequency

    // Thank you, Dave Delong for your thoughtful advices on handling dates at NSSpain XI
    public func preventRuleFulfillment(for notification: Notification.Name) async -> Bool {
        guard let lastTrigger = await RuleKit.internal.lastTrigger(for: notification) else {
            return false
        }
        guard let earliestDateForNextRuleTrigger = Calendar.current.date(byAdding: frequency.component, value: 1, to: lastTrigger) else {
            return false
        }
        if earliestDateForNextRuleTrigger > Date() {
            // If we are before the earliest next trigger date, prevent trigger by returning true
            return true
        }
        return false
    }
}

extension RuleOption where Self == TriggerFrequencyOption {
    /// Throttle down the number of time the trigger is called.
    /// By default, each time an event is triggered and that the condition are true, the event will dispatch
    public static func triggerFrequency(_ frequency: TriggerFrequencyOption.Frequency) -> RuleOption {
        TriggerFrequencyOption(frequency: frequency)
    }
}

// MARK: - DispatchQueue

public struct DispatchQueueOption: RuleOption {
    let queue: DispatchQueue
}

extension RuleOption where Self == DispatchQueueOption {
    /// Publish the notification on a specific dispatch queue.
    /// By default, notification will be sent on the main queue.
    public static func dispatchQueue(_ queue: DispatchQueue) -> RuleOption {
        DispatchQueueOption(queue: queue)
    }
}

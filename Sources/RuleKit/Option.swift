//
//  Option.swift
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
        if earliestDateForNextRuleTrigger > .now {
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

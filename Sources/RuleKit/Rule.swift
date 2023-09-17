//
//  Rule.swift
//

import Foundation

public protocol Rule {
    var isFulfilled: Bool { get async }
}

extension Rule {
    func firstOption<T: RuleOption>(ofType: T.Type) -> T? {
        (self as? RuleWithOptions)?.firstOption(ofType: T.self)
    }
}

// MARK: Event rule

public struct EventRule: Rule {
    let event: Event
    let condition: (DonatedEvent) -> Bool

    public var isFulfilled: Bool {
        get async {
            let donations = await event.donations
            if condition(DonatedEvent(event: event, donations: donations)) {
                return true
            }
            return false
        }
    }

    init(event: Event, condition: @escaping (DonatedEvent) -> Bool) {
        self.event = event
        self.condition = condition
    }
}

extension Rule where Self == EventRule {
    public static func event(_ event: Event, condition: @escaping (DonatedEvent) -> Bool) -> Rule {
        EventRule(event: event, condition: condition)
    }
}

// MARK: OneOf rule

public struct AnyOfRule: Rule {
    let rules: [any Rule]

    public var isFulfilled: Bool {
        get async {
            for rule in rules where await rule.isFulfilled {
                return true
            }
            return false
        }
    }
}

extension Rule where Self == AnyOfRule {
    public static func anyOf(_ rules: [any Rule]) -> Rule {
        AnyOfRule(rules: rules)
    }
}

// MARK: AllOf Rule

public struct AllOfRule: Rule {
    let rules: [any Rule]

    public var isFulfilled: Bool {
        get async {
            for rule in rules where await !rule.isFulfilled {
                return false
            }
            return true
        }
    }
}

extension Rule where Self == AllOfRule {
    public static func allOf(_ rules: [any Rule]) -> Rule {
        AllOfRule(rules: rules)
    }
}

// MARK: Rule with options

struct RuleWithOptions: Rule {
    let options: [RuleOption]
    let notification: Notification.Name
    let rule: Rule

    var isFulfilled: Bool {
        get async {
            for option in options where await option.preventRuleFulfillment(for: notification) {
                return false
            }
            return await rule.isFulfilled
        }
    }

    func firstOption<T: RuleOption>(ofType: T.Type) -> T? {
        return options.first(where: { $0 is T }) as? T
    }
}

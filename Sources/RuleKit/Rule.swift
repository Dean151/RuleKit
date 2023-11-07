//
//  Rule.swift
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

public protocol Rule {
    var isFulfilled: Bool { get async }
}

extension Rule {
    func firstOption<T: RuleKitOption>(ofType: T.Type) -> T? {
        (self as? RuleWithOptions)?.firstOption(ofType: T.self)
    }
}

@resultBuilder public struct RuleBuilder {
    public static func buildBlock(_ components: Rule...) -> [any Rule] {
        components
    }

    public static func buildBlock(_ components: [Rule]...) -> [Rule] {
        components.flatMap { $0 }
    }

    public static func buildExpression(_ expression: Rule) -> [Rule] {
        [expression]
    }

    public static func buildExpression(_ expression: [Rule]) -> [Rule] {
        expression
    }

    public static func buildOptional(_ component: [Rule]?) -> [Rule] {
        component ?? []
    }

    public static func buildEither(first component: [Rule]) -> [Rule] {
        component
    }

    public static func buildEither(second component: [Rule]) -> [Rule] {
        component
    }

    public static func buildArray(_ components: [[Rule]]) -> [Rule] {
        components.flatMap { $0 }
    }

    public static func buildLimitedAvailability(_ component: [Rule]) -> [Rule] {
        component
    }
}

// MARK: Condition rule

public struct ConditionRule: Rule {
    let condition: () async -> Bool

    public var isFulfilled: Bool {
        get async {
            await condition()
        }
    }

    public init(condition: @escaping () async -> Bool) {
        self.condition = condition
    }
}

extension Rule where Self == ConditionRule {
    public static func condition(_ condition: @escaping () -> Bool) async -> Rule {
        ConditionRule(condition: condition)
    }
}

// MARK: Event rule

public struct EventRule: Rule {
    let event: RuleKit.Event
    let condition: (RuleKit.DonatedEvent) async -> Bool

    public var isFulfilled: Bool {
        get async {
            let donations = await event.donations
            if await condition(RuleKit.DonatedEvent(event: event, donations: donations)) {
                return true
            }
            return false
        }
    }

    public init(event: RuleKit.Event, condition: @escaping (RuleKit.DonatedEvent) async -> Bool) {
        self.event = event
        self.condition = condition
    }
}

extension Rule where Self == EventRule {
    public static func event(_ event: RuleKit.Event, condition: @escaping (RuleKit.DonatedEvent) -> Bool) async -> Rule {
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

    public init(rules: [any Rule]) {
        self.rules = rules
    }

    public init(@RuleBuilder rules: () -> [any Rule]) {
        self.rules = rules()
    }
}

extension Rule where Self == AnyOfRule {
    public static func anyOf(_  rules: [any Rule]) -> Rule {
        AnyOfRule(rules: rules)
    }

    public static func anyOf(@RuleBuilder _  rules: () -> [any Rule]) -> Rule {
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

    public init(rules: [any Rule]) {
        self.rules = rules
    }

    public init(@RuleBuilder rules: () -> [any Rule]) {
        self.rules = rules()
    }
}

extension Rule where Self == AllOfRule {
    public static func allOf(_  rules: [any Rule]) -> Rule {
        AllOfRule(rules: rules)
    }

    public static func allOf(@RuleBuilder _  rules: () -> [any Rule]) -> Rule {
        AllOfRule(rules: rules)
    }
}

// MARK: Rule with options

struct RuleWithOptions: Rule {
    let options: [RuleKitOption]
    let trigger: any Trigger
    let rule: Rule

    var isFulfilled: Bool {
        get async {
            for option in options where await option.preventRuleFulfillment(for: trigger) {
                return false
            }
            return await rule.isFulfilled
        }
    }

    func firstOption<T: RuleKitOption>(ofType: T.Type) -> T? {
        return options.first(where: { $0 is T }) as? T
    }
}

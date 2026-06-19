# Getting Started

Configure RuleKit, declare events, register a rule, and donate events from your app.

## Overview

RuleKit revolves around three ideas:

- **Events** are things that happen in your app. You *donate* them as they occur.
- **Rules** describe the conditions — over those donations — that must hold before
  something should happen.
- **Triggers** are what RuleKit runs when a rule is fulfilled: a closure, or a posted
  `Notification`.

Every time you donate an event, RuleKit re-evaluates every registered rule and fires
the triggers whose rules now pass.

## Configure the store

Call ``RuleKit/configure(storeLocation:)`` once, early in your app's lifecycle (for
example in your `App` initializer or `application(_:didFinishLaunchingWithOptions:)`).
Configuring twice throws.

```swift
try RuleKit.configure(storeLocation: .applicationDefault)
```

The store is where event donations and trigger history are persisted. Pick the location
that matches your app:

- term ``RuleKit/Store/Location/applicationDefault``: Stores the data in your app's
  Documents directory. The simplest choice for a single-target app.
- term ``RuleKit/Store/Location/groupContainer(identifier:)``: Stores the data in a
  shared App Group container, so an app extension and its host app can share donations.
- term ``RuleKit/Store/Location/url(_:)``: Stores the data in a directory URL you
  provide. Use this when you need full control over the location.

> Note: On Linux and Android, prefer ``RuleKit/Store/Location/url(_:)``. App Group
> containers are an Apple sandbox concept and ``RuleKit/Store/Location/groupContainer(identifier:)``
> throws there, while ``RuleKit/Store/Location/applicationDefault`` resolves to
> `~/Documents`, which may not exist on a server. Note also that
> ``RuleKit/AppVersion/current`` is `nil` without an `Info.plist`, so version-based
> conditions always compare against `nil`.

## Declare your events

Extend ``RuleKit/Event`` with static constants. ``RuleKit/Event`` is
`ExpressibleByStringLiteral`, so each one is just a stable identifier string.

```swift
extension RuleKit.Event {
    static let appStarted: Self = "appStarted"
    static let entityCreated: Self = "entityCreated"
    static let promptAttempt: Self = "promptAttempt"
}
```

## Register a rule

A rule pairs a *trigger* with a *ruleset*. RuleKit offers two kinds of trigger.

### Triggering a closure

Give the rule a unique name and a closure to run:

```swift
RuleKit.setRule("askForReview", triggering: { requestReview() }, options: .triggerFrequency(.monthly)) {
    .event(.appStarted, atLeast: 3) && .event(.entityCreated, atLeast: 5)
}
```

### Triggering a notification

Alternatively, post a `Notification` and react to it where it makes sense in your UI —
useful when the side effect (like SwiftUI's `requestReview`) belongs to the view layer.

```swift
extension Notification.Name {
    static let requestReviewPrompt = Notification.Name("RequestReviewPrompt")
}

RuleKit.setRule(triggering: .requestReviewPrompt, options: .triggerFrequency(.monthly)) {
    .event(.appStarted, atLeast: 3) && .event(.entityCreated, atLeast: 5)
}
```

```swift
import StoreKit
import SwiftUI

struct ContentView: View {
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        Text("Hello, World!")
            .onReceive(NotificationCenter.default.publisher(for: .requestReviewPrompt)) { _ in
                requestReview()
                RuleKit.Event.promptAttempt.sendDonation()
            }
    }
}
```

> Tip: `options` is variadic and the ruleset is a trailing closure, so a single option
> no longer needs to be wrapped in an array. The array form
> (`options: [.triggerFrequency(.monthly)], .allOf([...])`) is still available.

For the full vocabulary of rules — `allOf`, `anyOf`, `noneOf`, `atLeast`, `not`, the
`&&`/`||`/`!` operators, recency helpers, and the donation properties you can read
inside a condition — see <doc:ComposingRules>.

## Donate events

Donate an event wherever it meaningfully happens. The asynchronous form returns
immediately; the `async` form lets you await persistence.

```swift
// Fire-and-forget (schedules the donation on a utility task)
RuleKit.Event.appStarted.sendDonation()

// Awaitable
await RuleKit.Event.entityCreated.donate()
```

As soon as a donation lands, every registered rule is re-evaluated, and any whose
ruleset now passes fires its trigger.

## Reset donations

To start a count over — for example after the user completed the flow a rule was
nudging toward — reset an event's donations to zero.

```swift
// Fire-and-forget
RuleKit.Event.appStarted.resetDonations()

// Awaitable
await RuleKit.Event.appStarted.reset()
```

## Manage registered rules

Rules can be inspected and removed at runtime. The identifier is the `name` you passed
to ``RuleKit/setRule(_:triggering:options:_:)``; for a notification rule registered
without an explicit name, it is the notification's `rawValue`.

```swift
// Register only if it isn't already there (registering again replaces it and logs a warning)
if !RuleKit.isRuleRegistered(named: "askForReview") {
    RuleKit.setRule("askForReview", triggering: { /* … */ }) { /* … */ }
}

// Every currently registered rule, in registration order
let names = RuleKit.registeredRuleNames

// Stop a rule from ever evaluating or firing again
RuleKit.removeRule(named: "askForReview")
```

## Tune when and how a trigger fires

Options refine a fulfilled rule's firing behavior. Pass any combination:

- term ``TriggerFrequencyOption``: Throttle how often the trigger may fire — for
  example `.triggerFrequency(.monthly)`, or `.triggerFrequency(.every(.day, count: 3))`.
  Without it, the trigger fires on every donation that satisfies the rule.
- term ``DispatchQueueOption``: Choose the `DispatchQueue` the trigger runs on. Defaults
  to the main actor.
- term ``DelayOption``: Wait before firing once the rule is fulfilled, with
  `.delay(for:)` or `.delay(nanoseconds:)`. The rule is re-checked after the delay, so a
  condition that stops holding in the meantime won't fire.

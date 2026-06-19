# RuleKit

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FDean151%2FRuleKit%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/Dean151/RuleKit)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FDean151%2FRuleKit%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/Dean151/RuleKit)

A TipKit-style API to trigger an arbitrary closure, or an `NSNotification`, based on events and conditions.

You *donate* events from meaningful places in your app, describe the *rules* that must hold, and RuleKit fires your *trigger* the moment they do.

## Usecases
- Open your paywall from time to time
- Prompt your user to leave an App Store review
- Watch for and send achievements to Game Center with GameKit
- Surface a shortcut for an action the user performs often
- ...

## Requirements
- Swift 6.0+ (Xcode 16+)
- iOS 14+, iPadOS 14+, tvOS 14+, watchOS 7+, macOS 11+
- Linux, Android

## Installation

Install using Swift Package Manager:
```swift
dependencies: [
    .package(url: "https://github.com/Dean151/RuleKit.git", from: "0.5.0"),
],
targets: [
    .target(name: "MyTarget", dependencies: [
        .product(name: "RuleKit", package: "RuleKit"),
    ]),
]
```

## Quick start

```swift
import RuleKit

// 1. Configure once, at launch.
try RuleKit.configure(storeLocation: .applicationDefault)

// 2. Declare your events.
extension RuleKit.Event {
    static let appStarted: Self = "appStarted"
    static let entityCreated: Self = "entityCreated"
}

// 3. Register a rule and what it triggers.
RuleKit.setRule("askForReview", triggering: { requestReview() }, options: .triggerFrequency(.monthly)) {
    .event(.appStarted, atLeast: 3) && .event(.entityCreated, atLeast: 5)
}

// 4. Donate events where they happen.
RuleKit.Event.appStarted.sendDonation()
await RuleKit.Event.entityCreated.donate()
```

As soon as an event is donated, RuleKit re-evaluates every rule and fires the triggers whose rules now pass.

Rules can trigger a closure (above) or post a `Notification` — handy when the side effect belongs to your UI layer. They compose with `.allOf` / `.anyOf` / `.noneOf` / `.atLeast` / `.not` (and the `&&`, `||`, `!` operators), and conditions can read each event's donation history (count, dates, app version, recency, cooldowns).

## Documentation

The full guide lives in the DocC documentation, hosted on the [Swift Package Index](https://swiftpackageindex.com/Dean151/RuleKit/documentation/rulekit):

- **Getting Started** — configuring the store, declaring events, registering closure- and notification-based rules, donating and resetting events, managing rules, and the available options (`triggerFrequency`, `dispatchQueue`, `delay`).
- **Composing Rules** — the full rule vocabulary: event conditions and shorthands, combinators, operators, constants, and the donation properties available inside a condition.

You can also browse it locally in Xcode via **Product ▸ Build Documentation**.

## Contribute
You are encouraged to contribute to this repository by opening issues or pull requests for bug fixes, improvement requests, or support.
Suggestions for contributing:
- Improving documentation
- Adding more tests
- Adding new rules, options, or properties for more use cases

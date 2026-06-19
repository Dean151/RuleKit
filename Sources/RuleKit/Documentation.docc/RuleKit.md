# ``RuleKit``

Trigger a closure or a notification when a set of events and conditions are met.

## Overview

RuleKit gives you a small, TipKit-style API for one job: run a closure — or post a
`Notification` — the moment a set of rules you describe become fulfilled.

You *donate* events from meaningful places in your app (the app started, the user
created an item, a paywall was shown). RuleKit persists a lightweight summary of those
donations and, on every new donation, re-evaluates your rules. When they all pass, your
trigger fires.

```swift
// 1. Configure once, at launch.
try RuleKit.configure(storeLocation: .applicationDefault)

// 2. Declare your events.
extension RuleKit.Event {
    static let appStarted: Self = "appStarted"
    static let entityCreated: Self = "entityCreated"
}

// 3. Register a rule that triggers a closure.
RuleKit.setRule("askForReview", triggering: { requestReview() }, options: .triggerFrequency(.monthly)) {
    .event(.appStarted, atLeast: 3) && .event(.entityCreated, atLeast: 5)
}

// 4. Donate events where they happen.
RuleKit.Event.appStarted.sendDonation()
```

This is a great fit for nudges that should happen *eventually, but not annoyingly*:
asking for an App Store review, surfacing a paywall from time to time, unlocking a
Game Center achievement, or hinting at a shortcut once a user repeats an action.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:ComposingRules>

### Configuration

- ``RuleKit/configure(storeLocation:)``
- ``RuleKit/Store/Location``

### Registering rules

- ``RuleKit/setRule(_:triggering:options:_:)``
- ``RuleKit/removeRule(named:)``
- ``RuleKit/registeredRuleNames``
- ``RuleKit/isRuleRegistered(named:)``

### Events and donations

- ``RuleKit/Event``
- ``RuleKit/Event/Donation``
- ``RuleKit/Event/Donations``
- ``RuleKit/AppVersion``

### Options

- ``TriggerFrequencyOption``
- ``DispatchQueueOption``
- ``DelayOption``

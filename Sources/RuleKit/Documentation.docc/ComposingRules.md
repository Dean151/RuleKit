# Composing Rules

Build rulesets from event conditions and combinators.

## Overview

A ruleset is a tree of ``Rule`` values. The leaves test events or arbitrary
conditions; the branches combine them. A trigger fires only when the whole tree is
fulfilled. Every rule is evaluated lazily and asynchronously each time an event is
donated.

```swift
RuleKit.setRule(triggering: .requestReviewPrompt, options: .triggerFrequency(.monthly)) {
    .allOf([
        .event(.promptAttempt) {
            $0.donations.last?.appVersion != .current
        },
        .anyOf([
            .event(.entityCreated) { _ in MyStore.shared.entityCount >= 5 },
            .allOf([
                .event(.appStarted, atLeast: 3),
                .event(.entityCreated, atLeast: 3),
            ])
        ])
    ])
}
```

## Event rules

The core leaf is ``Rule/event(_:condition:)``, which is fulfilled when its condition —
evaluated against the event's donations — returns `true`.

```swift
.event(.appStarted) { $0.donations.count >= 3 }
```

For common shapes, use the shorthands instead of writing the closure by hand:

- term ``Rule/event(_:atLeast:)``: Fulfilled once the event has been donated at least
  `count` times since its last reset. `.event(.appStarted, atLeast: 3)` is equivalent to
  `.event(.appStarted) { $0.donations.count >= 3 }`.
- term ``Rule/event(_:donatedWithin:)``: Fulfilled when the event's last donation
  happened within the last `interval` seconds. Not fulfilled if it was never donated.
- term ``Rule/event(_:notDonatedFor:)``: A cooldown — fulfilled when the event has *not*
  been donated for at least `interval` seconds. Also fulfilled if it was never donated.

```swift
// Fired within the last hour:
.event(.promptAttempt, donatedWithin: 60 * 60)

// Not prompted for at least a week (also true if never prompted):
.event(.promptAttempt, notDonatedFor: 7 * 24 * 60 * 60)
```

### Reading donations inside a condition

The condition closure receives a ``RuleKit/DonatedEvent``, whose
``RuleKit/Event/Donations`` summary exposes:

- term ``RuleKit/Event/Donations/count``: How many times the event has been donated
  since its last reset.
- term ``RuleKit/Event/Donations/first`` and ``RuleKit/Event/Donations/last``: The first
  and last recorded donation, each carrying its `date` and `appVersion`.
- term ``RuleKit/Event/Donations/timeSinceFirst`` and ``RuleKit/Event/Donations/timeSinceLast``:
  The elapsed time since those donations, or `nil` when there are none.
- term ``RuleKit/Event/Donations/firstSeenInCurrentVersion``: Whether the first donation
  was made in the current app version. `false` when there are no donations or no app
  version is available (e.g. on Linux).

> Note: To keep storage small, RuleKit does not retain every individual donation — only
> the count, the first, and the last.

## Arbitrary conditions

When a condition isn't about an event at all, use ``Rule/condition(_:)`` to test any
asynchronous boolean — app state, a feature flag, a stored preference.

```swift
.condition { await MyStore.shared.isPremium }
```

## Combining rules

These combinators build branches of the tree:

- term ``Rule/allOf(_:)``: Fulfilled when **every** child rule is fulfilled (logical AND).
- term ``Rule/anyOf(_:)``: Fulfilled when **at least one** child rule is fulfilled (logical OR).
- term ``Rule/noneOf(_:)``: Fulfilled when **none** of the child rules are fulfilled —
  the complement of `anyOf`.
- term ``Rule/atLeast(_:of:)``: A quorum (k-of-n) — fulfilled when at least `count` of
  the child rules are fulfilled.
- term ``Rule/not(_:)``: Negates a single rule.

```swift
.noneOf([
    .event(.subscribed) { $0.donations.count > 0 },
    .event(.paywallDismissed) { $0.donations.count > 0 },
])

.atLeast(2, of: [
    .event(.featureAUsed) { $0.donations.count > 0 },
    .event(.featureBUsed) { $0.donations.count > 0 },
    .event(.featureCUsed) { $0.donations.count > 0 },
])
```

### Operators

`&&`, `||`, and `!` are shorthand for `allOf`, `anyOf`, and `not`, respectively:

```swift
.event(.appStarted, atLeast: 3) && !(.condition { await MyStore.shared.isPremium })
```

## Constant rules

``Rule/always`` and ``Rule/never`` are always- and never-fulfilled rules. They are handy
as placeholders, to disable a trigger, or for conditional composition:

```swift
let activation: Rule = isBeta ? .event(.appStarted, atLeast: 1) : .never
```

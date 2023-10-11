# RuleKit

TipKit style API to trigger foundation notification based on events and condition.

## Usecases
- To open your Paywall from time to time
- To prompt your user to add an App Store review
- Watching and sending achievements to Game Center with GameKit
- ...

## Requirements
- Swift 5.8+ (Xcode 14.3+)
- iOS 14+, iPadOS 14+, tvOS 14+, watchOS 7+, macOS 11+

## Installation

Install using Swift Package Manager
```
dependencies: [
    .package(url: "https://github.com/Dean151/RuleKit.git", from: "0.2.0"),
],
targets: [
    .target(name: "MyTarget", dependencies: [
        .product(name: "RuleKit", package: "RuleKit"),
    ]),
]
```

And import it:
```swift
import RuleKit
```

## How to use?

RuleKit is about one thing: invoking a foundation notification when a set of rules are fulfilled!

- Configure RuleKit when your application starts
```swift
try RuleKit.configure(storeLocation: .applicationDefault)
```
- Create "events" to trigger RuleKit
```swift
extension RuleKit.Event {
    public static let appStarted: Self = "appStarted"
    public static let entityCreated: Self = "itemCreated"
    public static let promptAttempt: Self = "promptAttempt"
}
```
- Create a custom notification to be triggered by RuleKit
```swift
import Foundation

extension Notification.Name {
    static let requestReviewPrompt = Notification.Name("RequestReviewPrompt")
}
```
- Implement your logic of when your custom notification is triggered
```swift
import StoreKit
import SwiftUI

struct ContentView: View {
    @Environment(\.requestReview)
    private var requestReview

    var body: View {
        Text("Hello, World!")
            .onReceive(NotificationCenter.default.publisher(for: .requestReviewPrompt)) { _ in
                requestReview()
                RuleKit.Event.promptAttempt.sendDonation()
            }
    }
}
```
- Register your business rules that will trigger the notification
```swift
RuleKit.setRule(
    triggering: requestReviewNotification, 
    options: [.triggerFrequency(.monthly)], 
    .allOf([
        .event(.promptAttempt) {
            $0.donations.last?.version != .current
        },
        .anyOf([
            .event(.entityCreated) { _ in
                MyStore.shared.entityCount >= 5
            },
            .allOf([
                .event(.appStarted) {
                    $0.donations.count >= 3
                },
                .event(.entityCreated) { _ in
                    MyStore.shared.entityCount >= 3
                }
            ])
        ])
    ])
)
```
- Donate those event at proper places in your app
```swift
// Asynchronously
RuleKit.Event.appStarted.sendDonation()
// Synchronously
await RuleKit.Event.entityCreated.donate()
```
- As soon as an event is donated, if all the rules are fulfilled, the notification will be sent
- If required, reset an event donations to zero:
```swift
// Asynchronously
RuleKit.Event.appStarted.resetDonations()
// Synchronously
await RuleKit.Event.appStarted.reset()
```

### Available stores:
- `.applicationDefault`: Will use the default Document folder of your app
- `.groupContainer(identifier: String)`: Will store your event donations in the shared AppGroup container
- `.url(URL)`: Provide your own URL. It should be a directory URL.

### Available options:
- `.triggerFrequency(_)`: Throttle down notification donation or using given period
- `.dispatchQueue(_)`: Choose the DispatchQueue you want your notification to be sent from. Defaults to main queue.

### Event.Donations properties available in the condition closure:
- `count`: the number of times an event have been donated
- `first` and `last`: the first and last retrieved donation (date + version)

## Contribute
You are encouraged to contribute to this repository, by opening issues, or pull requests for bug fixes, improvement requests, or support.
Suggestions for contributing:
-  Improving documentation
-  Adding some automated tests 😜
-  Adding some new rules, options or properties for more use cases

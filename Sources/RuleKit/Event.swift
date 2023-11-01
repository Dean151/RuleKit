//
//  Event.swift
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

extension RuleKit {
    public struct Event: Sendable, RawRepresentable, ExpressibleByStringLiteral {
        public let rawValue: String
        
        public var donations: Event.Donations {
            get async {
                await RuleKit.internal.donations(for: self)
            }
        }
        
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
        
        public init(stringLiteral value: StringLiteralType) {
            self.init(rawValue: value)
        }
        
        public func donate() async {
            await RuleKit.internal.donate(self)
        }
        
        public func sendDonation() {
            Task(priority: .utility) {
                await donate()
            }
        }
        
        public func reset() async {
            await RuleKit.internal.reset(self)
        }

        public func resetDonations() {
            Task(priority: .utility) {
                await reset()
            }
        }
    }
    
    public struct DonatedEvent {
        public let event: Event
        public let donations: Event.Donations
    }
}

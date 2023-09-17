//
//  Version.swift
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

public struct Version: Sendable, Codable, Equatable, Comparable {
    let rawVersion: String

    public static let current: Self? = .init()

    public init(rawVersion: String) {
        self.rawVersion = rawVersion
    }
    init?() {
        guard let infoDict = Bundle.main.infoDictionary else {
            return nil
        }
        guard let version = infoDict["CFBundleShortVersionString"] as? String else {
            return nil
        }
        self.init(rawVersion: version)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.compare(with: rhs) == .orderedAscending
    }

    // Directly taken from https://sarunw.com/posts/how-to-compare-two-app-version-strings-in-swift/
    private func compare(with otherVersion: Self) -> ComparisonResult {
        let versionDelimiter = "."
        var versionComponents = rawVersion.components(separatedBy: versionDelimiter)
        var otherVersionComponents = otherVersion.rawVersion.components(separatedBy: versionDelimiter)

        let zeroDiff = versionComponents.count - otherVersionComponents.count
        if zeroDiff == 0 {
            // Same format, compare normally
            return rawVersion.compare(otherVersion.rawVersion, options: .numeric)
        } else {
            let zeros = Array(repeating: "0", count: abs(zeroDiff))
            if zeroDiff > 0 {
                otherVersionComponents.append(contentsOf: zeros)
            } else {
                versionComponents.append(contentsOf: zeros)
            }
            return versionComponents.joined(separator: versionDelimiter)
                .compare(otherVersionComponents.joined(separator: versionDelimiter), options: .numeric)
        }
    }
}

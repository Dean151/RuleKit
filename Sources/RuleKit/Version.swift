//
//  Version.swift
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

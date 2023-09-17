//
//  Store.swift
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

public actor Store {
    enum Error: Swift.Error {
        case missingGroupIdentifier
        case storeAlreadyConfigured
        case storeCouldFindDocumentDirectory
        case storeNotInitialized
        case storeUrlIsNotDirectory
    }

    public enum Location: Sendable {
        /// Will write the store file in `URL.applicationDirectory` folder
        case applicationDefault
        /// Will write the store file in the specified `containerURL(forSecurityApplicationGroupIdentifier: _)`
        case groupContainer(identifier: String)
        /// Will write the file in an arbitrary folder URL.
        /// If the provided URL is not a folder, `storeNotUrlDirectory` error will be thrown
        case url(URL)

        var url: URL {
            get throws {
                switch self {
                case .applicationDefault:
                    guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                        throw Error.storeCouldFindDocumentDirectory
                    }
                    return url
                case .groupContainer(identifier: let identifier):
                    guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
                        throw Error.missingGroupIdentifier
                    }
                    return url
                case .url(let url):
                    guard url.hasDirectoryPath && !url.isFileURL else {
                        throw Error.storeUrlIsNotDirectory
                    }
                    return url
                }
            }
        }

        func createStore() throws -> Store {
            var url = try self.url
            url.appendPathComponent("RuleKitEvents.plist")
            return Store(url: url)
        }
    }

    let url: URL

    var data: StoredData?

    init(url: URL) {
        self.url = url
    }

    func lastTrigger(of notification: Notification.Name) throws -> Date? {
        if data == nil {
            try loadData()
        }
        return data?.lastTrigger[notification.rawValue]
    }

    func persist(triggerOf notification: Notification.Name) throws {
        if data == nil {
            try loadData()
        }
        data?.lastTrigger[notification.rawValue] = .now
        try saveData()
    }

    func donations(for event: Event) throws -> Event.Donations {
        if data == nil {
            try loadData()
        }
        return data?.donations[event.rawValue] ?? .empty
    }

    func persist(_ donations: Event.Donations, for event: Event) throws {
        if data == nil {
            try loadData()
        }
        data?.donations[event.rawValue] = donations
        try saveData()
    }

    private func loadData() throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            data = .empty
            return
        }
        let decoder = PropertyListDecoder()
        let raw = try Data(contentsOf: url)
        do {
            self.data = try decoder.decode(StoredData.self, from: raw)
        } catch {
            // If we can't decode, let's throw the file away
            try FileManager.default.removeItem(at: url)
            try loadData()
        }
    }

    private func saveData() throws {
        guard let data else {
            return
        }
        let encoder = PropertyListEncoder()
        let raw = try encoder.encode(data)
        try raw.write(to: url, options: .atomic)
    }
}

struct StoredData: Codable {
    static let empty = StoredData()

    var donations: [String: Event.Donations]
    var lastTrigger: [String: Date]

    init() {
        self.donations = [:]
        self.lastTrigger = [:]
    }
}

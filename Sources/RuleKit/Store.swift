//
//  Store.swift
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

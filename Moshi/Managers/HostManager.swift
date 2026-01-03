import Foundation
import Combine

final class HostManager: ObservableObject {
    static let shared = HostManager()

    @Published var hosts: [Host] = []
    @Published var groups: [HostGroup] = []
    @Published var sshKeys: [SSHKey] = []

    private let hostsKey = "savedHosts"
    private let keysKey = "sshKeys"

    private init() {
        loadHosts()
        loadKeys()
        organizeGroups()
    }

    // MARK: - Host Management

    func addHost(_ host: Host) {
        hosts.append(host)
        saveHosts()
        organizeGroups()
    }

    func updateHost(_ host: Host) {
        if let index = hosts.firstIndex(where: { $0.id == host.id }) {
            hosts[index] = host
            saveHosts()
            organizeGroups()
        }
    }

    func deleteHost(_ host: Host) {
        hosts.removeAll { $0.id == host.id }
        saveHosts()
        organizeGroups()

        // Also delete stored credentials
        try? KeychainManager.shared.deletePassword(for: host.id)
    }

    func deleteHosts(at offsets: IndexSet) {
        let hostsToDelete = offsets.map { hosts[$0] }
        hosts.remove(atOffsets: offsets)
        saveHosts()
        organizeGroups()

        // Delete credentials
        for host in hostsToDelete {
            try? KeychainManager.shared.deletePassword(for: host.id)
        }
    }

    func moveHost(from source: IndexSet, to destination: Int) {
        hosts.move(fromOffsets: source, toOffset: destination)
        saveHosts()
    }

    // MARK: - Favorites

    func toggleFavorite(_ host: Host) {
        if let index = hosts.firstIndex(where: { $0.id == host.id }) {
            hosts[index].isFavorite.toggle()
            saveHosts()
        }
    }

    var favoriteHosts: [Host] {
        hosts.filter { $0.isFavorite }
    }

    // MARK: - Groups

    private func organizeGroups() {
        var groupDict: [String: [Host]] = [:]

        // Add ungrouped hosts to "Ungrouped"
        let ungroupedHosts = hosts.filter { $0.group == nil || $0.group?.isEmpty == true }
        if !ungroupedHosts.isEmpty {
            groupDict["Ungrouped"] = ungroupedHosts
        }

        // Organize by group
        for host in hosts {
            if let groupName = host.group, !groupName.isEmpty {
                groupDict[groupName, default: []].append(host)
            }
        }

        // Convert to HostGroup array
        groups = groupDict.map { HostGroup(name: $0.key, hosts: $0.value) }
            .sorted { $0.name < $1.name }
    }

    func createGroup(name: String) {
        guard !groups.contains(where: { $0.name == name }) else { return }
        groups.append(HostGroup(name: name))
        groups.sort { $0.name < $1.name }
    }

    func deleteGroup(name: String) {
        // Move hosts in this group to ungrouped
        for index in hosts.indices {
            if hosts[index].group == name {
                hosts[index].group = nil
            }
        }
        saveHosts()
        organizeGroups()
    }

    func moveHost(_ host: Host, toGroup groupName: String?) {
        if let index = hosts.firstIndex(where: { $0.id == host.id }) {
            hosts[index].group = groupName
            saveHosts()
            organizeGroups()
        }
    }

    // MARK: - SSH Keys

    func addKey(_ key: SSHKey) {
        sshKeys.append(key)
        saveKeys()
    }

    func deleteKey(_ key: SSHKey) {
        sshKeys.removeAll { $0.id == key.id }
        saveKeys()

        // Delete from keychain
        try? KeychainManager.shared.deletePrivateKey(for: key.id)
    }

    func getKey(by id: UUID) -> SSHKey? {
        sshKeys.first { $0.id == id }
    }

    // MARK: - Search

    func searchHosts(_ query: String) -> [Host] {
        guard !query.isEmpty else { return hosts }

        let lowercaseQuery = query.lowercased()

        return hosts.filter { host in
            host.name.lowercased().contains(lowercaseQuery) ||
            host.hostname.lowercased().contains(lowercaseQuery) ||
            host.username.lowercased().contains(lowercaseQuery) ||
            (host.notes?.lowercased().contains(lowercaseQuery) ?? false)
        }
    }

    // MARK: - Persistence

    private func loadHosts() {
        if let data = UserDefaults.standard.data(forKey: hostsKey),
           let decoded = try? JSONDecoder().decode([Host].self, from: data) {
            hosts = decoded
        } else {
            // Sample hosts for first launch
            hosts = createSampleHosts()
        }
    }

    private func saveHosts() {
        if let data = try? JSONEncoder().encode(hosts) {
            UserDefaults.standard.set(data, forKey: hostsKey)
        }
    }

    private func loadKeys() {
        if let data = UserDefaults.standard.data(forKey: keysKey),
           let decoded = try? JSONDecoder().decode([SSHKey].self, from: data) {
            sshKeys = decoded
        }
    }

    private func saveKeys() {
        if let data = try? JSONEncoder().encode(sshKeys) {
            UserDefaults.standard.set(data, forKey: keysKey)
        }
    }

    // MARK: - Import/Export

    func exportHosts() -> Data? {
        try? JSONEncoder().encode(hosts)
    }

    func importHosts(from data: Data) -> Int {
        guard let imported = try? JSONDecoder().decode([Host].self, from: data) else {
            return 0
        }

        var count = 0
        for host in imported {
            // Skip duplicates
            if !hosts.contains(where: { $0.hostname == host.hostname && $0.username == host.username }) {
                hosts.append(host)
                count += 1
            }
        }

        saveHosts()
        organizeGroups()
        return count
    }

    // MARK: - Sample Data

    private func createSampleHosts() -> [Host] {
        // Return empty for production, or sample hosts for demo
        return []
    }
}

// MARK: - Duplicate Detection

extension HostManager {
    func isDuplicate(hostname: String, username: String, port: Int, excludingId: UUID? = nil) -> Bool {
        hosts.contains { host in
            host.hostname == hostname &&
            host.username == username &&
            host.port == port &&
            host.id != excludingId
        }
    }
}

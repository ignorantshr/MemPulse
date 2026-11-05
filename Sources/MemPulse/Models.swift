import Foundation

struct ProcessRecord: Identifiable, Codable {
    let pid: Int32
    let parent: Int32
    let startSeconds: UInt64
    let startMicroseconds: UInt64
    let name: String
    let path: String
    let memory: UInt64?
    let memoryError: Int32
    var id: String { "\(pid):\(startSeconds):\(startMicroseconds)" }
}

struct AppIdentity: Hashable, Codable {
    let path: String
    let name: String
}

struct AssignedProcess: Identifiable, Codable {
    let process: ProcessRecord
    let reason: String
    var id: String { process.id }
}

struct AppGroup: Identifiable, Codable {
    let app: AppIdentity
    var processes: [AssignedProcess]
    var id: String { app.path }
    var total: UInt64 { processes.reduce(0) { $0 + ($1.process.memory ?? 0) } }
    var unreadable: Int { processes.filter { $0.process.memory == nil }.count }
}

struct Snapshot: Codable {
    let date: Date
    let groups: [AppGroup]
    let skipped: Int
    let duration: Double
}

func memoryLabel(_ bytes: UInt64) -> String {
    let value = Double(bytes)
    if bytes >= 1_073_741_824 { return String(format: "%.2f GiB", value / 1_073_741_824) }
    return String(format: "%.1f MiB", value / 1_048_576)
}

enum Attribution {
    static func outerBundle(_ path: String) -> String? {
        guard path.hasPrefix("/") else { return nil }
        let parts = (path as NSString).pathComponents
        guard let index = parts.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        return NSString.path(withComponents: Array(parts[...index]))
    }

    static func group(_ processes: [ProcessRecord], running: [Int32: AppIdentity],
                      bundleIdentity: (String) -> AppIdentity) -> [AppGroup] {
        let byPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })
        var owners: [Int32: (AppIdentity, String)] = [:]
        for process in processes {
            // Normalize nested Helper.app bundles to the outer product.
            if let path = outerBundle(process.path) {
                owners[process.pid] = (bundleIdentity(path), "包内进程")
            } else if let app = running[process.pid], Attribution.outerBundle(app.path) != nil, !process.path.isEmpty,
                      process.path.hasPrefix(app.path + "/") {
                owners[process.pid] = (app, "App 主进程")
            }
        }
        let direct = owners
        // Every process first inherits its parent's resolved application. Walking
        // to the highest attributable ancestor also resolves intermediate bundles
        // (e.g. Python.app) without depending on enumeration order.
        for process in processes {
            var child = process
            var visited: Set<Int32> = [process.pid]
            var inherited: (AppIdentity, String)?
            while let parent = byPID[child.parent] {
                guard visited.insert(parent.pid).inserted else {
                    // A cyclic chain has no trustworthy root; retain only self evidence.
                    inherited = nil
                    break
                }
                guard parent.startSeconds < child.startSeconds ||
                      (parent.startSeconds == child.startSeconds && parent.startMicroseconds <= child.startMicroseconds) else { break }
                if let owner = direct[parent.pid] {
                    inherited = (owner.0, "父进程优先 · 祖先 PID \(parent.pid)")
                }
                child = parent
            }
            if let inherited { owners[process.pid] = inherited }
        }
        let unknown = AppIdentity(path: "unassigned", name: "未归属进程")
        var groups: [String: AppGroup] = [:]
        for process in processes {
            let (app, reason) = owners[process.pid] ?? (unknown, "无法确定")
            if groups[app.path] == nil { groups[app.path] = AppGroup(app: app, processes: []) }
            groups[app.path]!.processes.append(AssignedProcess(process: process, reason: reason))
        }
        return groups.values.map { group in
            var copy = group
            copy.processes.sort { ($0.process.memory ?? 0) > ($1.process.memory ?? 0) }
            return copy
        }.sorted { $0.total == $1.total ? $0.id < $1.id : $0.total > $1.total }
    }
}

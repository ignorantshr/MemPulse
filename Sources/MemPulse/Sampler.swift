import AppKit
import ProcessProbe

actor Sampler {
    private var identities: [String: AppIdentity] = [:]

    func sample() async throws -> Snapshot {
        let started = Date()
        let running: [Int32: AppIdentity] = await MainActor.run {
            var result: [Int32: AppIdentity] = [:]
            for app in NSWorkspace.shared.runningApplications {
                guard let url = app.bundleURL else { continue }
                guard let path = Attribution.outerBundle(url.path) else { continue }
                result[app.processIdentifier] = AppIdentity(path: path, name: app.localizedName ?? url.deletingPathExtension().lastPathComponent)
            }
            return result
        }
        let count = wr_list_pids(nil, 0)
        guard count > 0 else { throw NSError(domain: "MemPulse", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法枚举进程"]) }
        var pids = [Int32](repeating: 0, count: Int(count) + 256)
        var actual = pids.withUnsafeMutableBufferPointer { wr_list_pids($0.baseAddress, Int32($0.count * MemoryLayout<Int32>.stride)) }
        // Retry with extra capacity if processes appeared while allocating.
        if actual >= pids.count {
            pids = [Int32](repeating: 0, count: pids.count * 2)
            actual = pids.withUnsafeMutableBufferPointer { wr_list_pids($0.baseAddress, Int32($0.count * MemoryLayout<Int32>.stride)) }
        }
        guard actual > 0, actual < pids.count else { throw NSError(domain: "MemPulse", code: 2, userInfo: [NSLocalizedDescriptionKey: "进程列表读取失败或持续增长，请重试"]) }
        var records: [ProcessRecord] = []
        var skipped = 0
        for pid in pids.prefix(Int(actual)) where pid > 0 {
            var raw = WRProcess()
            guard wr_read_process(pid, &raw) != 0 else { skipped += 1; continue }
            let name = withUnsafePointer(to: &raw.name) { pointer in pointer.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) } }
            let path = withUnsafePointer(to: &raw.path) { pointer in pointer.withMemoryRebound(to: CChar.self, capacity: 4096) { String(cString: $0) } }
            records.append(ProcessRecord(pid: pid, parent: raw.parent, startSeconds: raw.start_seconds,
                startMicroseconds: raw.start_microseconds, name: name, path: path,
                memory: raw.memory_error == 0 ? raw.footprint : nil, memoryError: raw.memory_error))
        }
        let groups = Attribution.group(records, running: running) { path in
            if let identity = identities[path] { return identity }
            let bundle = Bundle(path: path)
            let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            let identity = AppIdentity(path: path, name: name)
            identities[path] = identity
            return identity
        }
        let active = Set(groups.map { $0.app.path })
        identities = identities.filter { active.contains($0.key) }
        return Snapshot(date: Date(), groups: groups, skipped: skipped, duration: Date().timeIntervalSince(started))
    }
}

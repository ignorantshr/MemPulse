import SwiftUI
import AppKit

@MainActor
final class Monitor: ObservableObject {
    @Published var snapshot: Snapshot?
    @Published var error: String?
    @Published var paused = false
    private let sampler = Sampler()

    func run() async {
        while !Task.isCancelled {
            if !paused {
                do {
                    snapshot = try await sampler.sample()
                    error = nil
                } catch { self.error = error.localizedDescription }
            }
            let visible = NSApplication.shared.windows.contains { $0.isVisible && !$0.isMiniaturized }
            do { try await Task.sleep(nanoseconds: visible ? 2_000_000_000 : 10_000_000_000) }
            catch { return }
        }
    }
}

struct ContentView: View {
    @StateObject private var monitor = Monitor()
    @State private var search = ""
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("MemPulse").font(.title.bold())
                    Text("按应用汇总内存 · Physical footprint").foregroundStyle(.secondary)
                }
                Spacer()
                Button(monitor.paused ? "继续采样" : "暂停采样") { monitor.paused.toggle() }
            }
            TextField("搜索应用、进程名称或 PID", text: $search)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("搜索应用、进程名称或 PID")
            if let error = monitor.error {
                Text("采样失败：\(error)；下方可能为上次数据。")
                    .foregroundStyle(.red).textSelection(.enabled)
            }
            if let snapshot = monitor.snapshot {
                HStack {
                    Text("\(snapshot.groups.reduce(0) { $0 + $1.processes.count }) 个进程")
                    Text("更新于 \(snapshot.date.formatted(date: .omitted, time: .standard))")
                    Text(String(format: "采样 %.0f ms", snapshot.duration * 1000))
                    if monitor.paused { Text("已暂停").bold() }
                }.font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(snapshot.groups.filter(matches)) { group in
                            Section {
                                if expanded.contains(group.id) {
                                    ForEach(group.processes) { item in
                                        processRow(item)
                                        Divider().padding(.leading, 52)
                                    }
                                }
                            } header: {
                                appHeader(group)
                            }
                        }
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
                if snapshot.skipped > 0 {
                    Text("\(snapshot.skipped) 个进程已退出或基础信息不可读，未计入本次统计。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Spacer()
                HStack { Spacer(); ProgressView("正在采样…"); Spacer() }
                Spacer()
            }
            Text("内存为已归属进程 footprint 之和，并非关闭后必然释放的 RAM。系统共享服务可能无法归属。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .textSelection(.enabled)
        .padding(20).frame(minWidth: 690, minHeight: 480)
        .task { await monitor.run() }
    }

    private func appHeader(_ group: AppGroup) -> some View {
        let total = group.unreadable == group.processes.count ? "不可读取" : memoryLabel(group.total) + (group.unreadable > 0 ? " + 未知" : "")
        let details = "\(group.processes.count) 个进程" + (group.unreadable > 0 ? " · \(group.unreadable) 个不可读取，统计不完整" : "")
        return HStack(spacing: 10) {
            Button {
                if expanded.contains(group.id) { expanded.remove(group.id) }
                else { expanded.insert(group.id) }
            } label: {
                Image(systemName: expanded.contains(group.id) ? "chevron.down" : "chevron.right")
                    .frame(width: 20, height: 32).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(expanded.contains(group.id) ? "收起" : "展开") \(group.app.name)")
            if group.id != "unassigned" {
                Image(nsImage: NSWorkspace.shared.icon(forFile: group.app.path))
                    .resizable().frame(width: 26, height: 26).accessibilityHidden(true)
            } else {
                Image(systemName: "questionmark.folder").frame(width: 26, height: 26)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(group.app.name).fontWeight(.medium)
                Text(details).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(total).monospacedDigit().fontWeight(.semibold)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
        .help(group.app.path)
        .contextMenu {
            Button("复制应用汇总") { copyText("\(group.app.name)\t\(total)\t\(details)") }
            Button("复制全部进程明细") {
                copyText((["\(group.app.name)\t\(total)"] + group.processes.map(processText)).joined(separator: "\n"))
            }
            if group.id != "unassigned" {
                Button("复制应用路径") { copyText(group.app.path) }
            }
        }
    }

    private func processRow(_ item: AssignedProcess) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.process.name)
                Text("PID \(String(item.process.pid)) · \(item.reason)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(item.process.memory.map(memoryLabel) ?? "不可读取")
                .monospacedDigit()
                .help(item.process.memory == nil ? "\(String(cString: strerror(item.process.memoryError))) (errno \(item.process.memoryError))" : item.process.path)
        }
        .padding(.leading, 52).padding(.trailing, 12).padding(.vertical, 8)
        .contextMenu {
            Button("复制进程明细") { copyText(processText(item)) }
            Button("复制 PID") { copyText(String(item.process.pid)) }
            if !item.process.path.isEmpty {
                Button("复制进程路径") { copyText(item.process.path) }
            }
        }
    }

    private func processText(_ item: AssignedProcess) -> String {
        "\(item.process.name)\tPID \(item.process.pid)\t\(item.process.memory.map(memoryLabel) ?? "不可读取")\t\(item.reason)\t\(item.process.path)"
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func matches(_ group: AppGroup) -> Bool {
        search.isEmpty || group.app.name.localizedCaseInsensitiveContains(search)
            || group.processes.contains { $0.process.name.localizedCaseInsensitiveContains(search) || String($0.process.pid).contains(search) }
    }
}

struct DesktopApp: App {
    var body: some Scene {
        Window("MemPulse", id: "main") { ContentView() }
            .defaultSize(width: 850, height: 640)
    }
}

@main
enum Entry {
    @MainActor static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.isEmpty {
            NSApplication.shared.setActivationPolicy(.regular)
            DesktopApp.main()
            return
        }
        if args == ["--help"] {
            print("MemPulse                 打开图形界面\nMemPulse --snapshot      输出一次应用内存汇总\nMemPulse --snapshot --json 输出完整进程与归属 JSON")
            return
        }
        guard args == ["--snapshot"] || args == ["--snapshot", "--json"] else {
            fputs("参数无效；使用 --help 查看用法。\n", stderr)
            exit(2)
        }
        do {
            let snapshot = try await Sampler().sample()
            if args.contains("--json") {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                FileHandle.standardOutput.write(try encoder.encode(snapshot))
                print()
            } else {
                print("应用内存（physical footprint）\n")
                for group in snapshot.groups {
                    let total = group.unreadable == group.processes.count ? "不可读取" : memoryLabel(group.total)
                    print("\(total)\t\(group.processes.count) 进程\t\(group.app.name)\(group.unreadable > 0 ? " [\(group.unreadable) 个不可读取]" : "")")
                }
                print("\n跳过 \(snapshot.skipped) 个退出或基础信息不可读进程；耗时 \(Int(snapshot.duration * 1000)) ms。")
            }
        } catch {
            fputs("采样失败：\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}

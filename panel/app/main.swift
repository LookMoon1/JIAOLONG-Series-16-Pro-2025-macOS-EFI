//  机械革命 · 性能面板（只读）
//  数据来源：本项目自研只读驱动 MechrevoEC 发布的 IORegistry 属性 + 系统自带接口
//  不写任何硬件寄存器

import AppKit

// MARK: - 数据模型

struct Snapshot {
    var driverOK      = false
    var seq           = 0
    var failures      = 0
    var modeRaw       = -1          // 0x461，档位指纹
    var cpuTemp       = -1          // 0x449
    var gpuTemp       = -1          // 0x44F (VGAT)
    var cptmLimit     = -1          // 0x43E (CPTM)
    var fanLevel      = -1          // 0xD8
    var fanHist: [Int] = []         // 0xD0-0xD7 占空比历史
    var cpuLoad       = 0.0
    var memUsed       = 0.0
    var memTotal      = 0.0
    var gpuUtil       = -1.0
    var vramUsedMB    = -1.0
    var vramTotalMB   = -1.0
    var batteryPct    = -1
    var charging      = false
    var acPower       = false
    var timestamp     = Date()
}

// MARK: - 采集

enum Raw {
    static func run(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func property(_ name: String, _ text: String) -> [UInt8]? {
        guard let r = text.range(of: "\"\(name)\" = <") else { return nil }
        let rest = text[r.upperBound...]
        guard let end = rest.firstIndex(of: ">") else { return nil }
        let hex = rest[..<end].filter { $0.isHexDigit }
        guard hex.count % 2 == 0 else { return nil }
        var out = [UInt8]()
        out.reserveCapacity(hex.count / 2)
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let next = hex.index(idx, offsetBy: 2)
            if let b = UInt8(hex[idx..<next], radix: 16) { out.append(b) }
            idx = next
        }
        return out.isEmpty ? nil : out
    }

    static func number(after key: String, in text: String) -> Double? {
        guard let r = text.range(of: key) else { return nil }
        var rest = text[r.upperBound...]
        rest = rest.drop(while: { $0 == " " || $0 == "\t" || $0 == "=" })
        let digits = rest.prefix(while: { $0.isNumber || $0 == "." })
        return Double(digits)
    }

    static func intProperty(_ name: String, _ text: String) -> Int? {
        guard let r = text.range(of: "\"\(name)\" = ") else { return nil }
        let line = text[r.upperBound...].prefix(while: { $0 != "\n" })
        return Int(line.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

final class Monitor {
    private var timer: Timer?

    func start(_ handler: @escaping (Snapshot) -> Void) {
        tick(handler)
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.tick(handler)
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func tick(_ handler: @escaping (Snapshot) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let snap = self.collect()
            DispatchQueue.main.async { handler(snap) }
        }
    }

    private func collect() -> Snapshot {
        var s = Snapshot()

        // 1) 驱动数据
        let io = Raw.run("/usr/sbin/ioreg", ["-c", "MechrevoEC", "-r", "-d", "1"])
        if let seq = Raw.intProperty("Seq", io), seq > 0 {
            s.driverOK = true
            s.seq = seq
            s.failures = Raw.intProperty("Failures", io) ?? 0

            if let mid = Raw.property("MidMap", io), mid.count >= 0x80 {
                s.cpuTemp   = Int(mid[0x449 - 0x430])
                s.gpuTemp   = Int(mid[0x44F - 0x430])
                s.cptmLimit = Int(mid[0x43E - 0x430])
                s.modeRaw   = Int(mid[0x461 - 0x430])
            }
            if let fan = Raw.property("FanMap", io), fan.count >= 0x0A {
                s.fanHist  = (0..<8).map { Int(fan[$0]) }
                s.fanLevel = Int(fan[0x08])
            }
        }

        // 2) CPU 负载
        let psOut = Raw.run("/bin/ps", ["-A", "-o", "%cpu"])
        var total = 0.0
        for line in psOut.split(separator: "\n").dropFirst() {
            if let v = Double(line.trimmingCharacters(in: .whitespacesAndNewlines)) { total += v }
        }
        let ncpu = Double(Raw.run("/usr/sbin/sysctl", ["-n", "hw.ncpu"]).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 16
        s.cpuLoad = min(100.0, total / max(ncpu, 1))

        // 3) 内存：按字段名精确取值，页大小从 vm_stat 头部读取
        if let totalStr = Double(Raw.run("/usr/sbin/sysctl", ["-n", "hw.memsize"]).trimmingCharacters(in: .whitespacesAndNewlines)) {
            s.memTotal = totalStr / 1_073_741_824.0
        }
        let vm = Raw.run("/usr/bin/vm_stat", [])
        var pageSize = 4096.0
        if let r = vm.range(of: "page size of ") {
            let digits = vm[r.upperBound...].prefix(while: { $0.isNumber })
            if let ps = Double(digits) { pageSize = ps }
        }
        func vmField(_ key: String) -> Double {
            for line in vm.split(separator: "\n") {
                let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.hasPrefix(key) {
                    let digits = t.filter { $0.isNumber }
                    if let v = Double(digits) { return v }
                }
            }
            return 0
        }
        let usedPages = vmField("Pages active:")
                      + vmField("Pages wired down:")
                      + vmField("Pages occupied by compressor:")
        s.memUsed = min(s.memTotal, usedPages * pageSize / 1_073_741_824.0)

        // 3.5) GPU 利用率与显存（来自 NVIDIA 加速器对象，只读）
        let gpu = Raw.run("/usr/sbin/ioreg", ["-rc", "NVAccel"])
        if let u = Raw.number(after: "\"GPU Core Utilization %\"", in: gpu) {
            s.gpuUtil = u
        }
        if let used = Raw.number(after: "\"inUseVidMemoryBytes\"", in: gpu) {
            s.vramUsedMB = used / 1_048_576.0
        }
        let pci = Raw.run("/usr/sbin/ioreg", ["-c", "IOPCIDevice", "-r", "-d", "1"])
        if let total = Raw.number(after: "\"VRAM,totalsize\"", in: pci) {
            s.vramTotalMB = total / 1_048_576.0
        }

        // 4) 电量与供电
        let batt = Raw.run("/usr/bin/pmset", ["-g", "batt"])
        if let r = batt.range(of: "Now drawing from '") {
            s.acPower = batt[r.upperBound...].hasPrefix("AC Power")
        }
        if let pctR = batt.range(of: "%") {
            let before = batt[..<pctR.lowerBound].suffix(4)
            if let v = Int(before.trimmingCharacters(in: .whitespacesAndNewlines)) { s.batteryPct = v }
        }
        s.charging = batt.contains("; charging;") || batt.contains("; AC attached;")

        s.timestamp = Date()
        return s
    }

}

// MARK: - 视图组件

final class BarView: NSView {
    var fraction: Double = 0 { didSet { needsDisplay = true } }
    var barColor: NSColor = .systemTeal { didSet { needsDisplay = true } }
    var captionLeft: String = "" { didSet { needsDisplay = true } }
    var captionRight: String = "" { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let trackH: CGFloat = 10
        let trackRect = NSRect(x: 0, y: bounds.height - trackH - 2, width: bounds.width, height: trackH)
        NSColor(white: 0.24, alpha: 1).setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: trackH/2, yRadius: trackH/2).fill()

        let w = max(0, min(1, fraction)) * bounds.width
        if w > 1 {
            barColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: 0, y: trackRect.minY, width: w, height: trackH),
                         xRadius: trackH/2, yRadius: trackH/2).fill()
        }

        let attrsL: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor(white: 0.86, alpha: 1)]
        let attrsR: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: barColor]
        captionLeft.draw(at: NSPoint(x: 0, y: 0), withAttributes: attrsL)
        let rSize = captionRight.size(withAttributes: attrsR)
        captionRight.draw(at: NSPoint(x: bounds.width - rSize.width, y: 0), withAttributes: attrsR)
    }
}

final class SparkView: NSView {
    var values: [Int] = [] { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.18, alpha: 1).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        guard values.count > 1 else { return }
        let mx = max(1, values.max() ?? 1)
        let mn = values.min() ?? 0
        let span = max(1, mx - mn)
        let path = NSBezierPath()
        for (i, v) in values.enumerated() {
            let x = bounds.width * CGFloat(i) / CGFloat(values.count - 1)
            let y = 6 + (bounds.height - 12) * CGFloat(Double(v - mn) / Double(span))
            if i == 0 { path.move(to: NSPoint(x: x, y: y)) } else { path.line(to: NSPoint(x: x, y: y)) }
        }
        NSColor.systemOrange.setStroke()
        path.lineWidth = 2
        path.stroke()
    }
}

final class ModeBadge: NSView {
    var text: String = "未标定" { didSet { needsDisplay = true } }
    var color: NSColor = .systemGray { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
        color.withAlphaComponent(0.16).setFill()
        path.fill()
        color.setStroke()
        path.lineWidth = 1
        path.stroke()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 26, weight: .bold),
            .foregroundColor: color]
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: (bounds.width - size.width)/2, y: (bounds.height - size.height)/2),
                  withAttributes: attrs)
    }
}

// MARK: - 档位标定表

// 现场采样结论：三档对应 0x461 的三个稳定值
// 126 / 100 / 200 依次由按键循环产生；按"占空上限"推断 200 最高、100 最低
let modeTable: [Int: (String, NSColor)] = [
    126: ("均衡", .systemTeal),
    100: ("办公", .systemGreen),
    200: ("狂暴", .systemRed),
]

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var badge: ModeBadge!
    var cpuBar: BarView!
    var memBar: BarView!
    var tempBar: BarView!
    var fanBar: BarView!
    var gpuUtilBar: BarView!
    var vramBar: BarView!
    var spark: SparkView!
    var statusLabel: NSTextField!
    var detailLabel: NSTextField!
    var monitor = Monitor()
    var tempHistory: [Double] = []

    func applicationDidFinishLaunching(_ n: Notification) {
        buildUI()
        monitor.start { [weak self] snap in self?.render(snap) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func label(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = NSFont.systemFont(ofSize: size, weight: weight)
        l.textColor = color
        return l
    }

    private func buildUI() {
        let w: CGFloat = 460, h: CGFloat = 720
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                          styleMask: [.titled, .closable, .miniaturizable],
                          backing: .buffered, defer: false)
        window.title = "机械革命 · 性能面板（只读）"
        window.center()
        window.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 1)
        window.appearance = NSAppearance(named: .darkAqua)

        let content = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        window.contentView = content

        var y = h - 24

        func place(_ v: NSView, _ height: CGFloat, topGap: CGFloat = 10) {
            y -= topGap + height
            v.frame = NSRect(x: 24, y: y, width: w - 48, height: height)
            content.addSubview(v)
        }

        place(label("蛟龙16 Pro · 性能模式", size: 12, weight: .regular, color: NSColor(white: 0.62, alpha: 1)), 16, topGap: 0)
        y -= 4

        badge = ModeBadge()
        badge.frame = NSRect(x: 24, y: y - 84, width: w - 48, height: 76)
        content.addSubview(badge)
        y -= 84 + 10

        cpuBar = BarView(); place(cpuBar, 34)
        memBar = BarView(); place(memBar, 34)
        tempBar = BarView(); place(tempBar, 34)
        fanBar = BarView(); place(fanBar, 34)
        gpuUtilBar = BarView(); place(gpuUtilBar, 34)
        vramBar = BarView(); place(vramBar, 34)

        place(label("CPU 温度趋势（近 2 分钟）", size: 11, weight: .regular,
                    color: NSColor(white: 0.55, alpha: 1)), 14, topGap: 14)
        spark = SparkView()
        spark.frame = NSRect(x: 24, y: y - 54, width: w - 48, height: 50)
        content.addSubview(spark)
        y -= 54 + 12

        detailLabel = label("", size: 11, weight: .regular, color: NSColor(white: 0.60, alpha: 1))
        detailLabel.maximumNumberOfLines = 3
        place(detailLabel, 46)

        statusLabel = label("正在读取…", size: 11, weight: .regular, color: NSColor(white: 0.45, alpha: 1))
        statusLabel.frame = NSRect(x: 24, y: 14, width: w - 48, height: 16)
        content.addSubview(statusLabel)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func render(_ s: Snapshot) {
        // 档位
        if let m = modeTable[s.modeRaw] {
            badge.text = m.0
            badge.color = m.1
        } else if s.modeRaw >= 0 {
            badge.text = "未标定 (\(s.modeRaw))"
            badge.color = .systemGray
        } else {
            badge.text = "无数据"
            badge.color = .systemGray
        }

        cpuBar.captionLeft = "CPU 负载"
        cpuBar.captionRight = String(format: "%.0f%%", s.cpuLoad)
        cpuBar.fraction = s.cpuLoad / 100.0
        cpuBar.barColor = s.cpuLoad > 80 ? .systemRed : (s.cpuLoad > 50 ? .systemOrange : .systemTeal)

        let memFrac = s.memTotal > 0 ? s.memUsed / s.memTotal : 0
        memBar.captionLeft = "内存占用"
        memBar.captionRight = String(format: "%.1f / %.0f GB", s.memUsed, s.memTotal)
        memBar.fraction = memFrac
        memBar.barColor = .systemBlue

        let hottest = max(s.cpuTemp, s.gpuTemp)
        tempBar.captionLeft = "CPU 温度 / GPU 温度"
        tempBar.captionRight = (s.cpuTemp >= 0 && s.gpuTemp >= 0)
            ? "\(s.cpuTemp)°C / \(s.gpuTemp)°C" : "无数据"
        tempBar.fraction = hottest >= 0 ? min(1, Double(hottest) / 100.0) : 0
        tempBar.barColor = hottest >= 90 ? .systemRed : (hottest >= 75 ? .systemOrange : .systemTeal)

        fanBar.captionLeft = "风扇档位（EC 0xD8）"
        fanBar.captionRight = s.fanLevel >= 0 ? "\(s.fanLevel) / 7" : "无数据"
        fanBar.fraction = s.fanLevel >= 0 ? Double(s.fanLevel) / 7.0 : 0
        fanBar.barColor = .systemPurple

        if s.cpuTemp >= 0 {
            tempHistory.append(Double(s.cpuTemp))
            if tempHistory.count > 60 { tempHistory.removeFirst() }
        }
        gpuUtilBar.captionLeft = "GPU 利用率"
        gpuUtilBar.captionRight = s.gpuUtil >= 0 ? String(format: "%.0f%%", s.gpuUtil) : "无数据"
        gpuUtilBar.fraction = s.gpuUtil >= 0 ? s.gpuUtil / 100.0 : 0
        gpuUtilBar.barColor = s.gpuUtil > 80 ? .systemRed : (s.gpuUtil > 40 ? .systemOrange : .systemTeal)

        let vramPct = s.vramTotalMB > 0 ? s.vramUsedMB / s.vramTotalMB : 0
        vramBar.captionLeft = "显存占用"
        vramBar.captionRight = (s.vramUsedMB >= 0 && s.vramTotalMB > 0)
            ? String(format: "%.0f MB / %.1f GB (%.0f%%)", s.vramUsedMB, s.vramTotalMB / 1024.0, vramPct * 100)
            : "无数据"
        vramBar.fraction = max(0, min(1, vramPct))
        vramBar.barColor = .systemIndigo

        spark.values = tempHistory.map { Int($0) }

        var bits: [String] = []
        if s.batteryPct >= 0 {
            bits.append("电量 \(s.batteryPct)%\(s.charging ? "（充电中）" : "")")
            bits.append(s.acPower ? "AC 供电" : "电池供电")
        }
        if s.cptmLimit >= 0 { bits.append("温度限值 0x43E = \(s.cptmLimit)") }
        if s.modeRaw >= 0 { bits.append("档位寄存器 0x461 = \(s.modeRaw)") }
        detailLabel.stringValue = bits.joined(separator: " · ")

        let stamp = DateFormatter()
        stamp.dateFormat = "HH:mm:ss"
        if s.driverOK {
            statusLabel.stringValue = "驱动在线 · 采样 #\(s.seq) · 读取失败 \(s.failures) · 更新 \(stamp.string(from: s.timestamp))"
            statusLabel.textColor = NSColor(white: 0.45, alpha: 1)
        } else {
            statusLabel.stringValue = "驱动未加载（MechrevoEC 未匹配）· 仅显示系统数据"
            statusLabel.textColor = .systemOrange
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

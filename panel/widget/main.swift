//  机械革命 · 桌面小组件（只读）
//  贴在桌面图层上的无边框悬浮窗：不占 Dock、不抢焦点、可拖动、跨空间常驻。

import AppKit

// MARK: - 数据模型

struct Snapshot {
    var driverOK      = false
    var seq           = 0
    var failures      = 0
    var modeRaw       = -1
    var cpuTemp       = -1
    var gpuTemp       = -1
    var cptmLimit     = -1
    var fanLevel      = -1
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
                s.fanLevel = Int(fan[0x08])
            }
        }

        let psOut = Raw.run("/bin/ps", ["-A", "-o", "%cpu"])
        var total = 0.0
        for line in psOut.split(separator: "\n").dropFirst() {
            if let v = Double(line.trimmingCharacters(in: .whitespacesAndNewlines)) { total += v }
        }
        let ncpu = Double(Raw.run("/usr/sbin/sysctl", ["-n", "hw.ncpu"]).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 16
        s.cpuLoad = min(100.0, total / max(ncpu, 1))

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
                    if let v = Double(t.filter { $0.isNumber }) { return v }
                }
            }
            return 0
        }
        let usedPages = vmField("Pages active:") + vmField("Pages wired down:") + vmField("Pages occupied by compressor:")
        s.memUsed = min(s.memTotal, usedPages * pageSize / 1_073_741_824.0)

        let gpu = Raw.run("/usr/sbin/ioreg", ["-rc", "NVAccel"])
        if let u = Raw.number(after: "\"GPU Core Utilization %\"", in: gpu) { s.gpuUtil = u }
        if let used = Raw.number(after: "\"inUseVidMemoryBytes\"", in: gpu) { s.vramUsedMB = used / 1_048_576.0 }
        let pci = Raw.run("/usr/sbin/ioreg", ["-c", "IOPCIDevice", "-r", "-d", "1"])
        if let total = Raw.number(after: "\"VRAM,totalsize\"", in: pci) { s.vramTotalMB = total / 1_048_576.0 }

        let batt = Raw.run("/usr/bin/pmset", ["-g", "batt"])
        if let r = batt.range(of: "Now drawing from '") {
            s.acPower = batt[r.upperBound...].hasPrefix("AC Power")
        }
        if let pctR = batt.range(of: "%") {
            let before = batt[..<pctR.lowerBound].suffix(4)
            if let v = Int(before.trimmingCharacters(in: .whitespaces)) { s.batteryPct = v }
        }
        s.charging = batt.contains("; charging;") || batt.contains("; AC attached;")

        s.timestamp = Date()
        return s
    }
}

// MARK: - 视图

final class BarView: NSView {
    var fraction: Double = 0 { didSet { needsDisplay = true } }
    var barColor: NSColor = .systemTeal { didSet { needsDisplay = true } }
    var captionLeft: String = "" { didSet { needsDisplay = true } }
    var captionRight: String = "" { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let trackH: CGFloat = 8
        let trackRect = NSRect(x: 0, y: bounds.height - trackH - 1, width: bounds.width, height: trackH)
        NSColor(white: 0.26, alpha: 1).setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: trackH/2, yRadius: trackH/2).fill()

        let w = max(0, min(1, fraction)) * bounds.width
        if w > 1 {
            barColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: 0, y: trackRect.minY, width: w, height: trackH),
                         xRadius: trackH/2, yRadius: trackH/2).fill()
        }

        let attrsL: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor(white: 0.88, alpha: 1)]
        let attrsR: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: barColor]
        captionLeft.draw(at: NSPoint(x: 0, y: 0), withAttributes: attrsL)
        let rSize = captionRight.size(withAttributes: attrsR)
        captionRight.draw(at: NSPoint(x: bounds.width - rSize.width, y: 0), withAttributes: attrsR)
    }
}

final class SparkView: NSView {
    var values: [Int] = [] { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.20, alpha: 1).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
        guard values.count > 1 else { return }
        let mx = values.max() ?? 1
        let mn = values.min() ?? 0
        let span = max(1, mx - mn)
        let path = NSBezierPath()
        for (i, v) in values.enumerated() {
            let x = bounds.width * CGFloat(i) / CGFloat(values.count - 1)
            let y = 5 + (bounds.height - 10) * CGFloat(Double(v - mn) / Double(span))
            if i == 0 { path.move(to: NSPoint(x: x, y: y)) } else { path.line(to: NSPoint(x: x, y: y)) }
        }
        NSColor.systemOrange.setStroke()
        path.lineWidth = 1.6
        path.stroke()
    }
}

final class ModeBadge: NSView {
    var text: String = "无数据" { didSet { needsDisplay = true } }
    var color: NSColor = .systemGray { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 9, yRadius: 9)
        color.withAlphaComponent(0.15).setFill()
        path.fill()
        color.setStroke()
        path.lineWidth = 1
        path.stroke()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .bold),
            .foregroundColor: color]
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: (bounds.width - size.width)/2, y: (bounds.height - size.height)/2),
                  withAttributes: attrs)
    }
}

let modeTable: [Int: (String, NSColor)] = [
    126: ("均衡", .systemTeal),
    100: ("办公", .systemGreen),
    200: ("狂暴", .systemRed),
]

// MARK: - 桌面小组件

final class WidgetDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var badge: ModeBadge!
    var cpuBar: BarView!
    var memBar: BarView!
    var tempBar: BarView!
    var fanBar: BarView!
    var gpuBar: BarView!
    var vramBar: BarView!
    var spark: SparkView!
    var footLabel: NSTextField!
    var statusLabel: NSTextField!
    var monitor = Monitor()
    var tempHistory: [Double] = []

    let W: CGFloat = 330
    let H: CGFloat = 470

    func applicationDidFinishLaunching(_ n: Notification) {
        buildUI()
        monitor.start { [weak self] snap in self?.render(snap) }
    }

    private func label(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = NSFont.systemFont(ofSize: size, weight: weight)
        l.textColor = color
        return l
    }

    private func buildUI() {
        let saved = UserDefaults.standard.string(forKey: "widgetFrame")

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: W, height: H),
                          styleMask: [.borderless],
                          backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        if UserDefaults.standard.bool(forKey: "floatingForPreview") {
            window.level = .floating
        } else {
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)))
        }
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        window.isMovableByWindowBackground = true
        window.delegate = self
        window.appearance = NSAppearance(named: .darkAqua)

        let root = RoundedBox(frame: NSRect(x: 0, y: 0, width: W, height: H))
        window.contentView = root

        var y = H - 14

        func place(_ v: NSView, _ height: CGFloat, topGap: CGFloat = 8) {
            y -= topGap + height
            v.frame = NSRect(x: 14, y: y, width: W - 28, height: height)
            root.addSubview(v)
        }

        place(label("机械革命 · 蛟龙16 Pro", size: 10, weight: .medium,
                    color: NSColor(white: 0.55, alpha: 1)), 13, topGap: 0)

        badge = ModeBadge()
        badge.frame = NSRect(x: 14, y: y - 62, width: W - 28, height: 60)
        root.addSubview(badge)
        y -= 62 + 6

        cpuBar = BarView(); place(cpuBar, 28)
        memBar = BarView(); place(memBar, 28)
        tempBar = BarView(); place(tempBar, 28)
        fanBar = BarView(); place(fanBar, 28)
        gpuBar = BarView(); place(gpuBar, 28)
        vramBar = BarView(); place(vramBar, 28)

        place(label("CPU 温度趋势", size: 10, weight: .regular,
                    color: NSColor(white: 0.5, alpha: 1)), 12, topGap: 10)
        spark = SparkView()
        spark.frame = NSRect(x: 14, y: y - 44, width: W - 28, height: 40)
        root.addSubview(spark)
        y -= 44 + 8

        footLabel = label("", size: 10, weight: .regular, color: NSColor(white: 0.62, alpha: 1))
        footLabel.maximumNumberOfLines = 2
        place(footLabel, 26)

        statusLabel = label("正在读取…", size: 9, weight: .regular, color: NSColor(white: 0.45, alpha: 1))
        statusLabel.frame = NSRect(x: 14, y: 8, width: W - 28, height: 12)
        root.addSubview(statusLabel)

        // 右键菜单
        let menu = NSMenu()
        menu.addItem(withTitle: "立即刷新", action: #selector(refreshNow), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "退出小组件", action: #selector(quitMe), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        root.menu = menu

        if let s = saved {
            let r = NSRectFromString(s)
            window.setFrame(r, display: false)
        } else {
            let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            window.setFrame(NSRect(x: screen.maxX - W - 24, y: screen.maxY - H - 24, width: W, height: H),
                            display: false)
        }
        window.orderFrontRegardless()
    }

    func windowDidMove(_ notification: Notification) {
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: "widgetFrame")
    }

    @objc func refreshNow() {
        monitor.start { [weak self] snap in self?.render(snap) }
    }

    @objc func quitMe() { NSApp.terminate(nil) }

    private func render(_ s: Snapshot) {
        if let m = modeTable[s.modeRaw] {
            badge.text = m.0; badge.color = m.1
        } else if s.modeRaw >= 0 {
            badge.text = "未标定"; badge.color = .systemGray
        } else {
            badge.text = "无数据"; badge.color = .systemGray
        }

        cpuBar.captionLeft = "CPU 负载"
        cpuBar.captionRight = String(format: "%.0f%%", s.cpuLoad)
        cpuBar.fraction = s.cpuLoad / 100.0
        cpuBar.barColor = s.cpuLoad > 80 ? .systemRed : (s.cpuLoad > 50 ? .systemOrange : .systemTeal)

        memBar.captionLeft = "内存"
        memBar.captionRight = String(format: "%.1f / %.0f GB", s.memUsed, s.memTotal)
        memBar.fraction = s.memTotal > 0 ? s.memUsed / s.memTotal : 0
        memBar.barColor = .systemBlue

        let hottest = max(s.cpuTemp, s.gpuTemp)
        tempBar.captionLeft = "CPU / GPU 温度"
        tempBar.captionRight = (s.cpuTemp >= 0 && s.gpuTemp >= 0) ? "\(s.cpuTemp)°C / \(s.gpuTemp)°C" : "无数据"
        tempBar.fraction = hottest >= 0 ? min(1, Double(hottest) / 100.0) : 0
        tempBar.barColor = hottest >= 90 ? .systemRed : (hottest >= 75 ? .systemOrange : .systemTeal)

        fanBar.captionLeft = "风扇档位"
        fanBar.captionRight = s.fanLevel >= 0 ? "\(s.fanLevel) / 7" : "无数据"
        fanBar.fraction = s.fanLevel >= 0 ? Double(s.fanLevel) / 7.0 : 0
        fanBar.barColor = .systemPurple

        gpuBar.captionLeft = "GPU 利用率"
        gpuBar.captionRight = s.gpuUtil >= 0 ? String(format: "%.0f%%", s.gpuUtil) : "无数据"
        gpuBar.fraction = s.gpuUtil >= 0 ? s.gpuUtil / 100.0 : 0
        gpuBar.barColor = s.gpuUtil > 80 ? .systemRed : (s.gpuUtil > 40 ? .systemOrange : .systemTeal)

        let vramPct = s.vramTotalMB > 0 ? s.vramUsedMB / s.vramTotalMB : 0
        vramBar.captionLeft = "显存"
        vramBar.captionRight = (s.vramUsedMB >= 0 && s.vramTotalMB > 0)
            ? String(format: "%.0f MB / %.1f GB", s.vramUsedMB, s.vramTotalMB / 1024.0) : "无数据"
        vramBar.fraction = max(0, min(1, vramPct))
        vramBar.barColor = .systemIndigo

        if s.cpuTemp >= 0 {
            tempHistory.append(Double(s.cpuTemp))
            if tempHistory.count > 60 { tempHistory.removeFirst() }
        }
        spark.values = tempHistory.map { Int($0) }

        var bits: [String] = []
        if s.batteryPct >= 0 {
            bits.append("电量 \(s.batteryPct)%\(s.charging ? " 充电中" : "")")
            bits.append(s.acPower ? "AC 供电" : "电池供电")
        }
        if s.modeRaw >= 0 { bits.append("0x461=\(s.modeRaw)") }
        footLabel.stringValue = bits.joined(separator: " · ")

        let stamp = DateFormatter()
        stamp.dateFormat = "HH:mm:ss"
        if s.driverOK {
            statusLabel.stringValue = "驱动在线 · 采样 #\(s.seq) · 失败 \(s.failures) · \(stamp.string(from: s.timestamp))"
            statusLabel.textColor = NSColor(white: 0.45, alpha: 1)
        } else {
            statusLabel.stringValue = "驱动未加载 · 仅系统数据"
            statusLabel.textColor = .systemOrange
        }
    }
}

final class RoundedBox: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let p = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 14, yRadius: 14)
        NSColor(calibratedWhite: 0.11, alpha: 0.92).setFill()
        p.fill()
        NSColor(white: 0.30, alpha: 0.9).setStroke()
        p.lineWidth = 1
        p.stroke()
    }
}

let app = NSApplication.shared
let delegate = WidgetDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

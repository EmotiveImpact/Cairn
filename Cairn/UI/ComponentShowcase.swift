import SwiftUI
import AppKit

/// Isolated, sample-only component proposal. No production stores or file actions.
struct ComponentShowcase: View {
    @State private var selected = true
    @State private var buildSelected = false
    @State private var alerts = true
    @State private var scanning = false
    @State private var filter = "All files"
    @State private var showDialog = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 26) {
                HStack(spacing: 8) {
                    Circle().fill(Color.red.opacity(0.85)); Circle().fill(Color.yellow.opacity(0.9)); Circle().fill(Color.green.opacity(0.8))
                }.frame(width: 52, height: 12).padding(.bottom, 12)
                HStack { CairnLogo(size: 32); Text("Cairn").font(.system(size: 23, weight: .semibold)) }
                VStack(alignment: .leading, spacing: 25) {
                    nav("Overview", "house")
                    nav("Changes", "chart.xyaxis.line")
                    nav("Clean", "sparkles")
                    nav("Files", "doc.on.doc")
                    nav("Storage", "externaldrive")
                    nav("Activity", "clock.arrow.circlepath")
                }.padding(.top, 12)
                Spacer()
                nav("Settings", "gearshape")
            }.padding(24).frame(width: 192)
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("The finer details").font(.system(size: 27, weight: .semibold))
                        Text("A native component direction for Cairn.").foregroundStyle(Brand.textMuted)
                    }
                    Spacer()
                    Text("INTERACTIVE PREVIEW").font(.system(size: 9, weight: .medium)).tracking(1.2).foregroundStyle(Brand.textMuted).padding(.top, 9)
                }
                HStack(alignment: .top, spacing: 30) {
                    VStack(alignment: .leading, spacing: 15) {
                        caption("01", "Actions & controls")
                        HStack(spacing: 9) {
                            Button { scanning.toggle() } label: { Label(scanning ? "Stop scan" : "Scan Mac", systemImage: scanning ? "stop" : "arrow.clockwise") }.buttonStyle(ControlPanelButtonStyle(primary: true))
                            Button("Review…") { showDialog = true }.buttonStyle(ControlPanelButtonStyle())
                            Menu { Button("All files") { filter = "All files" }; Button("Archives") { filter = "Archives" } } label: { Label(filter, systemImage: "line.3.horizontal.decrease") }.menuStyle(.borderlessButton).fixedSize().padding(.horizontal, 10).frame(height: 32).background(Brand.wash(0.045), in: RoundedRectangle(cornerRadius: 7))
                        }
                        HStack(spacing: 10) {
                            badge("Review required", icon: "exclamationmark.circle", tint: Brand.amber)
                            badge("Protected", icon: "lock", tint: Brand.textMuted)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 15) {
                        caption("02", "Quiet preferences")
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Low-space alerts").fontWeight(.medium)
                                Text("Let me know below 30 GB").font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                            }
                            Spacer()
                            Toggle("Low-space alerts", isOn: $alerts).labelsHidden().toggleStyle(.switch).controlSize(.small).tint(Brand.blue)
                        }
                    }.frame(width: 235)
                }
                rule
                VStack(alignment: .leading, spacing: 15) {
                    HStack { caption("03", "Files, with room to breathe"); Spacer(); Text("2 sample items").font(.system(size: 11)).foregroundStyle(Brand.textMuted) }
                    fileRow("Design archive.zip", detail: "Downloads · Last opened 3 months ago", size: "2.4 GB", icon: "doc.zipper", checked: true)
                    rule
                    fileRow("Build output", detail: "Xcode · Generated files", size: "6.1 GB", icon: "hammer", checked: false)
                }
                rule
                HStack(alignment: .top, spacing: 30) {
                    VStack(alignment: .leading, spacing: 16) {
                        caption("04", "Visible progress")
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.clockwise").foregroundStyle(Brand.blue)
                            Text(scanning ? "Scanning your Mac" : "Scanning preview").fontWeight(.medium)
                            Spacer()
                            Text("64%").monospacedDigit().foregroundStyle(Brand.textMuted)
                        }
                        GeometryReader { g in
                            Capsule().fill(Brand.wash(0.06)).overlay(alignment: .leading) { Capsule().fill(Brand.blue).frame(width: g.size.width * 0.64) }
                        }.frame(height: 4)
                        HStack { Text("Developer files"); Spacer(); Text("12,408 checked") }.font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.safeCyan)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Ready for your review").fontWeight(.medium)
                                Text("Nothing is removed automatically.").font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                            }
                        }.padding(.top, 9)
                    }.frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 13) {
                        caption("05", "Clear confirmations")
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                Image(systemName: "trash").font(.system(size: 21)).foregroundStyle(Brand.blue)
                                Text("Move 1 item to Trash?").font(.system(size: 15, weight: .semibold))
                            }
                            Text("You can put it back from Activity. Files in Trash still occupy space.").font(.system(size: 12)).foregroundStyle(Brand.textSecondary).fixedSize(horizontal: false, vertical: true)
                            HStack { Spacer(); Button("Cancel") {}.buttonStyle(ControlPanelButtonStyle()); Button("Move to Trash") { showDialog = true }.buttonStyle(ControlPanelButtonStyle(primary: true)) }
                        }.padding(18).background(Brand.surfaceElevated.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                    }.frame(width: 320)
                }
                Spacer(minLength: 0)
                HStack { Text("Sample data · No scanning or cleanup actions"); Spacer(); Text("Native SwiftUI · Component study") }.font(.system(size: 10)).foregroundStyle(Brand.textMuted)
            }.font(.system(size: 13)).padding(30).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Brand.background, in: RoundedRectangle(cornerRadius: 18)).padding([.top, .trailing, .bottom], 12)
        }.foregroundStyle(Brand.textPrimary).background(Brand.chrome).frame(width: 1100, height: 740).preferredColorScheme(.dark)
            .alert("Preview only", isPresented: $showDialog) { Button("Done", role: .cancel) {} } message: { Text("These controls demonstrate the design. Your files are untouched.") }
    }
    private var rule: some View { Rectangle().fill(Brand.separator).frame(height: 1) }
    private func nav(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 13) { Image(systemName: icon).font(.system(size: 19, weight: .light)).frame(width: 23); Text(title).font(.system(size: 13)) }.foregroundStyle(Brand.textSecondary)
    }
    private func caption(_ number: String, _ title: String) -> some View {
        HStack(spacing: 9) { Text(number).foregroundStyle(Brand.blue); Text(title).foregroundStyle(Brand.textMuted) }.font(.system(size: 11, weight: .medium))
    }
    private func badge(_ title: String, icon: String, tint: Color) -> some View {
        Label(title, systemImage: icon).font(.system(size: 10)).foregroundStyle(tint).padding(.horizontal, 9).padding(.vertical, 5).background(tint.opacity(0.07), in: Capsule())
    }
    private func fileRow(_ name: String, detail: String, size: String, icon: String, checked: Bool) -> some View {
        HStack(spacing: 14) {
            Toggle(name, isOn: checked ? $selected : $buildSelected).labelsHidden().toggleStyle(.checkbox).tint(Brand.blue)
            Image(systemName: icon).font(.system(size: 23, weight: .light)).foregroundStyle(Brand.blue).frame(width: 36, height: 40)
            VStack(alignment: .leading, spacing: 5) { Text(name).fontWeight(.medium); Text(detail).font(.system(size: 11)).foregroundStyle(Brand.textMuted) }
            Spacer()
            Text(size).monospacedDigit().foregroundStyle(Brand.textSecondary)
            Button("Inspect") { showDialog = true }.buttonStyle(ControlPanelButtonStyle())
        }.padding(.vertical, 4)
    }
}

@MainActor enum ComponentShowcaseRunner {
    static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let screen = CommandLine.arguments.first(where: { $0.hasPrefix("--capture-screen=") }).map { String($0.dropFirst("--capture-screen=".count)) }.flatMap { value in NavSection(rawValue: value) != nil || value == "dialog" || value == "review" ? value : nil }
        // --capture-light takes the same picture in Light, to check both looks.
        let light = CommandLine.arguments.contains("--capture-light")
        let minimum = CommandLine.arguments.contains("--capture-minimum")
        let width: CGFloat = minimum ? 1024 : 1100
        let height: CGFloat = minimum ? 658 : 740
        let stress = CommandLine.arguments.contains("--capture-review-stress")
        let scheme: ColorScheme = light ? .light : .dark
        NSApp.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
        let root: AnyView
        if screen == "dialog" {
            root = AnyView(WorkspaceConfirmation(title: "Move 2 items to Trash?", explanation: "Review the exact locations. Files in Trash still occupy disk space, and can be put back while they remain available.", entries: ["/Sample/Downloads/Design archive.zip", "/Sample/Downloads/Old installer.dmg"], actionTitle: "Move to Trash", action: {}).frame(width: width, height: height).background(Brand.chrome).preferredColorScheme(scheme))
        }
        else if screen == "review" {
            root = AnyView(ReviewSheet(store: ScanStore(), proEnabled: false, sample: stress ? .stress : .showcase, onDone: { _ in })
                .frame(width: width, height: height).background(Brand.chrome).preferredColorScheme(scheme))
        }
        else if screen != nil { root = AnyView(AppShell().frame(width: width, height: height).preferredColorScheme(scheme)) }
        else { root = AnyView(ComponentShowcase()) }
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Cairn · Component preview"
        window.contentView = host
        window.center()
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            host.layoutSubtreeIfNeeded()
            if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: bitmap)
                if let data = bitmap.representation(using: .png, properties: [:]) {
                    let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("artifacts/component-showcase/\(screen ?? "preview")\(light ? "-light" : "")\(minimum ? "-minimum" : "")\(stress ? "-stress" : "").png")
                    do { try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true); try data.write(to: output) }
                    catch { fputs("Preview export failed: \(error)\n", stderr) }
                }
            }
            if !CommandLine.arguments.contains("--showcase-live") { app.terminate(nil) }
        }
        app.run()
    }
}

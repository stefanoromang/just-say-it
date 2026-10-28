// Just Say It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

import AppKit
import SwiftUI

struct NoteView: View {
    @ObservedObject var n = NoteTaker.shared
    @ObservedObject var tick = Ticker.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle().fill(n.isRecording ? .red : .gray).frame(width: 10, height: 10)
                    .opacity(n.isRecording && tick.blink ? 0.3 : 1)
                Text("Note Taker").font(.headline)
                if let s = n.startedAt, n.isRecording {
                    Text(n.stamp(tick.now.timeIntervalSince(s))).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                }
                Spacer()
                if n.isRecording {
                    Button { Task { await n.stop() } } label: { Label("Stop", systemImage: "stop.fill") }
                        .buttonStyle(.borderedProminent).tint(.red)
                } else {
                    Button { Task { await n.start() } } label: { Label("New note", systemImage: "record.circle") }
                        .buttonStyle(.borderedProminent).tint(.purple)
                }
            }
            Text(n.status + (n.isRecording ? " · press Right ⇧ three times to stop" : ""))
                .font(.caption).foregroundStyle(.secondary)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(n.lines) { l in
                            HStack(alignment: .top, spacing: 8) {
                                Text(n.stamp(l.time)).font(.caption.monospacedDigit()).foregroundStyle(.tertiary).frame(width: 44, alignment: .leading)
                                Text(l.speaker).font(.caption.bold()).foregroundStyle(l.speaker == "Me" ? .purple : .blue).frame(width: 48, alignment: .leading)
                                Text(l.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        ForEach(n.live.keys.sorted(), id: \.self) { k in
                            if let t = n.live[k], !t.isEmpty {
                                HStack(alignment: .top, spacing: 8) {
                                    Text("…").frame(width: 44, alignment: .leading).foregroundStyle(.tertiary)
                                    Text(k).font(.caption.bold()).foregroundStyle(k == "Me" ? .purple : .blue).frame(width: 48, alignment: .leading)
                                    Text(t).foregroundStyle(.secondary).italic()
                                }
                            }
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(10)
                }
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .onChange(of: n.lines.count) { proxy.scrollTo("end") }
                .onChange(of: n.live) { proxy.scrollTo("end") }
            }

            HStack {
                Button("Copy transcript") { n.copyAll() }.disabled(n.lines.isEmpty)
                if let u = n.lastNoteURL, !n.isRecording {
                    Button("Open note") { NSWorkspace.shared.open(u) }
                }
                Button("Notes folder") { NSWorkspace.shared.open(NoteTaker.notesDir) }
                Spacer()
                Text("Saved on this Mac only").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 380)
    }
}

/// Drives the timer and blinking dot.
@MainActor
final class Ticker: ObservableObject {
    static let shared = Ticker()
    @Published var now = Date()
    @Published var blink = false
    private init() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated {
                Ticker.shared.now = Date()
                Ticker.shared.blink.toggle()
            }
        }
    }
}

@MainActor
final class NoteWindow {
    static let shared = NoteWindow()
    private var panel: NSPanel?

    func show() {
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
                            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
                            backing: .buffered, defer: false)
            p.title = "Just Say It – Note Taker"
            p.level = .floating
            p.isReleasedWhenClosed = false
            p.hidesOnDeactivate = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.contentView = NSHostingView(rootView: NoteView())
            if let f = NSScreen.main?.visibleFrame {
                p.setFrameOrigin(NSPoint(x: f.maxX - 580, y: f.maxY - 480))
            }
            panel = p
        }
        panel?.orderFrontRegardless()
    }
}

// Just Say It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

import AppKit
import SwiftUI

struct NoteView: View {
    @ObservedObject var n = NoteTaker.shared
    @ObservedObject var tick = Ticker.shared
    @ObservedObject var captions = CaptionConnector.shared

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
                    Button { n.endByUser() } label: { Label("End Note Taker", systemImage: "stop.fill") }
                        .buttonStyle(.borderedProminent).tint(.red)
                        .help("Finish now, save the notes and send them to CollectivIQ")
                } else {
                    Button { Task { await n.start() } } label: { Label("New note", systemImage: "record.circle") }
                        .buttonStyle(.borderedProminent).tint(.purple)
                }
            }
            Text(n.status + (n.isRecording ? (n.origin == .call ? " · stops by itself when the call ends" : " · press Right ⇧ three times or End Note Taker to finish") : ""))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Label(captions.status, systemImage: "captions.bubble").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Import transcript…") { captions.importTranscript() }.disabled(!n.isRecording)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if !captions.lines.isEmpty {
                            Text("MEETING CAPTIONS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            ForEach(Array(captions.lines.enumerated()), id: \.offset) { _, l in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(l.speaker).font(.subheadline.weight(.semibold)).foregroundStyle(.tint)
                                    Text(l.text).textSelection(.enabled)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
                            }
                            Divider()
                            Text("LOCAL AUDIO BACKUP").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        ForEach(n.lines) { l in
                            HStack(alignment: .top, spacing: 8) {
                                Text(n.stamp(l.time)).font(.caption.monospacedDigit()).foregroundStyle(.tertiary).frame(width: 44, alignment: .leading)
                                Text(l.speaker).font(.caption.bold()).foregroundStyle(l.speaker == "Me" ? .purple : .blue).frame(width: 72, alignment: .leading)
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
                Text(Store.shared.prefs.ciqEnabled ? "Saved locally · CollectivIQ delivery enabled" : "Saved on this Mac").font(.caption2).foregroundStyle(.secondary)
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

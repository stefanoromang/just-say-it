// Just Say It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

import AppKit
import EventKit
import Foundation

struct UpcomingMeeting: Identifiable, Equatable {
    let id: String          // event id + start time (unique per occurrence)
    let title: String
    let start: Date
    let end: Date
    let link: MeetingLink
    let calendar: String
    let attendees: [String]
}

/// Watches your calendars (Google and Microsoft accounts added to macOS Calendar),
/// joins Zoom / Meet / Teams calls on time and runs the Note Taker for each one.
@MainActor
final class AutoJoin: ObservableObject {
    static let shared = AutoJoin()

    @Published private(set) var access: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    @Published private(set) var upcoming: [UpcomingMeeting] = []
    @Published private(set) var calendars: [EKCalendar] = []
    @Published private(set) var current: UpcomingMeeting?
    @Published var lastAction = ""

    private let store = EKEventStore()
    private var timer: Timer?
    private var joined: Set<String> = []
    private var notified: Set<String> = []
    private var stopTimer: Timer?

    var hasAccess: Bool { access == .fullAccess }

    func boot() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
            MainActor.assumeIsolated { AutoJoin.shared.refresh() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
            MainActor.assumeIsolated { AutoJoin.shared.tick() }
        }
        refresh()
    }

    func requestAccess() {
        Task {
            _ = try? await store.requestFullAccessToEvents()
            access = EKEventStore.authorizationStatus(for: .event)
            if !hasAccess {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
            }
            refresh()
        }
    }

    func refresh() {
        access = EKEventStore.authorizationStatus(for: .event)
        guard hasAccess else { upcoming = []; calendars = []; return }
        calendars = store.calendars(for: .event).sorted { ($0.source.title, $0.title) < ($1.source.title, $1.title) }
        let excluded = Set(Store.shared.prefs.autoJoinExcludedCalendars)
        let cals = calendars.filter { !excluded.contains($0.calendarIdentifier) }
        guard !cals.isEmpty else { upcoming = []; return }
        let now = Date()
        let pred = store.predicateForEvents(withStart: now.addingTimeInterval(-3 * 3600), end: now.addingTimeInterval(36 * 3600), calendars: cals)
        upcoming = store.events(matching: pred).compactMap { e -> UpcomingMeeting? in
            guard !e.isAllDay, e.endDate > now, e.status != .canceled else { return nil }
            // Skip meetings you declined.
            if let me = e.attendees?.first(where: { $0.isCurrentUser }), me.participantStatus == .declined { return nil }
            let texts: [String?] = [e.url?.absoluteString, e.location, e.notes]
            guard let link = MeetingLinks.find(in: texts) else { return nil }
            let names = (e.attendees ?? []).compactMap { $0.name }.filter { !$0.isEmpty }
            return UpcomingMeeting(id: "\(e.calendarItemExternalIdentifier ?? e.eventIdentifier ?? UUID().uuidString)@\(Int(e.startDate.timeIntervalSince1970))",
                                   title: e.title?.isEmpty == false ? e.title! : "Meeting",
                                   start: e.startDate, end: e.endDate, link: link,
                                   calendar: "\(e.calendar.source.title) · \(e.calendar.title)",
                                   attendees: Array(names.prefix(12)))
        }
        .sorted { $0.start < $1.start }
    }

    func isCalendarIncluded(_ c: EKCalendar) -> Bool {
        !Store.shared.prefs.autoJoinExcludedCalendars.contains(c.calendarIdentifier)
    }

    func setCalendar(_ c: EKCalendar, included: Bool) {
        var ex = Set(Store.shared.prefs.autoJoinExcludedCalendars)
        if included { ex.remove(c.calendarIdentifier) } else { ex.insert(c.calendarIdentifier) }
        Store.shared.prefs.autoJoinExcludedCalendars = Array(ex)
        refresh()
    }

    // MARK: Scheduler

    private func tick() {
        let p = Store.shared.prefs
        guard p.autoJoinEnabled, hasAccess else { return }
        let now = Date()
        let lead = TimeInterval(p.autoJoinLeadSeconds)
        for m in upcoming where !joined.contains(m.id) {
            let joinAt = m.start.addingTimeInterval(-lead)
            // Join in the window from "lead time before" until 10 minutes after the start.
            if now >= joinAt && now < m.start.addingTimeInterval(600) && now < m.end {
                join(m, automatic: true)
                break
            } else if now >= joinAt.addingTimeInterval(-120) && now < joinAt && !notified.contains(m.id) {
                notified.insert(m.id)
                lastAction = "Joining “\(m.title)” at \(m.start.formatted(date: .omitted, time: .shortened))"
                Controller.shared.overlay.show(.error("Joining “\(m.title)” in 2 min – \(m.link.platform.rawValue)"))
            }
        }
        // Stop notes when the current meeting is over.
        if let c = current, now >= c.end.addingTimeInterval(TimeInterval(p.autoJoinStopGraceSeconds)) {
            finishCurrent()
        }
    }

    func join(_ m: UpcomingMeeting, automatic: Bool) {
        joined.insert(m.id)
        let p = Store.shared.prefs
        let url = MeetingLinks.appURL(for: m.link)
        let opened = NSWorkspace.shared.open(url) || NSWorkspace.shared.open(m.link.url)
        lastAction = (opened ? "Joined" : "Couldn't open") + " “\(m.title)” on \(m.link.platform.rawValue)"
        guard opened, p.autoJoinStartNotes, p.noteTakerEnabled else { return }
        current = m
        let notes = NoteTaker.shared
        Task {
            if notes.isRecording && notes.origin == .call { return }   // the live call is already being recorded
            if notes.isRecording { await notes.stop() }
            // Give the meeting app a moment to connect audio.
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await notes.start(meeting: m, origin: .calendar)
        }
    }

    func finishCurrent() {
        guard current != nil else { return }
        current = nil
        Task { await NoteTaker.shared.stop() }
    }
}

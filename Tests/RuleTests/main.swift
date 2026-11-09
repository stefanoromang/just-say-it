// Just Say It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it
//
// Self-checking tests for the Mac text cleanup rules (no XCTest needed).
// Run with:  swift run RuleTests

import Foundation

var failures = 0
var passed = 0

@MainActor func check(_ name: String, _ actual: String, _ expected: String) {
    if actual == expected { passed += 1 } else {
        failures += 1
        print("✗ \(name)\n   expected: \(expected.debugDescription)\n   actual:   \(actual.debugDescription)")
    }
}

@MainActor func check(_ name: String, _ cond: Bool) {
    if cond { passed += 1 } else { failures += 1; print("✗ \(name)") }
}

@MainActor func run() {
    check("fillers", TextBrain.ruleClean("um so I think we should uh meet tomorrow"), "So I think we should meet tomorrow")
    check("like filler", TextBrain.ruleClean("I was like, going to the store"), "I was going to the store")
    check("you know", TextBrain.ruleClean("you know it works"), "It works")
    check("repeats", TextBrain.ruleClean("the the report is ready"), "The report is ready")
    check("scratch that", TextBrain.ruleClean("send it friday. scratch that. send it Monday"), "Send it Monday")
    check("scratch that at start", TextBrain.ruleClean("scratch that hello there"), "Hello there")
    check("spoken punctuation", TextBrain.ruleClean("hello comma how are you question mark"), "Hello, how are you?")
    check("new line", TextBrain.ruleClean("first line new line second line"), "First line\nSecond line")
    check("new paragraph", TextBrain.ruleClean("intro new paragraph body"), "Intro\n\nBody")
    check("capitalize", TextBrain.capitalizeSentences("one. two! three?"), "One. Two! Three?")

    let reps = [Replacement(heard: "cloud code", write: "Claude Code")]
    check("replacements", TextBrain.applyReplacements("i use cloud code and kubernetes", reps, vocabulary: ["Kubernetes"]),
          "i use Claude Code and Kubernetes")
    check("replacement $", TextBrain.applyReplacements("the price is fine", [Replacement(heard: "price", write: "$5")], vocabulary: []),
          "the $5 is fine")

    let sn = [Snippet(trigger: "my address", text: "1 Main St")]
    let (whole, isWhole) = TextBrain.expandSnippets("My address.", sn)
    check("whole snippet", whole, "1 Main St")
    check("whole snippet flag", isWhole)
    let (inline, inlineWhole) = TextBrain.expandSnippets("here it is insert my link thanks", [Snippet(trigger: "my link", text: "https://x.y")])
    check("inline snippet", inline, "here it is https://x.y thanks")
    check("inline snippet flag", !inlineWhole)

    check("edit command", TextBrain.looksLikeEditCommand("make this shorter"))
    check("not edit command", !TextBrain.looksLikeEditCommand("I will be there at noon"))
    check("keepsMeaning rejects answer", !TextBrain.keepsMeaning("Paris", "What's the capital of France"))
    check("keepsMeaning accepts cleanup", TextBrain.keepsMeaning("I think we should meet on Wednesday at 3 PM.",
                                                                 "I think we should meet on Tuesday no wait Wednesday at 3pm"))
    check("placeholders", TextBrain.removePlaceholders("Hi John,\n\nThanks!\n\nBest regards,\n[Your Name]"),
          "Hi John,\n\nThanks!\n\nBest regards,")
    check("fit after sentence", TextBrain.fitToCursor("Thanks a lot.", before: "Great talking to you. "), "Thanks a lot.")
    check("fit mid sentence", TextBrain.fitToCursor("Thanks a lot.", before: "I wanted to say"), " thanks a lot.")
    check("fit keeps I", TextBrain.fitToCursor("I agree.", before: "Well"), " I agree.")
    check("fit empty", TextBrain.fitToCursor("Hello.", before: nil), "Hello.")

    // Meeting links
    check("zoom link", MeetingLinks.find(in: ["Join: https://us06web.zoom.us/j/81234567890?pwd=AbC1.1 ID 812"])?.platform == .zoom)
    check("meet link", MeetingLinks.find(in: ["https://meet.google.com/abc-defg-hij"])?.platform == .meet)
    check("teams link", MeetingLinks.find(in: ["<https://teams.microsoft.com/l/meetup-join/19%3ameeting_X%40thread.v2/0?context=%7b%7d>"])?.platform == .teams)
    check("no link", MeetingLinks.find(in: ["Lunch at noon", "https://docs.google.com/x"]) == nil)
    check("zoom app url", MeetingLinks.appURL(for: MeetingLinks.find(in: ["https://zoom.us/j/123?pwd=x"])!).absoluteString,
          "zoommtg://zoom.us/join?action=join&confno=123&pwd=x")

    // Update version comparison
    check("1.6 > 1.5", Updater.isNewer("1.6", than: "1.5"))
    check("1.10 > 1.9", Updater.isNewer("v1.10", than: "1.9"))
    check("1.5 == 1.5.0", !Updater.isNewer("1.5.0", than: "1.5"))
    check("1.4 < 1.5", !Updater.isNewer("1.4", than: "1.5"))

    // CollectivIQ message
    check("ciq message", CollectivIQ.message(prompt: " Recap this. ", title: "Weekly sync", transcript: "Me: hi"),
          "Recap this.\n\nMeeting: Weekly sync\n\nMe: hi")
    check("ciq default prompt", CollectivIQ.message(prompt: "", title: nil, transcript: "x") == ciqStandardPrompt + "\n\nx")
    check("ciq prompt ends with information marker", ciqStandardPrompt.hasSuffix("- HERE IS THE INFORMATION :"))

    // Call apps: every service is recognised from its app, web address or window title
    let natives: [(String, String)] = [
        ("com.microsoft.teams2", "teams"), ("com.microsoft.teams2.modulehost", "teams"), ("us.zoom.xos", "zoom"),
        ("com.apple.FaceTime", "facetime"), ("com.cisco.webexmeetingsapp", "webex"), ("com.webex.meetingmanager", "webex"),
        ("com.tinyspeck.slackmacgap", "slack"), ("com.hnc.Discord", "discord"), ("com.skype.skype", "skype"),
        ("com.whereby.app", "whereby"), ("org.jitsi.jitsi-meet", "jitsi"), ("com.ringcentral.glip", "ringcentral"),
        ("com.ringcentral.video", "ringcentral"), ("com.logmein.GoToMeeting", "goto"), ("com.zoho.meeting", "zoho"),
        ("org.whispersystems.signal-desktop", "signal"), ("net.whatsapp.WhatsApp", "whatsapp"), ("ru.keepcoder.Telegram", "telegram"),
    ]
    for (bundle, id) in natives {
        if case .native(let svc)? = CallApps.kind(bundleID: bundle) { check("app \(bundle)", svc.id == id) } else { check("app \(bundle)", false) }
    }
    check("chrome is a browser", CallApps.kind(bundleID: "com.google.Chrome.helper") == .browser("Google Chrome"))
    check("music is not a call", CallApps.kind(bundleID: "com.apple.Music") == nil)
    let urls: [(String, String?)] = [
        ("https://meet.google.com/abc-defg-hij?authuser=0", "meet"), ("https://meet.google.com/landing", nil),
        ("https://teams.microsoft.com/v2/", "teams"), ("https://app.zoom.us/wc/81234567890/join", "zoom"),
        ("https://acme.webex.com/meet/jdoe", "webex"), ("https://app.slack.com/huddle/T123/C456", "slack"),
        ("https://whereby.com/stefano-room", "whereby"), ("https://meet.jit.si/MyStandup", "jitsi"),
        ("https://v.ringcentral.com/join/123", "ringcentral"), ("https://app.goto.com/meeting/123456789", "goto"),
        ("https://meeting.zoho.com/meeting/join", "zoho"), ("https://facetime.apple.com/join#v=1&p=abc", "facetime"),
        ("https://web.skype.com/", "skype"), ("https://discord.com/channels/123/456", "discord"),
        ("https://mail.google.com/mail/u/0/", nil), ("https://www.youtube.com/watch?v=x", nil),
    ]
    for (u, id) in urls { check("url \(u)", CallApps.service(forURL: u)?.id == id) }
    check("meet title", CallApps.service(forTitle: "Meet - abc-defg-hij - Google Chrome")?.id == "meet")
    check("jitsi title not meet", CallApps.service(forTitle: "MyStandup | Jitsi Meet - Google Chrome")?.id == "jitsi")
    check("gmail title", CallApps.service(forTitle: "Inbox - Gmail - Google Chrome") == nil)
    check("16 call apps", CallApps.services.count >= 16)

    print(failures == 0 ? "✓ All \(passed) Mac rule tests passed" : "\(failures) failed, \(passed) passed")
    exit(failures == 0 ? 0 : 1)
}

MainActor.assumeIsolated { run() }

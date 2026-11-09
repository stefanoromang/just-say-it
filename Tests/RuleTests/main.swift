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

    // Mixed languages: real word timings/confidences from an English → Spanish → English recording.
    func w(_ t: String, _ a: Double, _ b: Double, _ c: Double) -> SpokenWord { SpokenWord(text: t, start: a, end: b, confidence: c) }
    let en: [SpokenWord] = [w("Hi ", 0, 0.3, 0.35), w("Maria", 0.3, 0.8, 0.9), w(", ", 0.9, 0.9, 0.9), w("I ", 0.9, 1.0, 0.77),
        w("wanted ", 1.0, 1.5, 0.91), w("to ", 1.5, 1.7, 0.93), w("confirm ", 1.7, 2.3, 0.78), w("the ", 2.3, 2.5, 0.69),
        w("meeting ", 2.5, 2.8, 0.59), w("for ", 2.8, 3.0, 0.51), w("Thursday ", 3.0, 3.6, 0.83), w("at ", 3.6, 3.7, 0.84),
        w("three ", 3.7, 4.2, 0.65), w("this ", 4.5, 5.4, 0.12), w("week ", 5.4, 5.6, 0.08), w("with ", 5.6, 5.9, 0.06),
        w("the ", 5.9, 6.2, 0.15), w("project", 6.2, 8.0, 0.02), w(". ", 8.6, 8.6, 0.02), w("Thanks", 8.6, 9.1, 0.64),
        w(". ", 9.2, 9.2, 0.64), w("Talk ", 9.2, 9.6, 0.67), w("soon", 9.6, 10.1, 0.68), w(".", 10.5, 10.5, 0.68)]
    let es: [SpokenWord] = [w("Hi ", 0, 0.3, 0.23), w("Maria", 0.3, 0.8, 0.91), w(", ", 0.9, 0.9, 0.91), w("I ", 0.9, 1.0, 0.61),
        w("wanted ", 1.0, 1.5, 0.76), w("to ", 1.5, 1.6, 0.88), w("confirm ", 1.6, 2.3, 0.63), w("the ", 2.3, 2.5, 0.79),
        w("meeting ", 2.5, 2.9, 0.61), w("or ", 2.9, 3.0, 0.78), w("Thursday ", 3.0, 3.7, 0.83), w("at ", 3.7, 3.8, 0.78),
        w("three", 3.8, 4.2, 0.85), w(". ", 4.7, 4.7, 0.85), w("Please ", 4.7, 4.9, 0.16), w("necesito ", 4.9, 5.4, 0.66),
        w("que ", 5.4, 5.5, 0.85), w("me ", 5.5, 5.7, 0.82), w("envíes ", 5.7, 6.1, 0.8), w("el ", 6.1, 6.2, 0.93),
        w("presupuesto ", 6.2, 6.8, 0.93), w("del ", 6.8, 6.9, 0.89), w("proyecto ", 6.9, 7.5, 0.94), w("por ", 7.5, 7.7, 0.94),
        w("favor", 7.7, 8.1, 0.89), w(". ", 8.7, 8.7, 0.89), w("Thanks ", 8.7, 9.1, 0.46), w("Talk ", 9.3, 9.6, 0.46),
        w("soon", 9.6, 10.1, 0.53), w(".", 10.5, 10.5, 0.53)]
    let mixed = LanguageMix.merge(["en_US": en, "es_MX": es], languages: ["en_US", "es_MX"])
    check("mix: 3 pieces en/es/en", mixed.map(\.language) == ["en_US", "es_MX", "en_US"])
    let mixedText = LanguageMix.join(mixed.map(\.text))
    check("mix: English kept", mixedText.hasPrefix("Hi Maria, I wanted to confirm the meeting for Thursday at three"))
    check("mix: Spanish kept", mixedText.contains("necesito que me envíes el presupuesto del proyecto por favor"))
    check("mix: ends in English", mixedText.hasSuffix("Thanks. Talk soon.") || { print("   got:", mixedText); return false }())
    check("mix: single language unchanged", LanguageMix.text(["en_US": en], languages: ["en_US"]).hasPrefix("Hi Maria"))
    check("reads as Spanish", LanguageMix.readsAs("necesito que me envíes el presupuesto del proyecto", language: "es_MX") > 0.5)
    check("reads as English", LanguageMix.readsAs("I wanted to confirm the meeting for Thursday", language: "es_MX") < 0.3)
    check("join adds sentence break", LanguageMix.join(["hello there", "Gracias"]) == "hello there. Gracias")
    // Live merging (Note Taker): phrases come out once both languages are done with them.
    let live = LanguageMix.Stream(languages: ["en_US", "es_MX"])
    live.add("en_US", Array(en.prefix(13)), through: 4.3)
    check("stream waits for all languages", live.drain().isEmpty)
    live.add("es_MX", Array(es.prefix(13)), through: 4.3)
    live.add("en_US", Array(en.dropFirst(13)), through: 10.5)
    live.add("es_MX", Array(es.dropFirst(13)), through: 10.5)
    let streamed = live.drain(final: true)
    check("stream final en/es/en", streamed.map(\.language) == ["en_US", "es_MX", "en_US"])

    // Learning from corrections
    let subs = LearnCore.substitutions(from: "Please send it to Mark at Acme by Friday", to: "Please send it to Marc at ACME by Friday")
    check("learns name fix", subs.contains { $0.0 == "Mark" && $0.1 == "Marc" })
    check("learns casing fix", subs.contains { $0.0 == "Acme" && $0.1 == "ACME" })
    check("ignores big rewrites", LearnCore.substitutions(from: "can you send me the report", to: "Kindly forward the quarterly summary document to me at your earliest convenience").isEmpty)
    var learning = Learning()
    LearnCore.learn(&learning, original: "Talk to Mark tomorrow", edited: "Talk to Marc tomorrow")
    check("one correction isn't automatic yet", LearnCore.learnedFixes(learning).isEmpty)
    LearnCore.learn(&learning, original: "Mark said yes", edited: "Marc said yes")
    check("two corrections become automatic", LearnCore.learnedFixes(learning).contains { $0.heard == "mark" && $0.write == "Marc" })
    check("name learned as a term", LearnCore.learnedTerms(learning).contains("Marc"))
    for _ in 0..<8 { learning.languageCounts["en_US", default: 0] += 1 }
    learning.languageCounts["es_MX"] = 2
    check("language prior", abs((LearnCore.languagePrior(learning)["en_US"] ?? 0) - 0.8) < 0.001)
    LearnCore.remember(&learning, example: "Hi team, the launch moves to Monday. Thanks!", category: "work")
    check("style example kept", LearnCore.styleBlock(learning, category: "work")?.contains("launch moves") == true)

    // CollectivIQ sending rule
    check("route: Notetaker gets raw", CiqRoute.Route.parse("route:notetaker:Notetaker") == .notetaker("Notetaker") && CiqRoute.Route.notetaker("N").sendsRaw)
    check("route: assistant gets AI", CiqRoute.Route.parse("route:assistant:Ana") == .assistant("Ana") && !CiqRoute.Route.assistant("Ana").sendsRaw)
    check("route: no DDR → chat", CiqRoute.Route.parse("route:none") == .chat && CiqRoute.Route.chat.destination == .chat)
    check("route: DDR destination", CiqRoute.Route.assistant("Ana").destination == .ddr("Ana"))
    check("route: wait ignored", CiqRoute.Route.parse("wait") == nil)
    check("chat models", CiqRoute.chatModels == ["Gemini", "Nemotron"])

    print(failures == 0 ? "✓ All \(passed) Mac rule tests passed" : "\(failures) failed, \(passed) passed")
    exit(failures == 0 ? 0 : 1)
}

MainActor.assumeIsolated { run() }

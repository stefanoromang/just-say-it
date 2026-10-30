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

    print(failures == 0 ? "✓ All \(passed) Mac rule tests passed" : "\(failures) failed, \(passed) passed")
    exit(failures == 0 ? 0 : 1)
}

MainActor.assumeIsolated { run() }

// Just Say It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

import AppKit
import Foundation
import UserNotifications
import WebKit

/// Sends Note Taker transcripts to CollectivIQ in the background.
/// CollectivIQ runs in a hidden in-app web view; the window is shown only when
/// the person has to sign in. Each person signs in once; the session is remembered.
@MainActor
enum CollectivIQ {
    static let chatURL = URL(string: "https://collectiviq.ai/chat")!
    static let loginURL = URL(string: "https://collectiviq.ai/login")!
    static let defaultPrompt = ciqStandardPrompt

    enum Choice { case raw, ai, both }

    /// Where a message goes: a new CIQ chat, or a DDR's direct-message chat (e.g. "Notetaker").
    enum Destination: Equatable { case chat, ddr(String) }

    static func message(prompt: String, title: String?, transcript: String) -> String {
        var s = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { s = defaultPrompt }
        s += "\n\n"
        if let title, !title.isEmpty { s += "Meeting: \(title)\n\n" }
        s += transcript
        return s
    }

    /// Raw transcript on its own (no prompt).
    static func rawMessage(title: String?, raw: String) -> String {
        var s = "RAW TRANSCRIPT (exactly as heard)"
        if let title, !title.isEmpty { s += " – \(title)" }
        return s + "\n\n" + raw
    }

    /// Called when a recording is saved: asks what to send and where, then sends in the background.
    static func deliver(title: String?, raw: String, smart: String?) {
        guard Store.shared.prefs.ciqEnabled, !raw.isEmpty else { return }
        guard let choice = askWhat() else { return }
        guard let dest = askWhere() else { return }
        let prompt = Store.shared.prefs.ciqPrompt
        let ai = message(prompt: prompt, title: title, transcript: smart ?? raw)
        let text: String
        switch choice {
        case .raw: text = rawMessage(title: title, raw: raw)
        case .ai: text = ai
        case .both: text = rawMessage(title: title, raw: raw) + "\n\n" + String(repeating: "─", count: 40) + "\n\n" + ai
        }
        CIQSender.shared.send([text], to: dest)
    }

    /// For "Send my last note now" (asks where; no "what" question).
    static func send(title: String?, transcript: String, force: Bool = false) {
        let p = Store.shared.prefs
        guard (p.ciqEnabled || force), !transcript.isEmpty else { return }
        guard let dest = askWhere() else { return }
        CIQSender.shared.send([message(prompt: p.ciqPrompt, title: title, transcript: transcript)], to: dest)
    }

    static func showWindow(signIn: Bool = false) {
        CIQSender.shared.show(url: signIn ? loginURL : chatURL)
    }

    private static func alert(_ title: String, _ info: String, _ buttons: [String]) -> Int? {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        defer { NSApp.setActivationPolicy(.accessory) }
        let a = NSAlert()
        a.messageText = title
        a.informativeText = info
        for b in buttons { a.addButton(withTitle: b) }
        let skip = a.addButton(withTitle: "Don't send")
        skip.keyEquivalent = "\u{1b}"
        a.window.level = .floating
        let r = a.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        return r < buttons.count ? r : nil
    }

    private static func askWhat() -> Choice? {
        switch alert("Send this recording to CollectivIQ?",
                     "Raw: the transcript exactly as heard.\nAI version: your prompt + the transcript with words and logic fixed.\nBoth: raw first, then the AI version, in the same chat.",
                     ["AI version", "Raw", "Both"]) {
        case 0: return .ai
        case 1: return .raw
        case 2: return .both
        default: return nil
        }
    }

    private static func askWhere() -> Destination? {
        let ddr = Store.shared.prefs.ciqDDRName.trimmingCharacters(in: .whitespaces)
        if ddr.isEmpty { return .chat }
        switch alert("Where should it go?",
                     "CIQ Chat: a new CollectivIQ chat (answered by \(Store.shared.prefs.ciqModel.isEmpty ? "All · Auto" : Store.shared.prefs.ciqModel)).\nDDR: your \(ddr) DDR's chat.",
                     ["CIQ Chat", "DDR: \(ddr)"]) {
        case 0: return .chat
        case 1: return .ddr(ddr)
        default: return nil
        }
    }

    /// Opens a DDR's direct-message chat, pastes the message and presses Send.
    static func ddrScript(for msg: String, ddr: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [msg, ddr])) ?? Data("[\"\",\"\"]".utf8)
        let args = String(decoding: data, as: UTF8.self)
        return "(" + ddrSteps + ")(" + args + "[0], " + args + "[1])"
    }

    static let ddrSteps = #"""
(function(msg, ddrName){
  var S = window.__jsiddr || (window.__jsiddr = {});
  if (location.pathname.indexOf('/login') === 0) return 'login';
  function txt(e){ return (e && (e.innerText || e.textContent) || '').trim(); }
  var want = ddrName.toLowerCase().replace(/[^a-z0-9]/g, '');
  // 1. Open the DDR's direct-message chat from the sidebar (or the left rail).
  if (location.pathname.indexOf('/chat/ddr/dm') !== 0) {
    if (S.clicked && Date.now() - S.clicked < 4000) return 'wait';
    var entries = Array.prototype.slice.call(document.querySelectorAll('[data-testid=ddr-dm-entry], [data-testid=chat-rail-persona-button]'));
    if (!entries.length) return 'wait';
    var hit = entries.filter(function(e){
      var name = (txt(e.querySelector('.name')) || e.getAttribute('title') || e.getAttribute('aria-label') || txt(e)).toLowerCase().replace(/[^a-z0-9]/g, '');
      return name.indexOf(want) >= 0;
    })[0];
    if (!hit) return 'ddr:missing';
    S.clicked = Date.now(); hit.click(); return 'ddr:open';
  }
  // 2. Paste into the DDR composer and press Send.
  var ta = document.querySelector('textarea[data-testid=ddr-composer-input]');
  if (!ta || ta.disabled) return 'wait';
  var b = document.querySelector('[data-testid=ddr-send-button]');
  if (ta.value === msg && b && !b.disabled) { b.click(); S.sentAt = Date.now(); return 'sent'; }
  if (ta.value !== msg) {
    var setter = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value').set;
    ta.focus(); setter.call(ta, msg);
    ta.dispatchEvent(new Event('input', {bubbles: true}));
    ta.dispatchEvent(new Event('change', {bubbles: true}));
  }
  return 'filled';
})
"""#

    /// Picks the model (All · Auto → All Selected → only <model> → Apply Changes), then fills the
    /// chat box and presses Send. Returns "login", "wait", "model:…", "filled" or "sent".
    static func script(for msg: String) -> String {
        let model = Store.shared.prefs.ciqModel
        let data = (try? JSONSerialization.data(withJSONObject: [msg, model])) ?? Data("[\"\",\"\"]".utf8)
        let args = String(decoding: data, as: UTF8.self)
        return "(" + Self.steps + ")(" + args + "[0], " + args + "[1])"
    }

    /// Clears the per-chat progress kept in the page (call after loading a new chat).
    static let reset = "window.__jsi = undefined; window.__jsiddr = undefined; 'ok'"

    static let steps = #"""
(function(msg, model){
  var S = window.__jsi || (window.__jsi = {modelDone: !model});
  if (location.pathname.indexOf('/login') === 0) return 'login';
  function txt(e){ return (e && (e.innerText || e.textContent) || '').trim(); }
  // 1. Pick the model: All · Auto -> All Selected -> only <model> -> Apply Changes
  if (!S.modelDone) {
    var modal = document.querySelector('app-model-config-modal [role=dialog], app-model-config-modal .modal');
    if (!modal) {
      var trig = document.querySelector('[data-testid=model-config-trigger]');
      if (!trig) return 'wait';
      if (S.opened && Date.now() - S.opened < 4000) return 'wait';
      S.opened = Date.now(); trig.click(); return 'model:open';
    }
    var chips = Array.prototype.slice.call(modal.querySelectorAll('button.model-chip'));
    if (!chips.length) return 'wait';
    var want = model.toLowerCase();
    var target = chips.filter(function(c){ return txt(c.querySelector('.provider') || c).toLowerCase().indexOf(want) >= 0; })[0];
    if (!target) { S.modelDone = true; var x = modal.querySelector('.plain-btn, [aria-label="Close modal"]'); if (x) x.click(); return 'model:missing'; }
    var all = modal.querySelector('button.text-btn');
    if (!S.cleared && all && /all selected/i.test(txt(all))) { S.cleared = true; all.click(); return 'model:all-selected'; }
    S.cleared = true;
    if (!target.classList.contains('is-selected')) { target.click(); return 'model:pick'; }
    var others = chips.filter(function(c){ return c !== target && c.classList.contains('is-selected') && !c.disabled; });
    if (others.length) { others[0].click(); return 'model:trim'; }
    var apply = modal.querySelector('button.apply-btn');
    if (apply && !apply.disabled) { S.modelDone = true; apply.click(); return 'model:apply'; }
    S.modelDone = true; var c2 = modal.querySelector('.plain-btn, [aria-label="Close modal"]'); if (c2) c2.click(); return 'model:unchanged';
  }
  if (document.querySelector('app-model-config-modal [role=dialog], app-model-config-modal .modal')) return 'wait';
  // 2. Paste the prompt + transcript and press Send
  var h = document.querySelector('wa-textarea[data-testid=chat-input]');
  if (!h || !h.shadowRoot) return 'wait';
  var ta = h.shadowRoot.querySelector('textarea');
  if (!ta) return 'wait';
  var b = document.querySelector('[data-testid=send-button]');
  if (h.value === msg && b && !b.hasAttribute('disabled')) { b.click(); return 'sent'; }
  if (h.value !== msg) {
    ta.focus(); ta.value = msg;
    ta.dispatchEvent(new Event('input', {bubbles: true, composed: true}));
    try { h.value = msg; } catch (e) {}
    h.dispatchEvent(new Event('input', {bubbles: true, composed: true}));
    h.dispatchEvent(new Event('change', {bubbles: true, composed: true}));
  }
  return 'filled';
})
"""#

    static func notify(_ title: String, _ body: String) {
        let c = UNUserNotificationCenter.current()
        c.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            guard ok else { return }
            let n = UNMutableNotificationContent()
            n.title = title
            n.body = body
            n.sound = .default
            c.add(UNNotificationRequest(identifier: UUID().uuidString, content: n, trigger: nil))
        }
    }
}

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

    enum Choice: String { case raw, ai, both }

    typealias Destination = CiqRoute.Destination
    typealias Route = CiqRoute.Route
    static var chatModels: [String] { CiqRoute.chatModels }

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

    /// Called when a recording is saved: sends it right away, no questions, following the rule above.
    static func deliver(title: String?, raw: String, smart: String?, automatic: Bool = true) {
        let p = Store.shared.prefs
        guard p.ciqEnabled, !raw.isEmpty else { return }
        CIQSender.shared.sendRouted(raw: rawMessage(title: title, raw: raw),
                                    ai: message(prompt: p.ciqPrompt, title: title, transcript: smart ?? raw))
    }

    /// "Send my last note now": same rule.
    static func send(title: String?, transcript: String, force: Bool = false) {
        let p = Store.shared.prefs
        guard (p.ciqEnabled || force), !transcript.isEmpty else { return }
        CIQSender.shared.sendRouted(raw: rawMessage(title: title, raw: transcript),
                                    ai: message(prompt: p.ciqPrompt, title: title, transcript: transcript))
    }

    static func showWindow(signIn: Bool = false) {
        CIQSender.shared.show(url: signIn ? loginURL : chatURL)
    }

    /// Looks at this person's DDRs and says where the notes go. Waits until the list has loaded and
    /// stopped changing; with no DDR showing after a while, the answer is CIQ Chat.
    static func routeScript(notetaker: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [notetaker])) ?? Data("[\"\"]".utf8)
        return "(" + routeSteps + ")(" + String(decoding: data, as: UTF8.self) + "[0])"
    }

    static let routeSteps = #"""
(function(notetaker){
  var S = window.__jsiroute || (window.__jsiroute = {t: Date.now()});
  if (location.pathname.indexOf('/login') === 0) return 'login';
  function txt(e){ return (e && (e.innerText || e.textContent) || '').trim(); }
  function norm(s){ return (s || '').toLowerCase().replace(/[^a-z0-9]/g, ''); }
  if (!document.querySelector('wa-textarea[data-testid=chat-input], [data-testid=ddr-dm-entry], [data-testid=chat-rail-persona-button]')) return 'wait';
  var names = Array.prototype.slice.call(document.querySelectorAll('[data-testid=ddr-dm-entry], [data-testid=chat-rail-persona-button]'))
    .map(function(e){ return (txt(e.querySelector('.name')) || e.getAttribute('title') || e.getAttribute('aria-label') || txt(e)).split(/[\r\n]/)[0].trim(); })
    .filter(function(n){ return n.length > 0; });
  var key = names.join('|');
  if (key !== S.key) { S.key = key; S.since = Date.now(); }
  // Give the list time to load fully (DDRs can appear one by one).
  if (Date.now() - S.t < 3000 || Date.now() - S.since < 2000) return 'wait';
  if (!names.length) return Date.now() - S.t > 9000 ? 'route:none' : 'wait';
  var want = norm(notetaker);
  if (want) {
    var nt = names.filter(function(n){ return norm(n).indexOf(want) >= 0; })[0];
    if (nt) return 'route:notetaker:' + nt;
  }
  var other = names.filter(function(n){ return !want || norm(n).indexOf(want) < 0; })[0];
  return other ? 'route:assistant:' + other : 'route:none';
})
"""#

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
    static func script(for msg: String, models: [String] = CiqRoute.chatModels) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [msg, models] as [Any])) ?? Data("[\"\",[]]".utf8)
        let args = String(decoding: data, as: UTF8.self)
        return "(" + Self.steps + ")(" + args + "[0], " + args + "[1])"
    }

    /// Clears the per-chat progress kept in the page (call after loading a new chat).
    static let reset = "window.__jsi = undefined; window.__jsiddr = undefined; window.__jsiroute = undefined; 'ok'"

    static let steps = #"""
(function(msg, models){
  var S = window.__jsi || (window.__jsi = {modelDone: !models || !models.length});
  if (location.pathname.indexOf('/login') === 0) return 'login';
  function txt(e){ return (e && (e.innerText || e.textContent) || '').trim(); }
  // 1. Pick the models: All · Auto -> All Selected -> only the wanted models -> Apply Changes
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
    var targets = [];
    models.forEach(function(m){
      var w = m.toLowerCase();
      var c = chips.filter(function(c){ return targets.indexOf(c) < 0 && txt(c.querySelector('.provider') || c).toLowerCase().indexOf(w) >= 0; })[0];
      if (c) targets.push(c);
    });
    if (!targets.length) { S.modelDone = true; var x = modal.querySelector('.plain-btn, [aria-label="Close modal"]'); if (x) x.click(); return 'model:missing'; }
    var all = modal.querySelector('button.text-btn');
    if (!S.cleared && all && /all selected/i.test(txt(all))) { S.cleared = true; all.click(); return 'model:all-selected'; }
    S.cleared = true;
    var pick = targets.filter(function(c){ return !c.classList.contains('is-selected'); })[0];
    if (pick) { pick.click(); return 'model:pick'; }
    var others = chips.filter(function(c){ return targets.indexOf(c) < 0 && c.classList.contains('is-selected') && !c.disabled; });
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

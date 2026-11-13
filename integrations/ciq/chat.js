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

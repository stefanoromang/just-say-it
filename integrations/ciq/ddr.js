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

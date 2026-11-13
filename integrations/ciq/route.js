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

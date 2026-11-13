let enabled = false;
let session = crypto.randomUUID();
let segments = new WeakMap();
let sequence = 0;
let status = 'Capture is off. Enable captions in the meeting, then start capture here.';
const service = location.hostname === 'meet.google.com' ? 'meet' : 'teams';

chrome.runtime.onMessage.addListener((m, _, reply) => {
  if (m.type === 'status') reply({ enabled, status });
  if (m.type === 'toggle') {
    enabled = !enabled;
    if (enabled) { session = crypto.randomUUID(); segments = new WeakMap(); sequence = 0; }
    status = enabled ? 'Waiting for visible captions and a recording in Just Say It…' : 'Capture is off.';
    reply({ enabled, status });
  }
});

let sending = false;
setInterval(async () => {
  if (!enabled || sending) return;
  sending = true;
  try {
    const rows = JSICaptions.extract(document, service);
    if (!rows.length) { status = 'No readable captions. Open the captions/transcript panel in the meeting.'; return; }
    for (const row of rows.slice(-50)) {
      let segment = segments.get(row.element);
      // shortcut: a reused caption element starts a new utterance after a pause; platform cue IDs should replace this if their DOM exposes them reliably.
      if (!segment || segment.speaker !== row.speaker || (Date.now() - segment.changed > 4000 && !row.text.startsWith(segment.text) && !segment.text.startsWith(row.text))) {
        segment = { id: String(++sequence), speaker: row.speaker, text: '', changed: Date.now() };
        segments.set(row.element, segment);
      }
      if (segment.text === row.text) continue;
      const response = await chrome.runtime.sendMessage({
        type: 'caption', service, session, segment: segment.id, speaker: row.speaker,
        text: row.text, url: location.href, title: document.title
      });
      status = response?.status || 'App connection unavailable.';
      if (response?.ok) { segment.text = row.text; segment.changed = Date.now(); }
    }
  } catch { status = 'App connection unavailable. Install the caption connector from Just Say It.'; }
  finally { sending = false; }
}, 1000);

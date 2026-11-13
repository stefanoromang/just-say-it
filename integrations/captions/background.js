chrome.runtime.onMessage.addListener((message, sender, reply) => {
  if (message.type !== 'caption') return;
  // Never trust the URL supplied in page data: verify the sender supplied by the browser.
  const url = new URL(sender.url || 'https://invalid/');
  const allowed = ['meet.google.com', 'teams.microsoft.com', 'teams.live.com', 'teams.cloud.microsoft'];
  if (url.protocol !== 'https:' || !allowed.includes(url.hostname) || sender.frameId !== 0) {
    reply({ ok: false, status: 'Unsupported meeting page.' }); return;
  }
  chrome.runtime.sendNativeMessage('com.stefano.justsayit.captions', { ...message, url: url.href }, result => {
    reply(chrome.runtime.lastError ? { ok: false, status: 'Install the caption connector from Just Say It first.' } : result);
  });
  return true;
});

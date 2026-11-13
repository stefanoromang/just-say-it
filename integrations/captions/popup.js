const status = document.getElementById('status'), button = document.getElementById('toggle');
async function update(type) {
  try {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    const r = await chrome.tabs.sendMessage(tab.id, { type });
    status.textContent = r.status;
    button.textContent = r.enabled ? 'Stop capture' : 'Start capture';
  } catch { status.textContent = 'Open a Teams web or Google Meet meeting first.'; button.disabled = true; }
}
button.onclick = () => update('toggle');
update('status');

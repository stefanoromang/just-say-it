const assert = require('node:assert/strict');
const { extract } = require('./extract.js');
function row(speaker, text) {
  const s = { textContent: speaker, getAttribute: () => null }, t = { textContent: text, getAttribute: () => null };
  return { querySelector: selector => selector.includes('speaker') || selector.includes('author') ? s : t, contains: () => false };
}
const teams = row('Laura Bianchi', 'The budget is 48,000 euros.');
const doc = { querySelectorAll: selector => selector === '[data-tid="closed-caption-item"]' ? [teams] : [] };
assert.equal(extract(doc, 'teams')[0].speaker, 'Laura Bianchi');
assert.equal(extract(doc, 'teams')[0].text, 'The budget is 48,000 euros.');
const missing = row('', 'A chat message must not be captured');
assert.equal(extract({ querySelectorAll: () => [missing] }, 'teams').length, 0);
assert.equal(extract({ querySelectorAll: () => [] }, 'meet').length, 0);
console.log('Caption extraction fixtures passed (synthetic DOM; not live Teams/Meet).');

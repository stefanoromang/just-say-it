/* Only read known caption/transcript containers, never arbitrary chat messages. */
(function (root) {
  function extract(doc, service) {
    const selectors = service === 'teams'
      ? ['[data-tid="closed-caption-item"]', '[data-tid="transcript-item"]', '[data-tid="closed-caption-container"]']
      : ['.a4cQT', '[data-caption-id]', '[jsname="tgaKEf"]'];
    const rows = [...new Set(selectors.flatMap(s => [...doc.querySelectorAll(s)]))];
    return rows.filter(r => !rows.some(other => other !== r && r.contains(other))).flatMap(row => {
      const speaker = row.querySelector('[data-tid="author"], [data-tid="speaker-name"], [data-tid="closed-caption-speaker-name"], .zs7s8d, .NWpY1d, [data-speaker-name]');
      const text = row.querySelector('[data-tid="caption-text"], [data-tid="transcript-text"], [data-tid="closed-caption-text"], .iTTPOb, .ygicle, [data-caption-text]');
      const name = (speaker?.textContent || speaker?.getAttribute('data-speaker-name') || '').trim();
      const words = (text?.textContent || '').trim();
      // Missing speaker/text is a compatibility failure, not permission to scrape the whole page.
      return name && words && name.length <= 200 && words.length <= 12000 ? [{ element: row, speaker: name, text: words }] : [];
    });
  }
  root.JSICaptions = { extract };
  if (typeof module !== 'undefined') module.exports = { extract };
})(globalThis);

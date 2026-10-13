// Pullglance diagnostic — paste in Chrome DevTools on a GitHub pull request "Files changed" page.
// Reports structure only (selectors, counts, positions); no file names, no titles, no URLs.
// Output goes to the console and to the clipboard (copy(...)) when available.
(async () => {
  const out = {};
  const q = (s, r = document) => Array.from(r.querySelectorAll(s));
  const sel = (el) => {
    if (!el) return null;
    const id = el.id ? `#${el.id.replace(/[0-9a-f]{20,}/g, '…')}` : '';
    const cls = Array.from(el.classList).slice(0, 3).map((c) => '.' + c.replace(/__[A-Za-z0-9]+$/, '')).join('');
    const attrs = Array.from(el.attributes).filter((a) => /^(data-|role$|aria-label$)/.test(a.name)).slice(0, 4)
      .map((a) => `[${a.name}${a.name === 'role' ? '=' + a.value : ''}]`).join('');
    return `${el.tagName.toLowerCase()}${id}${cls}${attrs}`;
  };
  const chain = (el, n = 5) => { const c = []; while (el && n--) { c.push(sel(el)); el = el.parentElement; } return c; };

  // 1. Where do #diff- links live? (headers vs tree vs others)
  const links = q('a[href^="#diff-"]');
  const groups = {};
  for (const a of links) {
    const kind = a.closest('h3') ? 'h3-header' : a.closest('[role="tree"],[role="treeitem"],nav,[data-testid*="tree" i]') ? 'tree' : 'other';
    groups[kind] = (groups[kind] || 0) + 1;
  }
  out.diffLinks = { total: links.length, byKind: groups, sampleTreeChain: chain(links.find((a) => !a.closest('h3'))) };

  // 2. Rendered headers: how many, sticky?, where
  const wrappers = q('[data-diff-header-wrapper="true"], [class*="Diff-module__diffHeaderWrapper"]');
  out.headers = {
    rendered: wrappers.length,
    positions: wrappers.slice(0, 40).map((w) => ({ top: Math.round(w.getBoundingClientRect().top), sticky: getComputedStyle(w).position })),
    sampleChain: chain(wrappers[0]),
  };

  // 3. What scrolls? window or an inner pane
  const scrollers = q('*').filter((el) => { const s = getComputedStyle(el); return /(auto|scroll)/.test(s.overflowY) && el.scrollHeight > el.clientHeight + 200; })
    .map((el) => ({ el: sel(el), scrollTop: el.scrollTop, scrollHeight: el.scrollHeight, clientHeight: el.clientHeight }));
  out.scroll = { windowScrollY: Math.round(scrollY), documentHeight: document.documentElement.scrollHeight, innerScrollers: scrollers.slice(0, 6) };

  // 4. Virtualization: total files vs rendered headers, and the file tree's state
  const tree = document.querySelector('[role="tree"]');
  out.tree = tree ? { chain: chain(tree, 4), items: q('[role="treeitem"]', tree).length, visible: tree.getBoundingClientRect().width > 0 } : null;
  const embedded = q('script[type="application/json"]').map((s) => s.textContent || '').find((t) => /"diffEntries"|"diffs"|viewerViewedState/.test(t));
  out.embeddedJSON = embedded ? { bytes: embedded.length, hasViewerViewedState: /viewerViewedState/.test(embedded), filesGuess: (embedded.match(/"path":/g) || []).length } : null;

  // 5. Experiment: does clicking a tree link far from the viewport scroll the page? (restores scroll after)
  const far = links.filter((a) => !a.closest('h3')).find((a) => { const h = a.getAttribute('href'); return !document.getElementById(h.slice(1)) && !document.querySelector(`h3 a[href="${h}"]`); });
  if (far) {
    const before = { y: scrollY, inner: scrollers.map((s) => s.scrollTop) };
    far.click();
    await new Promise((r) => setTimeout(r, 1200));
    const after = { y: scrollY, inner: q('*').filter((el) => /(auto|scroll)/.test(getComputedStyle(el).overflowY) && el.scrollHeight > el.clientHeight + 200).map((el) => el.scrollTop) };
    out.treeClickExperiment = { before, after, hashAfter: location.hash.replace(/[0-9a-f]{20,}/g, '…'), headersRenderedAfter: q('[data-diff-header-wrapper="true"], [class*="Diff-module__diffHeaderWrapper"]').length };
    history.replaceState(null, '', location.pathname + location.search);
    window.scrollTo(0, before.y);
  } else {
    out.treeClickExperiment = 'no unrendered tree link found';
  }

  // 6. Hash experiment: does a hash change scroll?
  const target = links.map((a) => a.getAttribute('href')).find((h) => !document.querySelector(`h3 a[href="${h}"]`));
  if (target) {
    const y0 = scrollY;
    location.hash = target;
    await new Promise((r) => setTimeout(r, 1200));
    out.hashExperiment = { scrolled: Math.abs(scrollY - y0) > 50, headersRenderedAfter: q('[data-diff-header-wrapper="true"], [class*="Diff-module__diffHeaderWrapper"]').length };
    history.replaceState(null, '', location.pathname + location.search);
    window.scrollTo(0, y0);
  }

  const text = JSON.stringify(out, null, 1);
  console.log(text);
  try { copy(text); console.log('%c(copied to clipboard)', 'color: green'); } catch {}
})();

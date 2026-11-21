// The layout pane (plan 00 step 4): the kind of right-click, and the layout's cards as a tree of lines (read only;
// editing comes with step 5). The app sends { type: "state", kind, kinds, layout, source, error }; a kind chosen here
// goes back as { type: "kind", kind }.
"use strict";

const kindSelect = document.getElementById("kind");
const source = document.getElementById("source");
const errorBox = document.getElementById("error");
const cardsBox = document.getElementById("cards");

const kindNames = { file: "a file", folder: "a folder", several: "several items", background: "a folder's empty part",
  drive: "a drive", default: "anything else" };

// JSON with // comments (docs/plans/02-PLAN-own-menu.md 3.5): a comment ends the line, except inside a string.
function withoutComments(text) {
  let out = "", inString = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (inString) {
      out += c;
      if (c === "\\" && i + 1 < text.length) out += text[++i];
      else if (c === '"') inString = false;
    } else if (c === '"') { inString = true; out += c; }
    else if (c === "/" && text[i + 1] === "/") { while (i < text.length && text[i] !== "\n") i++; out += "\n"; }
    else out += c;
  }
  return out;
}

function el(tag, cls, text) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text !== undefined) e.textContent = text;
  return e;
}

function renderLines(lines) {
  const box = el("div", "lines");
  for (const entry of lines || []) {
    if (!entry.line) continue;
    const row = el("div", "line");
    for (const card of entry.line) row.append(renderCard(card));
    box.append(row);
  }
  return box;
}

function renderCard(card) {
  const rules = card.rules || [];
  const remaining = rules.includes("remaining");
  const box = el("div", "card" + (remaining ? " remaining" : ""));
  box.append(el("div", "title", card.card));
  let what;
  if (card.menu) what = "a card with a menu";
  else if (remaining) what = "the remaining card: every item no other card took, each a card of its own here";
  else what = rules.length + (rules.length === 1 ? " rule" : " rules");
  box.append(el("div", "what", what));
  if (card.menu) box.append(renderLines(card.menu));
  return box;
}

function show(state) {
  kindSelect.replaceChildren(...state.kinds.map(k => {
    const o = el("option", "", kindNames[k] || k);
    o.value = k;
    o.selected = k === state.kind;
    return o;
  }));
  source.textContent = state.source;
  errorBox.hidden = !state.error;
  errorBox.textContent = state.error || "";
  let layout;
  try { layout = JSON.parse(withoutComments(state.layout)); }
  catch (e) { cardsBox.replaceChildren(el("div", "what", "The layout is not valid JSON: " + e.message)); return; }
  cardsBox.replaceChildren(renderLines(layout[state.kind] || layout["default"]));
}

kindSelect.addEventListener("change", () => chrome.webview.postMessage({ type: "kind", kind: kindSelect.value }));
chrome.webview.addEventListener("message", e => { if (e.data.type === "state") show(e.data); });

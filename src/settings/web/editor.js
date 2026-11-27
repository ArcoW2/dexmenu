// The layout editor (docs/plans/executed/02-PLAN-own-menu.md 3.3, 3.5; plan 00 step 5). Two views of one layout: the cards
// (a tree of lines and submenus, dragged around; a card selected shows its name, title, extra text and rules) and the
// rules in priority order (dragged to change it). Every change goes to the app at once ({ type: "edit", layout }),
// which has the DLL draw the preview from it; saving writes the file. The app sends:
//   { type: "state", kind, layout, source, name, theme, error }      the layout (re)loaded
//   { type: "preview", error }                                                      the preview of an edit
//   { type: "placed", event, cardId, rule }      the preview: an item hovered (1) or clicked (2): who placed it
// and gets { type: "edit" | "save" | "saveAs" | "close" | "mark" | "theme", ... } back.
"use strict";

const M = LayoutModel;
const $ = id => document.getElementById(id);
const post = message => chrome.webview.postMessage(message);

const kindNames = { file: "a file", folder: "a folder", several: "several items", background: "a folder's empty part",
  drive: "a drive", default: "anything else" };
const placeNames = { top: "at the top level", anywhere: "anywhere", path: "in the submenu" };

let layout = null;       // the layout being edited (parsed, with ids and priorities)
let kind = "default";
let selectedId = null;
let selectedRule = -1;   // index on the selected card
let hoverId = null;
const collapsed = new Set();   // cards with a menu shown folded (this session only)
let generalStates = "both";   // what a rule without states of its own takes (the main window's General)
let palette = {};  // the theme's palette, { name: "#rrggbbaa" } (the app, DexmenuThemePalette): the colour pickers
let counts = {};   // the stored use counts per card id of what the preview shows (the app, DexmenuPreviewCounts)
let dirty = false;
let lastSent = "";
let loadedText = "";

// A small card, the icon of the buttons that add one (drawn here: a symbol font such as Wingdings is not sure to be
// there).
function cardIcon() {
  const ns = "http://www.w3.org/2000/svg";
  const svg = document.createElementNS(ns, "svg");
  svg.setAttribute("viewBox", "0 0 14 10");
  svg.setAttribute("class", "card-icon");
  svg.setAttribute("aria-hidden", "true");
  const add = (tag, attrs) => { const e = document.createElementNS(ns, tag); for (const [k, v] of Object.entries(attrs)) e.setAttribute(k, v); svg.append(e); };
  add("rect", { x: "0.75", y: "0.75", width: "12.5", height: "8.5", rx: "2", fill: "none", stroke: "currentColor", "stroke-width": "1.5" });
  add("line", { x1: "3.5", y1: "4", x2: "10.5", y2: "4", stroke: "currentColor", "stroke-width": "1.3" });
  add("line", { x1: "3.5", y1: "6.5", x2: "8", y2: "6.5", stroke: "currentColor", "stroke-width": "1.3" });
  return svg;
}
// A note's icon: a sheet with lines of text, no button's frame.
function noteIcon() {
  const ns = "http://www.w3.org/2000/svg";
  const svg = document.createElementNS(ns, "svg");
  svg.setAttribute("viewBox", "0 0 14 10");
  svg.setAttribute("class", "card-icon");
  svg.setAttribute("aria-hidden", "true");
  for (const [y, x2] of [[2, 13], [5, 13], [8, 9]]) {
    const l = document.createElementNS(ns, "line");
    for (const [k, v] of Object.entries({ x1: 1, y1: y, x2, y2: y, stroke: "currentColor", "stroke-width": "1.4" })) l.setAttribute(k, v);
    svg.append(l);
  }
  return svg;
}

// A divider's icon: a line with a short text in it.
function dividerIcon() {
  const ns = "http://www.w3.org/2000/svg";
  const svg = document.createElementNS(ns, "svg");
  svg.setAttribute("viewBox", "0 0 14 10");
  svg.setAttribute("class", "card-icon");
  svg.setAttribute("aria-hidden", "true");
  for (const [x1, x2] of [[0.5, 3.5], [10.5, 13.5]]) {
    const l = document.createElementNS(ns, "line");
    for (const [k, v] of Object.entries({ x1, y1: 5, x2, y2: 5, stroke: "currentColor", "stroke-width": "1.5" })) l.setAttribute(k, v);
    svg.append(l);
  }
  const t = document.createElementNS(ns, "line");
  for (const [k, v] of Object.entries({ x1: 5, y1: 5, x2: 9, y2: 5, stroke: "currentColor", "stroke-width": "3", "stroke-linecap": "round" })) t.setAttribute(k, v);
  svg.append(t);
  return svg;
}
const withIcon = (button, label) => { button.replaceChildren(cardIcon(), document.createTextNode(" " + label)); return button; };

function el(tag, cls, text) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text !== undefined) e.textContent = text;
  return e;
}

// The lines of the kind being edited: its own, or the default's.
// The menu being edited: a layout is one menu (plan 05 3.1), whatever kind of right-click the preview shows.
function linesOf() { return M.rootOf(layout); }

function changed() {
  dirty = true;
  $("dirty").hidden = false;
  const text = JSON.stringify(layout, null, 2);
  if (text !== lastSent) { lastSent = text; post({ type: "edit", layout: text }); }
  remember(text);
  render();
}

// ---- undo and redo: every change kept (the layout as text), this window's session -----------------------------------

let history = [];   // the layout after each change, the last the current one
let future = [];    // what Undo took back, for Redo
const historySize = 200;

function remember(text) {
  if (history[history.length - 1] === text) return;
  history.push(text);
  if (history.length > historySize) history.shift();
  future = [];
}

// The layout as it was (Undo) or again (Redo): drawn, sent to the preview, not saved until Save.
function restore(text) {
  layout = JSON.parse(text);
  lastSent = text;
  dirty = true;
  $("dirty").hidden = false;
  post({ type: "edit", layout: text });
  if (selectedId && !M.find(linesOf(), selectedId.replace(/~t\d+$/, ""))) selectedId = null;
  render();
}

function undo() {
  if (!layout || history.length < 2) return;
  future.push(history.pop());
  restore(history[history.length - 1]);
}

function redo() {
  if (!layout || !future.length) return;
  const text = future.pop();
  history.push(text);
  restore(text);
}

// ---- the cards view --------------------------------------------------------------------------------------------

function ruleBadges(card) {
  return (card.rules || []).filter(r => r !== "remaining").map(r => el("span", "badge", "#" + r.priority));
}

function describeCard(card) {
  if (M.isNote(card)) return "a note: shown as text, no button";
  if (M.isOwn(card)) return "Dexmenu's own item: " + (card.own === "windowsMenu" ? "shows Windows' menu" : "opens this editor");
  if (card.hidden && !M.isRemaining(card)) return "hidden: what it finds is left out of the menu";
  if (M.isHolder(card)) {
    const n = card.content.filter(e => !M.isDividerEntry(e)).length;
    const how = card.show === "row" ? "side by side" : card.show === "column" ? "under each other" : "in a submenu";
    return "holds " + n + (n === 1 ? " card" : " cards") + ", " + how;
  }
  if (M.isRemaining(card)) return "the remaining card: every item no rule took, each a card of its own here";
  const n = (card.rules || []).length;
  if (n === 0) return "no rules: finds nothing";
  return n + (n === 1 ? " rule" : " rules") + (M.useless(card) ? ", one of them invalid" : "");
}

function dropZone(cls, onDrop) {
  const z = el("div", cls);
  // stopPropagation: a zone inside a card's menu, else the card around it also takes the drop (dropped twice)
  z.addEventListener("dragover", e => { e.preventDefault(); e.stopPropagation(); z.classList.add("over"); });
  z.addEventListener("dragleave", e => { e.stopPropagation(); z.classList.remove("over"); });
  z.addEventListener("drop", e => {
    e.preventDefault();
    e.stopPropagation();
    z.classList.remove("over");
    withDragged(e, onDrop);
  });
  return z;
}

// What is being dropped: a card or a divider of the layout, or a new one ("+ Card" or "+ Divider" dragged: made now, at
// the end, then moved by the drop like any; taken out again when the drop cannot place it). place(id, isDivider)
// moves it and says whether it did.
function withDragged(e, place) {
  const isDivider = e.dataTransfer.types.includes("text/divider");
  let id = e.dataTransfer.getData(isDivider ? "text/divider" : "text/card");
  if (!id) return;
  const isNew = id === "new" || id === "newnote" || id === "newgroup";   // "+ Card", "+ Divider", "+ Note", "+ Group"
  if (id === "newnote") id = M.addNote(layout, linesOf()).id;
  else if (id === "newgroup") id = M.addGroup(layout, linesOf()).id;
  else if (isNew) id = isDivider ? M.addDivider(layout, linesOf(), null).id : M.addCard(layout, linesOf(), null).id;
  if (place(id, isDivider)) {
    if (isNew) select(id, -1);
    changed();
    if (isNew) focusNew(id);
  } else if (isNew) isDivider ? M.deleteDivider(linesOf(), id) : M.deleteCard(linesOf(), id);
}

// A divider in the cards view: its text (or a plain line) where it will show; dragged, selected, deleted on hover.
function renderDivider(entry) {
  const box = el("div", "divider" + (entry.id === selectedId ? " selected" : "") + " align-" + (entry.align || "left"));
  box.draggable = true;
  box.dataset.id = entry.id;
  if (entry.search) {
    box.classList.add("mostused");
    box.append(el("span", "text", "Search box: what is typed searches every item"));
  } else {
    box.append(el("span", "rule-line"), el("span", "text", entry.divider || ""), el("span", "rule-line"));
    if (!entry.divider) box.classList.add("plain");
  }
  const actions = el("div", "card-actions");
  const x = el("button", "", "x");
  x.title = entry.search ? "Delete the search box" : "Delete this divider";
  x.addEventListener("click", e => { e.stopPropagation(); if (M.deleteDivider(linesOf(), entry.id)) { if (selectedId === entry.id) selectedId = null; changed(); } });
  actions.append(x);
  box.append(actions);
  box.addEventListener("click", e => { e.stopPropagation(); select(entry.id, -1); });
  box.addEventListener("mouseover", e => {
    e.stopPropagation();
    for (const h of document.querySelectorAll(".hot")) if (h !== box) h.classList.remove("hot");
    box.classList.add("hot");
  });
  box.addEventListener("mouseleave", () => box.classList.remove("hot"));
  box.addEventListener("dragstart", e => { e.stopPropagation(); e.dataTransfer.setData("text/divider", entry.id); });
  return box;
}

// A card just added gets the focus: selected, scrolled into view, its name ready to be typed over. After the frame, as
// the renders of the change come first and each makes the panel's fields anew.
function focusNew(id) {
  requestAnimationFrame(() => {
    document.querySelector(`#cards [data-id="${id}"]`)?.scrollIntoView({ block: "nearest" });
    const name = $("card").querySelector("input[type=text]");
    if (name) { name.focus(); name.select(); }
  });
}
function addAndFocus(card) { select(card.id, -1); changed(); focusNew(card.id); }
// A card, note, group or divider added by a click on its button above the cards: put after the selected card (inside
// the group it is in), then selected itself, so the next one follows it.
function addAfterSelected(card) { M.putAfter(linesOf(), card.id, selectedId); addAndFocus(card); }

// The menu as a card (plan 11 3.9): the fixed outer card holding every other; selected by its heading to set how its
// cards show (under each other, side by side, in columns), its submenus' default and its style. Not moved, copied or
// deleted.
function renderMenuCard() {
  const frame = el("div", "menu-frame" + (selectedId === "menu" ? " selected" : ""));
  const head = el("div", "menu-frame-head");
  const root = layout.menu;
  const how = root.show === "row" ? "side by side" : root.perColumn ? root.perColumn + " per column" : "under each other";
  head.append(el("span", "name", "Menu"), el("span", "what", " the layout's menu: its cards " + how + (root.submenus ? ", submenus " + root.submenus : "")));
  head.title = "The menu itself: how its cards show, its submenus' default and its style";
  head.addEventListener("click", e => { e.stopPropagation(); select("menu", -1); });
  frame.append(head, renderLines(linesOf(), null));
  return frame;
}

// A container (the menu's content, or a card's holding them under each other): each card on a line of its own, a
// drop gap before each and at the end. A plain row (what a line was) is drawn as that line, its cards side by side.
function renderLines(lines, parentId) {
  const box = el("div", "lines");
  lines.forEach((entry, index) => {
    box.append(dropZone("gap", (id, isDiv) => isDiv ? M.moveDivider(linesOf(), id, parentId, index) : M.moveCard(linesOf(), id, parentId, index)));
    if (M.isDividerEntry(entry)) {
      const d = renderDivider(entry);
      if (!parentId) d.dataset.top = index;   // a top-level place, for a card pasted in the gutter
      box.append(d);
      return;
    }
    const row = M.isPlainRow(entry) ? renderRow(entry) : el("div", "line");
    if (!M.isPlainRow(entry)) row.append(renderCard(entry));
    if (!parentId) row.dataset.top = index;
    box.append(row);
  });
  box.append(dropZone("gap", (id, isDiv) => isDiv ? M.moveDivider(linesOf(), id, parentId, lines.length)
    : M.moveCard(linesOf(), id, parentId, lines.length)));
  return box;
}

// A row's cards side by side (its content), a drop place at its end; a plain row (no style of its own) is the line
// itself, selected as a card (a click in the gutter beside it, plan 11 3.5).
function renderRow(holder) {
  const row = el("div", "line" + (M.isPlainRow(holder) ? " row-holder" : "") + (holder.id === selectedId ? " selected" : ""));
  row.dataset.holder = holder.id;
  for (const entry of holder.content) row.append(M.isDividerEntry(entry) ? renderDivider(entry) : renderCard(entry));
  row.append(dropZone("line-end", (id, isDiv) => isDiv ? M.moveDividerNext(linesOf(), id, holder.id, "below")
    : M.moveCard(linesOf(), id, holder.id, holder.content.length)));
  return row;
}

// A card whose found items become inner cards (in a row, a column or a submenu: plan 11 3.1), which follow templates.
function usesTemplates(card) {
  return !M.isHolder(card) && !M.isNote(card) && !M.isRemaining(card) && ["row", "column", "submenu"].includes(card.show);
}

// Its templates as dashed cards inside it ("Template 1", ...), selected and edited as a card; "+ Template" adds one,
// "x" on one removes it. Selected by "<card id>~t<n>".
function renderTemplates(card) {
  const box = el("div", "templates");
  (card.templates || []).forEach((t, i) => {
    const id = card.id + "~t" + i;
    const chip = el("div", "template-card" + (selectedId === id ? " selected" : ""), "Template " + (i + 1));
    chip.title = "What its inner cards follow" + ((card.templates.length > 1) ? (card.templatesBy === "rule" ? " (the rules that name it)" : " (in turn)") : "");
    const x = el("button", "", "x");
    x.title = "Remove this template";
    x.addEventListener("click", e => {
      e.stopPropagation();
      card.templates.splice(i, 1);
      if (!card.templates.length) delete card.templates;
      if (selectedId === id) selectedId = card.id;
      changed();
    });
    chip.append(x);
    chip.addEventListener("click", e => { e.stopPropagation(); select(id, -1); });
    // its own right-click menu (not its card's): its style copied, or a copied style pasted onto it
    chip.addEventListener("contextmenu", async e => {
      e.preventDefault();
      e.stopPropagation();
      select(id, -1);
      const x = e.clientX, y = e.clientY;
      const type = await clipboardType();
      showContextMenu(x, y, [
        ["Copy style", "This template's background, text colour, border, radius, hover look, height, square, wrap and fit (Ctrl+Shift+C)", copyStyle],
        ["Paste style", "The copied style onto this template: what the style does not set, the theme's again (Ctrl+Shift+V)", () => pasteStyle(), type !== "style"],
        null,
        ["Copy template", "This template (its texts, layout and style), to paste onto another card, also in another layout (Ctrl+C)", copyTemplate]]);
    });
    box.append(chip);
  });
  const add = el("button", "", "+ Template");
  add.title = "A template its inner cards follow: their texts, layout and style";
  add.addEventListener("click", e => {
    e.stopPropagation();
    card.templates = card.templates || [];
    card.templates.push({});
    select(card.id + "~t" + (card.templates.length - 1), -1);
    changed();
  });
  box.append(add);
  return box;
}

function renderCard(card) {
  const classes = ["card"];
  if (card.id === selectedId) classes.push("selected");
  if (card.id === hoverId) classes.push("hover");
  if (M.useless(card)) classes.push("useless");
  if (M.isRemaining(card)) classes.push("remaining");
  if (card.hidden && !M.isRemaining(card)) classes.push("hidden");
  const box = el("div", classes.join(" "));
  box.draggable = true;
  box.dataset.id = card.id;
  // a card with a menu folds; its toggle is in the pane's gutter (placeToggles)
  const folded = M.isHolder(card) && collapsed.has(card.id);
  if (M.isHolder(card)) box.dataset.fold = folded ? "folded" : "open";
  const title = el("div", "title");
  // its own element, so a long name wraps inside the card; a note shows its text (its first lines)
  title.append(M.isNote(card) ? el("span", "name note-text align-" + (card.align || "left"), card.note || "(empty)")
    : el("span", "name", card.card));
  title.append(...ruleBadges(card));
  const cardsIn = M.isHolder(card) ? [...M.cards(card.content)].length : 0;
  box.append(cardActions(card), title,
    el("div", "what", describeCard(card) + (folded ? ", " + cardsIn + (cardsIn === 1 ? " card" : " cards") + " folded" : "")));
  if (usesTemplates(card)) box.append(renderTemplates(card));
  if (M.isHolder(card) && !folded) box.append(card.show === "row" ? renderRow(card) : renderLines(card.content, card.id));
  box.addEventListener("click", e => { e.stopPropagation(); select(card.id, -1); });
  // its right-click menu: the card copied, a copied card pasted inside it (when it can hold one), its style copied, or
  // a copied style pasted onto it (the remaining card: no copy, no style)
  box.addEventListener("contextmenu", async e => {
    e.preventDefault();
    e.stopPropagation();
    select(card.id, -1);
    const x = e.clientX, y = e.clientY;
    const type = await clipboardType();
    const remaining = M.isRemaining(card);
    showContextMenu(x, y, [
      ["Copy card", "A duplicate of it (with its menu and rules) can be pasted elsewhere, also in another layout (Ctrl+C)", copyCard, remaining],
      ["Paste card inside", M.isHolder(card) ? "The copied card added to what this card holds" : "This card becomes a card with a submenu: its rules in the first card, the copied card after it",
        () => pasteCardAt({ into: card.id }), type !== "card" || !M.canHold(card)],
      null,
      ["Copy style", "Its background, text colour, border, radius, hover look, height, wrap, fit in line, extra text at and submenus open (Ctrl+Shift+C)", copyStyle, remaining],
      ["Paste style", "The copied style onto this card: what the style does not set, the theme's again (Ctrl+Shift+V)", () => pasteStyle(), type !== "style" || remaining],
      ["Paste template", "The copied template added to this card's templates (what the items it shows inside it follow)", () => pasteTemplate(card),
        type !== "template" || !M.canTakeTemplate(card)]]);
  });
  // a double click on a card with a menu (its own space, not a card in it or a button) folds or unfolds it
  box.addEventListener("dblclick", e => {
    e.stopPropagation();
    if (!M.isHolder(card) || e.target.closest("button")) return;
    collapsed.has(card.id) ? collapsed.delete(card.id) : collapsed.add(card.id);
    render();
  });
  // its actions show for the innermost card under the mouse only (CSS :hover would show the outer cards' too)
  box.addEventListener("mouseover", e => {
    e.stopPropagation();
    for (const h of document.querySelectorAll(".card.hot")) if (h !== box) h.classList.remove("hot");
    box.classList.add("hot");
  });
  box.addEventListener("mouseleave", () => box.classList.remove("hot"));
  box.addEventListener("dragstart", e => { e.stopPropagation(); e.dataTransfer.setData("text/card", card.id); });
  const zones = ["over", "over-before", "over-after", "over-above", "over-below"];
  box.addEventListener("dragover", e => {
    e.preventDefault();
    e.stopPropagation();
    box.classList.remove(...zones);
    if (e.dataTransfer.types.includes("text/ruleref")) {   // a rule: onto the card, moved or (Shift) copied
      e.dataTransfer.dropEffect = e.shiftKey ? "copy" : "move";
      if (!M.isHolder(card) && !M.isRemaining(card) && !M.isNote(card) && !M.isOwn(card)) box.classList.add("over");
      return;
    }
    box.classList.add(zoneClass(dropZoneOf(box, e, e.dataTransfer.types.includes("text/divider"))));
  });
  box.addEventListener("dragleave", e => { e.stopPropagation(); box.classList.remove(...zones); });
  box.addEventListener("drop", e => {
    e.preventDefault();
    e.stopPropagation();
    box.classList.remove(...zones);
    if (e.dataTransfer.types.includes("text/ruleref")) {
      const ref = JSON.parse(e.dataTransfer.getData("text/ruleref"));
      const from = M.find(linesOf(), ref.cardId);
      const placed = from && M.moveRuleToCard(linesOf(), from.card, ref.index, card, e.shiftKey);
      if (placed) { selectedId = card.id; selectedRule = card.rules.indexOf(placed); post({ type: "mark", cardId: card.id }); changed(); }
      return;
    }
    // a selected line dropped onto one of its own cards: nothing
    const zone = dropZoneOf(box, e, e.dataTransfer.types.includes("text/divider"));
    withDragged(e, (id, isDiv) => isDiv ? M.moveDividerNext(linesOf(), id, card.id, zone)
      : zone === "onto" ? M.dropOnCard(layout, linesOf(), id, card.id) : M.moveCardNext(linesOf(), id, card.id, zone));
  });
  return box;
}

// A card's own actions, shown on hover: a card beside it, a card in its menu, make it a card with a menu, delete.
function cardActions(card) {
  // over the card's top right on hover (the card keeps its size): the two that add a card above each other, then the rest
  const box = el("div", "card-actions");
  const adds = el("div", "adds"), rest = el("div", "rest");
  box.append(adds, rest);
  const action = (into, label, tip, fn, icon = false) => {
    const b = el("button", "", label);
    if (icon) withIcon(b, label);
    b.title = tip + " (hold the click a moment, or double-click)";
    b.draggable = false;
    // only a click held at least holdMs acts (a quick click passing over the icon does nothing); from the keyboard
    // (no pointer press) at once; a double-click at once, unless its first click acted already
    let down = 0, acted = false;
    b.addEventListener("pointerdown", () => { down = performance.now(); });
    b.addEventListener("click", e => {
      e.stopPropagation();
      const held = e.detail === 0 || (down > 0 && performance.now() - down >= holdMs);
      down = 0;
      if (e.detail === 1) acted = false;
      if (held && e.detail <= 1) { acted = true; fn(); }
    });
    b.addEventListener("dblclick", e => {
      e.stopPropagation();
      if (!acted) fn();
      acted = true;
    });
    into.append(b);
  };
  action(adds, "+ beside", "A new card beside this one", () => addAndFocus(M.addCard(layout, linesOf(), null, card.id)), true);
  if (M.isHolder(card)) action(adds, "+ inside", "A new card at the end of what it holds", () => {
    collapsed.delete(card.id);
    addAndFocus(M.addCard(layout, linesOf(), card.id));
  }, true);
  if (!M.isHolder(card) && !M.isRemaining(card) && !M.isNote(card) && !M.isOwn(card)) action(rest, "menu", "Make it a card with a submenu (its rules go to a first card in it)", () => {
    M.makeMenu(layout, linesOf(), card.id);
    changed();
  });
  if (!M.isRemaining(card)) action(rest, "x", "Delete this card", () => {
    if (M.deleteCard(linesOf(), card.id)) { if (selectedId === card.id) selectedId = null; changed(); }
  });
  return box;
}

// A rule dragged: from the rules view or a card's panel; onto a card it is moved, with Shift copied.
function startRuleDrag(e, card, index) {
  e.dataTransfer.setData("text/ruleref", JSON.stringify({ cardId: card.id, index }));
  e.dataTransfer.effectAllowed = "copyMove";
}

// Where on a card a drop lands: its top or bottom edge, a line of its own above or below the card's line; its left or
// right edge, beside it in its line; else onto it (it becomes a card with a menu).
function dropZoneOf(box, e, divider = false) {
  const r = box.getBoundingClientRect();
  const x = e.clientX - r.left, y = e.clientY - r.top;
  if (divider) return y < r.height / 2 ? "above" : "below";   // a divider goes between lines only
  const edgeY = Math.min(10, r.height / 4), edgeX = Math.max(14, r.width / 5);
  if (y < edgeY) return "above";
  if (y > r.height - edgeY) return "below";
  if (x < edgeX) return "before";
  if (x > r.width - edgeX) return "after";
  return "onto";
}
const zoneClass = zone => zone === "onto" ? "over" : "over-" + zone;

function select(id, ruleIndex) {
  if (ruleIndex >= 0) revealRule = true;
  selectedId = id;
  selectedRule = ruleIndex;
  post({ type: "mark", cardId: id || "" });
  render();
}

// ---- the selected card -----------------------------------------------------------------------------------------

function textField(label, value, onChange, placeholder = "") {
  const row = el("label", "field");
  const input = el("input");
  input.type = "text";
  input.value = value || "";
  input.placeholder = placeholder;
  input.addEventListener("change", () => onChange(input.value));
  row.append(el("span", "", label), input);
  return row;
}

// A card's size on its line (plan 03 3.5): its share of the width, a minimum width, a height in lines, and how it fits
// a taller line. Empty: the default (weight 1, no minimum, its content's height, as the line says).
function sizeFields(card) {
  const number = (name, label, placeholder) => textField(label, card[name] === undefined ? "" : String(card[name]), v => {
    const n = Number(v.trim());
    if (v.trim() && n > 0) card[name] = n; else delete card[name];
    changed();
  }, placeholder);
  const fit = el("select");
  for (const [v, label] of [["", "as its row says (by default stretched to its height)"], ["stretch", "stretched to its height"],
    ["top", "at its top"], ["center", "in its middle"], ["bottom", "at its bottom"]]) {
    const o = el("option", "", label);
    o.value = v;
    fit.append(o);
  }
  fit.value = card.cardFit || "";
  fit.addEventListener("change", () => { if (fit.value) card.cardFit = fit.value; else delete card.cardFit; changed(); });
  const fitRow = el("label", "field");
  fitRow.title = "A card lower than the row it stands in: stretched to the row's height, or at its own height at the row's top, middle or bottom (not its width)";
  fitRow.append(el("span", "", "Height in row"), fit);
  // its title wrapping over more lines: within the height when one is set, else the card as high as it needs
  const wrap = el("input");
  wrap.type = "checkbox";
  wrap.checked = !!card.wrap;
  wrap.addEventListener("change", () => { if (wrap.checked) card.wrap = true; else delete card.wrap; changed(); });
  const wrapRow = el("label", "field");
  wrapRow.title = "The title wraps over more lines: within Height when it is set (the last line cut with ...), else the card is as high as its lines";
  wrapRow.append(el("span", "", "Wrap"), el("span"));
  wrapRow.lastChild.append(wrap, " the title over more lines");
  // its height in lines; not with Square (its width sets its height then)
  const heightRow = number("height", "Height", card.square ? "(as wide as it is: square)" : "(its content) in lines of text");
  if (card.square) {
    heightRow.querySelector("input").disabled = true;
    heightRow.title = "Square: its height is its width";
  }
  // as high as it is wide (plan 11 3.1)
  const square = el("input");
  square.type = "checkbox";
  square.checked = !!card.square;
  square.addEventListener("change", () => { if (square.checked) card.square = true; else delete card.square; changed(); });
  const squareRow = el("label", "field");
  squareRow.append(el("span", "", "Square"), el("span"));
  squareRow.lastChild.append(square, " as high as it is wide");
  return [number("weight", "Weight", "1: its share of the line's width"),
    number("minWidth", "Min width", "(none) the line wraps when it does not fit"),
    heightRow, wrapRow, squareRow, fitRow];
}

// One colour's controls (plan 03 3.6): a swatch, where the colour comes from (the theme's own colour, when withTheme;
// a colour picked; a colour of the theme's palette by name), an intensity (0 - 200, 100 the colour itself) and an
// opacity (0 - 100) that only counts when "overrule" is ticked (else the colour's own alpha stays). cs (a
// LayoutModel.colorState, not JSON) is changed in place; commit() after each change that is to be written.
function colorControls(cs, withTheme, commit) {
  const controls = el("span", "color-controls");
  const swatch = el("span", "swatch");
  const source = el("select");
  const option = (value, text, color) => {
    const o = el("option", "", text);
    o.value = value;
    if (color) { o.style.background = color; o.style.color = "inherit"; }
    source.append(o);
  };
  if (withTheme) option("theme", "(the theme's)");
  option("pick", "a colour");
  const names = Object.keys(palette);
  if (cs.mode === "pick" && !cs.base.startsWith("#") && !names.includes(cs.base)) names.push(cs.base);
  for (const n of names) option("name:" + n, n, M.colorCss({ mode: "pick", base: n, intensity: 100, opacity: 100 }, palette));
  source.value = cs.mode === "pick" ? (cs.base.startsWith("#") ? "pick" : "name:" + cs.base) : "theme";
  const picker = el("input");
  picker.type = "color";
  picker.value = cs.mode === "pick" && cs.base.startsWith("#") ? cs.base : "#808080";
  const slider = (min, max, value, title) => {
    const r = el("input");
    r.type = "range";
    r.min = min;
    r.max = max;
    r.value = value;
    // the exact value typed beside the slider; the two follow each other
    const shown = el("input", "slider-value");
    shown.type = "number";
    shown.min = min;
    shown.max = max;
    shown.step = 1;
    shown.value = value;
    const box = el("label", "slider");
    box.title = title;
    box.append(r, shown);
    return [box, r, shown];
  };
  const [intensityBox, intensity, intensityShown] = slider(0, 200, cs.intensity ?? 100,
    "Intensity: 0 the theme's base colour, 100 the colour itself, 200 towards the base colour inverted");
  const [opacityBox, opacity, opacityShown] = slider(0, 100, cs.opacity ?? 100,
    "Opacity: 0 invisible, 100 solid; only with overrule ticked, else the colour's own (the theme's) opacity");
  const overrule = el("input");
  overrule.type = "checkbox";
  overrule.checked = !!cs.overrule;
  overrule.title = "Ticked: this opacity overrules the colour's own; not ticked: as the theme has it";
  intensityBox.prepend(el("span", "slider-name", "Intensity"));
  const opacityName = el("span", "slider-name");
  opacityName.append(overrule, " Opacity");
  opacityBox.prepend(opacityName);
  const show = () => {
    picker.hidden = source.value !== "pick";
    opacity.disabled = opacityShown.disabled = !cs.overrule;
    swatch.hidden = cs.mode !== "pick";
    swatch.style.setProperty("--swatch", M.colorCss(cs, palette) || "transparent");
  };
  // the sliders' values follow while dragging; written when let go
  const live = () => {
    cs.intensity = +intensity.value;
    cs.opacity = +opacity.value;
    intensityShown.value = intensity.value;
    opacityShown.value = opacity.value;
    show();
  };
  intensity.addEventListener("input", live);
  opacity.addEventListener("input", live);
  intensity.addEventListener("change", commit);
  opacity.addEventListener("change", commit);
  // a value typed: a whole number within the slider's range, then written as a slider let go
  for (const [field, range] of [[intensityShown, intensity], [opacityShown, opacity]])
    field.addEventListener("change", () => {
      const n = Math.round(Number(field.value));
      if (field.value.trim() === "" || !Number.isFinite(n)) { field.value = range.value; return; }
      range.value = Math.max(+range.min, Math.min(+range.max, n));
      live();
      commit();
    });
  overrule.addEventListener("change", () => { cs.overrule = overrule.checked; commit(); });
  picker.addEventListener("change", () => { cs.base = picker.value; commit(); });
  // the intensity and opacity kept when switching between the theme's, a colour and a palette colour
  source.addEventListener("change", () => {
    const v = source.value;
    if (v === "theme") { cs.mode = "theme"; delete cs.base; }
    else { cs.mode = "pick"; cs.base = v === "pick" ? picker.value : v.slice(5); }
    commit();
  });
  controls.append(swatch, source, picker, intensityBox, opacityBox);
  show();
  return controls;
}

// A colour field (plan 03 3.6): what it is, a colour (colorControls) or, where a gradient can be drawn (gradients), a
// gradient of two colours (From and To on rows of their own, each a colour or a palette colour with its intensity and
// opacity, and its angle), or anything else as JSON (a gradient of more colours, "none"). Written in its shortest form
// (LayoutModel.fillValue).
function colorField(label, get, set, gradients = false, withNone = false) {
  let state = M.fillState(get(), gradients);
  const row = el("div", "field color-field");
  const body = el("div", "color-body");
  const commit = () => {
    const r = M.fillValue(state);
    if (!r.ok) return;
    set(r.value);
    changed();
  };
  // a colour picked or a palette colour, for a gradient's colour: the field's own colour when it is one, else the
  // first palette colour, else grey
  const stop = () => state.kind === "colour" && state.colour.mode === "pick" ? { ...state.colour }
    : { mode: "pick", base: Object.keys(palette).find(n => n !== "basecolor") || "#808080", intensity: 100, opacity: 100, overrule: false };
  const build = () => {
    const kind = el("select");
    for (const [v, text] of [["colour", "a colour"], ...(gradients ? [["gradient", "a gradient"], ["image", "an image"]] : []),
      ...(withNone ? [["none", "none (not drawn)"]] : []), ["json", "other (JSON)"]]) {
      const o = el("option", "", text);
      o.value = v;
      kind.append(o);
    }
    kind.value = state.kind;
    kind.title = "A colour; a gradient from one colour to another; or anything else written as JSON (" +
      (gradients ? "a gradient of more colours, " : "") + "\"none\")";
    kind.addEventListener("change", () => {
      const current = M.fillValue(state);
      if (kind.value === "colour")
        state = { kind: "colour", colour: state.kind === "gradient" ? { ...state.start } : { mode: "theme", intensity: 100, opacity: 100, overrule: false } };
      else if (kind.value === "gradient") { const s = stop(); state = { kind: "gradient", start: s, end: { ...s }, angle: 90 }; }
      else if (kind.value === "none") state = { kind: "none" };
      else if (kind.value === "image") state = { kind: "image", spec: { image: "" } };
      else state = { kind: "json", text: current.ok && current.value !== undefined ? JSON.stringify(current.value) : "" };
      if (state.kind === "json" && !state.text) body.replaceChildren(...build());   // nothing to write yet
      else commit();
    });
    const first = el("div", "color-row");
    first.append(kind);
    if (state.kind === "image") {
      // the file (typed, or Browse...), how it fits, its opacity; a colour under it and a tint over it
      const spec = state.spec;
      const file = el("input");
      file.type = "text";
      file.value = spec.image || "";
      file.placeholder = "a file: PNG, JPEG, ...; %APPDATA%\\... allowed";
      file.addEventListener("change", () => { spec.image = file.value.trim(); commit(); });
      const browse = el("button", "", "Browse...");
      browse.addEventListener("click", e => {
        e.preventDefault();
        pickedImage = path => { spec.image = path; commit(); };
        post({ type: "pickImage" });
      });
      first.append(file, browse);
      const fit = el("select");
      for (const [v, text] of [["stretch", "stretched to the whole box"], ["fit", "whole inside, its proportions kept"],
        ["center", "its own size, in the middle"], ["repeatX", "tiled across"], ["repeatY", "tiled down"], ["repeat", "tiled"]]) {
        const o = el("option", "", text);
        o.value = v;
        fit.append(o);
      }
      fit.value = spec.fit || "stretch";
      fit.addEventListener("change", () => { spec.fit = fit.value; commit(); });
      const fitRow = el("div", "color-row");
      fitRow.append(el("span", "slider-name", "Fit"), fit);
      const opacity = sliderRow("Opacity", 0, 100, spec.opacity, 100, v => { spec.opacity = v; commit(); }, "0 invisible, 100 solid");
      // written into the image's value; the colour field itself reports the change
      const sub = (name, label) => colorField(label, () => spec[name], v => {
        if (v === undefined) delete spec[name]; else spec[name] = v;
        const r = M.fillValue(state);
        if (r.ok) set(r.value);
      });
      return [first, fitRow, opacity, sub("color", "Colour under"), sub("tint", "Tint over")];
    }
    if (state.kind === "colour") {
      first.append(colorControls(state.colour, true, commit));
      return [first];
    }
    if (state.kind === "none") return [first];
    if (state.kind === "json") {
      const json = el("input");
      json.type = "text";
      json.value = state.text;
      json.placeholder = gradients ? '{ "gradient": [ "accent", "surface", "bar" ], "angle": 0 } or "none"' : '"none"';
      json.addEventListener("change", () => { state.text = json.value.trim(); commit(); });
      first.append(json);
      return [first];
    }
    const angle = el("input", "slider-value");
    angle.type = "number";
    angle.step = 1;
    angle.value = state.angle;
    angle.title = "The gradient's direction in degrees: 0 left to right, 90 top to bottom";
    angle.addEventListener("change", () => {
      const n = Number(angle.value);
      if (angle.value.trim() === "" || !Number.isFinite(n)) { angle.value = state.angle; return; }
      state.angle = n;
      commit();
    });
    const angleBox = el("label", "slider angle");
    angleBox.append(el("span", "slider-name", "Angle"), angle);
    first.append(angleBox);
    const stopRow = (name, cs) => {
      const r = el("div", "color-row");
      r.append(el("span", "color-stop", name), colorControls(cs, false, commit));
      return r;
    };
    return [first, stopRow("From", state.start), stopRow("To", state.end)];
  };
  body.append(...build());
  row.append(el("span", "", label), body);
  return row;
}

// A select as a field row: options [value, text]; onChange(value).
function selectRow(label, options, value, onChange, title = "") {
  const sel = el("select");
  for (const [v, text] of options) { const o = el("option", "", text); o.value = v; sel.append(o); }
  sel.value = value;
  if (title) sel.title = title;
  sel.addEventListener("change", () => onChange(sel.value));
  const row = el("label", "field");
  row.append(el("span", "", label), sel);
  return row;
}

// A checkbox as a field row.
function checkRow(label, checked, onChange) {
  const box = el("input");
  box.type = "checkbox";
  box.checked = !!checked;
  box.addEventListener("change", () => onChange(box.checked));
  const row = el("label", "field");
  const span = el("span");
  row.append(el("span", "", label), span);
  span.append(box);
  return row;
}

// A property of an object in the card (card[key], made when set, gone when empty), as get/set for a field.
function partOf(card, key, name) {
  return {
    get: () => card[key] && card[key][name],
    set: v => {
      if (v === undefined) { if (card[key]) { delete card[key][name]; if (!Object.keys(card[key]).length) delete card[key]; } }
      else card[key] = Object.assign(card[key] || {}, { [name]: v });
    }
  };
}

// The rows after the first drawn as its sub-options: indented, a tree line to the first (as Font's own font).
function asTree(rows) {
  rows.slice(1).forEach((r, i, all) => r.classList.add("sub", ...(i === all.length - 1 ? ["last"] : [])));
  return rows;
}

// A number as a slider with the exact value beside it (as a colour's intensity): from min to max; empty the default.
function sliderRow(label, min, max, value, fallback, onChange, title = "") {
  const r = el("input");
  r.type = "range";
  r.min = min;
  r.max = max;
  r.value = value ?? fallback;
  const shown = el("input", "slider-value");
  shown.type = "number";
  shown.min = min;
  shown.max = max;
  shown.step = 1;
  shown.value = value ?? fallback;
  const box = el("span", "slider");
  if (title) box.title = title;
  box.append(r, shown);
  r.addEventListener("input", () => { shown.value = r.value; });
  r.addEventListener("change", () => onChange(+r.value));
  shown.addEventListener("change", () => {
    const n = Math.max(min, Math.min(max, Math.round(+shown.value || 0)));
    shown.value = r.value = n;
    onChange(n);
  });
  const row = el("label", "field");
  row.append(el("span", "", label), box);
  return row;
}

// A number in such an object: empty the default.
function partNumber(card, key, name, label, placeholder, min = 0) {
  const p = partOf(card, key, name);
  return textField(label, p.get() === undefined ? "" : String(p.get()), v => {
    const n = Number(v.trim());
    p.set(v.trim() && Number.isFinite(n) && n >= min ? n : undefined);
    changed();
  }, placeholder);
}

// A card's border (plan 03 3.6) as one style: flat (its colour, the theme's when none is set), raised or sunk (a 3D
// border as a lit panel: its width, where the light comes from, the light and dark colours), or none; each style's
// settings under it with a tree line.
function borderFields(card) {
  const style = card.border3d && ["outset", "inset"].includes(card.border3d.style) ? card.border3d.style
    : card.border === "none" ? "none" : "flat";
  const rows = [selectRow("Border", [["flat", "flat"], ["outset", "raised (3D)"], ["inset", "sunk (3D)"], ["none", "none (not drawn)"]], style, v => {
    if (v === "outset" || v === "inset") {
      card.border3d = Object.assign(card.border3d || {}, { style: v });
      delete card.border;
    } else {
      delete card.border3d;
      if (v === "none") card.border = "none"; else if (card.border === "none") delete card.border;
    }
    changed();
  }, "Flat: a line in a colour; raised or sunk: lit as a panel, light inside the edges facing the light, shadow inside the others")];
  if (style === "flat")
    rows.push(colorField("Colour", () => card.border, v => { if (v === undefined) delete card.border; else card.border = v; }));
  else if (style !== "none")
    rows.push(partNumber(card, "border3d", "width", "Width", "2 (DIP)", 0.5),
      partNumber(card, "border3d", "angle", "Light from", "135 (degrees: 90 the top, 135 top left, 180 the left)", -360),
      colorField("Light", partOf(card, "border3d", "light").get, partOf(card, "border3d", "light").set),
      colorField("Shadow", partOf(card, "border3d", "shadow").get, partOf(card, "border3d", "shadow").set));
  return asTree(rows);
}

// A card's shadow (plan 03 3.6): its shape at a distance away from the light, under the card, its edge blurred; only
// on the menu's own background.
function shadowFields(card) {
  const rows = [checkRow("Shadow", !!card.shadow, on => { if (on) card.shadow = { distance: 3 }; else delete card.shadow; changed(); })];
  if (!card.shadow) return rows;
  rows.push(colorField("Colour", partOf(card, "shadow", "color").get, partOf(card, "shadow", "color").set),
    partNumber(card, "shadow", "distance", "Distance", "3 (DIP)"),
    partNumber(card, "shadow", "angle", "Light from", "135 (degrees; the shadow falls away from it)", -360),
    sliderRow("Blur", 0, 16, card.shadow.blur, 0, v => { partOf(card, "shadow", "blur").set(v || undefined); changed(); },
      "0 a sharp edge; up to 16: softer and wider (DIP)"));
  return asTree(rows);
}

let fonts = [];   // the installed font families, from the settings app
let pickedImage = null;   // a background image field waiting for its file from the settings app's dialog
let pickedNoteFile = null;   // a note waiting for the file it shows (plan 14)

// A font family as a dropdown of the installed ones (as LexPen's), each in its own font; empty: the items' font. A
// family the layout names that is not installed stays, marked so.
function familyRow(value, onChange) {
  const options = [["", "(the items' font)"], ...fonts.map(f => [f, f])];
  if (value && !fonts.includes(value)) options.splice(1, 0, [value, value + " (not installed)"]);
  const row = selectRow("Family", options, value || "", onChange);
  for (const o of row.querySelector("select").options) if (o.value) o.style.fontFamily = '"' + o.value.replace(/"/g, "") + '"';
  return row;
}

// A note's font (plan 03 3.6): the items' text, the smaller extra text, or its own (family, size, bold, italic; empty:
// the items'). Plain text only.
function fontFields(card) {
  const kind = card.font === "extra" ? "extra" : card.font && typeof card.font === "object" ? "own" : "text";
  const rows = [selectRow("Font", [["text", "as the items' text"], ["extra", "as the extra text (smaller)"], ["own", "its own"]], kind, v => {
    if (v === "text") delete card.font; else if (v === "extra") card.font = "extra"; else card.font = {};
    changed();
  })];
  if (kind !== "own") return rows;
  const f = card.font;
  rows.push(familyRow(f.family, v => { if (v) f.family = v; else delete f.family; changed(); }),
    textField("Size", f.size === undefined ? "" : String(f.size), v => {
      const n = Number(v.trim());
      if (v.trim() && n >= 4) f.size = Math.min(72, n); else delete f.size;
      changed();
    }, "(the items' size, in DIP)"),
    checkRow("Bold", f.bold, on => { if (on) f.bold = true; else delete f.bold; changed(); }),
    checkRow("Italic", f.italic, on => { if (on) f.italic = true; else delete f.italic; changed(); }));
  // its own font's parts under Font, indented with a tree line to it
  return asTree(rows);
}

// A card's own look over the theme's (plan 03 3.6): its colours as pickers (colorField), the hover background the
// same; the radius a number; its 3D border and shadow. A note: its font after its text colour, no hover.
function lookFields(card, note = false) {
  const own = name => ({ get: () => card[name], set: v => { if (v === undefined) delete card[name]; else card[name] = v; } });
  const hover = {
    get: () => card.hover && card.hover.background,
    set: v => {
      if (v === undefined) { if (card.hover) { delete card.hover.background; if (!Object.keys(card.hover).length) delete card.hover; } }
      else card.hover = Object.assign(card.hover || {}, { background: v });
    }
  };
  return [colorField("Background", own("background").get, own("background").set, true, true),
    colorField("Text colour", own("foreground").get, own("foreground").set),
    ...(note ? fontFields(card) : []),
    ...borderFields(card),
    textField("Radius", card.radius === undefined ? "" : String(card.radius), v => {
      const n = Number(v.trim());
      if (v.trim() && n >= 0) card.radius = n; else delete card.radius;
      changed();
    }, "(the theme's) corners, in DIP"),
    ...shadowFields(card),
    ...(note ? [] : [colorField("Hover background", hover.get, hover.set, true, true)])];
}

// "any" (every name, no text): written as the wildcard "*"; the kind "any" of the file (equals one of a list) is shown
// as "one of".
function matchEditor(match, onChange) {
  const kindSel = el("select");
  const anyName = m => !!m && Object.keys(m).length === 1 && m.wildcard === "*";
  for (const k of ["anyName", ...M.matchKinds]) {
    const o = el("option", "", k === "anyName" ? "any" : k === "any" ? "one of" : k);
    o.value = k;
    kindSel.append(o);
  }
  const current = anyName(match) ? "anyName" : match ? Object.keys(match)[0] : "contains";
  kindSel.value = current;
  const input = el("input");
  input.type = "text";
  input.value = current === "anyName" ? "" : match ? (current === "any" ? (match.any || []).join(", ") : match[current]) : "";
  input.placeholder = current === "any" ? "one, two, three" : "text";
  input.hidden = current === "anyName";
  const update = () => {
    const k = kindSel.value;
    onChange(k === "anyName" ? { wildcard: "*" }
      : k === "any" ? { any: input.value.split(",").map(s => s.trim()).filter(Boolean) } : { [k]: input.value });
  };
  kindSel.addEventListener("change", update);
  input.addEventListener("change", update);
  return [kindSel, input];
}

// A rule's panel: a group box with its number, its place in the priority list and its type in the border line, "x"
// (delete) at the top right of that line, its whole left edge the handle to drag it by; inside, its settings in two
// columns, a label and its fields.
function ruleEditor(card, rule, index) {
  const box = el("div", "rule" + (index === selectedRule ? " selected" : "") + (rule.exclude ? " exclude" : ""));
  // Reordered by dragging its handle (the card's rules keep their places in the priority list, swapped among
  // themselves); numbered within the card, with its number in the priority list beside it.
  const handle = el("div", "rule-handle");
  handle.draggable = true;
  handle.title = "Drag to change the order of this card's rules, or onto another card: move (Shift: copy)";
  handle.addEventListener("dragstart", e => {
    e.stopPropagation();
    e.dataTransfer.setData("text/cardrule", String(index));
    startRuleDrag(e, card, index);
  });
  box.addEventListener("dragover", e => { if (e.dataTransfer.types.includes("text/cardrule")) { e.preventDefault(); box.classList.add("over"); } });
  box.addEventListener("dragleave", () => box.classList.remove("over"));
  box.addEventListener("drop", e => {
    box.classList.remove("over");
    const from = e.dataTransfer.getData("text/cardrule");
    if (from === "") return;
    e.preventDefault();
    if (M.moveCardRule(linesOf(), card, +from, index)) { selectedRule = index; changed(); }
  });
  const head = el("div", "rule-head");
  const number = el("span", "number", (index + 1) + ".");
  const priority = el("span", "badge", "#" + rule.priority);
  priority.title = "Its place in the priority list";
  // the rule's type (plan 09 3.3): Name or Usage, each with its own group of fields; only the chosen one shown
  const typeSel = el("select");
  for (const [t, label] of [["name", "Name"], ["usage", "Usage"], ["editMenu", "Edit Dexmenu"], ["windowsMenu", "Windows' menu"]]) {
    const o = el("option", "", label);
    o.value = t;
    typeSel.append(o);
  }
  typeSel.value = M.ruleType(rule);
  typeSel.title = "What the rule finds: items by their name, or by their use (the most used or most recently used); or " +
    "Dexmenu's own item, Edit Dexmenu (this editor on the layout in use) or Windows' menu (Windows' own menu shown instead)";
  typeSel.addEventListener("change", () => { M.setRuleType(rule, typeSel.value); changed(); });
  head.append(number, priority, typeSel);
  // a setting's row: its label in the first column, its fields in the second
  const body = el("div", "rule-body");
  const row = (label, ...fields) => {
    const f = el("div", "rule-fields");
    f.append(...fields);
    body.append(el("span", "rule-label", label), f);
    return f;
  };
  const ownType = M.ruleType(rule) === "editMenu" || M.ruleType(rule) === "windowsMenu";
  if (ownType) {
    // Dexmenu's own item (plan 12): nothing more to set; the card places it as any item it finds
    body.append(el("span", "rule-label"), el("div", "rule-fields hint", rule.own === "editMenu"
      ? "Finds \"Edit menu...\": chosen, the menu closes and this editor opens on the layout in use"
      : "Finds \"Windows' menu\": chosen, Dexmenu's menu closes and Windows' own menu shows in its place"));
  } else if (M.ruleType(rule) === "usage") {
    const usedSel = el("select");
    for (const [u, label] of [["most", "most used"], ["recent", "most recently used"]]) { const o = el("option", "", label); o.value = u; usedSel.append(o); }
    usedSel.value = rule.used === "recent" ? "recent" : "most";
    usedSel.addEventListener("change", () => { rule.used = usedSel.value; changed(); });
    const rank = el("input");
    rank.type = "text";
    rank.className = "rank";
    rank.placeholder = "all";
    rank.title = "Empty: all of them, in order; a number from 1 (3: the third); a range (1-3, or 3-1: the same in reverse); several, as pages to print (1,3,5 or 1-2,5-6,8-10)";
    rank.value = rule.rank === undefined ? "" : String(rule.rank);
    rank.addEventListener("change", () => {
      const v = rank.value.trim();
      if (v === "") delete rule.rank;
      else rule.rank = /^\d+$/.test(v) ? +v : v;
      changed();
    });
    row("Finds the", usedSel);
    row("Rank", rank);
  } else {
    const cs = el("input");
    cs.type = "checkbox";
    cs.checked = !!rule.caseSensitive;
    cs.addEventListener("change", () => { if (cs.checked) rule.caseSensitive = true; else delete rule.caseSensitive; changed(); });
    const csl = el("label");
    csl.append(cs, " case sensitive");
    row("Name", ...matchEditor(rule.name, m => { rule.name = m; changed(); }), csl);
  }
  const placeSel = el("select");
  for (const p of ["top", "anywhere", "path"]) { const o = el("option", "", placeNames[p]); o.value = p; placeSel.append(o); }
  placeSel.value = rule.path ? "path" : rule.scope === "anywhere" ? "anywhere" : "top";
  placeSel.addEventListener("change", () => {
    delete rule.scope;
    delete rule.path;
    if (placeSel.value === "anywhere") rule.scope = "anywhere";
    if (placeSel.value === "path") rule.path = { contains: "" };
    changed();
  });
  if (M.ruleType(rule) === "name")
    row("Where", placeSel, ...(rule.path ? matchEditor(rule.path, m => { rule.path = m; changed(); }) : []));
  if (M.ruleType(rule) === "name") {
    // "latest": of what it finds only the ones seen most recently (an item whose name changes each time)
    const latest = el("input");
    latest.type = "text";
    latest.className = "rank";
    latest.placeholder = "all";
    latest.title = "Empty: all it finds; a number: only that many, the ones seen most recently (an item whose name " +
      "changes, as \"Compare to <file>\"); the others are taken all the same";
    latest.value = rule.latest === undefined ? "" : String(rule.latest);
    latest.addEventListener("change", () => {
      const v = latest.value.trim();
      if (v === "") delete rule.latest;
      else rule.latest = /^\d+$/.test(v) ? +v : v;
      changed();
    });
    row("Latest", latest);
  }
  // the template the items it finds follow, when its card picks templates by rule (plan 11 3.1)
  if (card.templatesBy === "rule" && Array.isArray(card.templates) && card.templates.length > 0) {
    const tsel = el("select");
    for (let i = 0; i <= card.templates.length; i++) {
      const o = el("option", "", i === 0 ? "(the first)" : "Template " + i);
      o.value = i === 0 ? "" : String(i);
      tsel.append(o);
    }
    tsel.value = rule.template ? String(rule.template) : "";
    tsel.addEventListener("change", () => { if (tsel.value) rule.template = +tsel.value; else delete rule.template; changed(); });
    row("Template", tsel);
  }
  // the states it takes: a group whose border holds "Overrule general setting: States"; not ticked, the rule takes what General sets (shown,
  // greyed); ticked, its own, written even when both (General may say otherwise)
  const statesBox = el("fieldset", "states");
  const legend = el("legend");
  const own = el("input");
  own.type = "checkbox";
  own.checked = Array.isArray(rule.states);
  own.addEventListener("change", () => {
    if (own.checked) rule.states = M.statesOf(rule, generalStates).slice(); else delete rule.states;
    changed();
  });
  const ownLabel = el("label");
  ownLabel.title = "Not ticked: as General sets for every rule (the main window); ticked: this rule's own";
  ownLabel.append(own, " Overrule general setting: States");
  legend.append(ownLabel);
  statesBox.append(legend);
  const states = M.statesOf(rule, generalStates);
  for (const s of ["enabled", "disabled"]) {
    const cb = el("input");
    cb.type = "checkbox";
    cb.checked = states.includes(s);
    cb.disabled = !own.checked;
    cb.addEventListener("change", () => {
      const now = new Set(rule.states);
      cb.checked ? now.add(s) : now.delete(s);
      if (now.size === 0) { cb.checked = true; return; }   // it takes something: one stays
      rule.states = ["enabled", "disabled"].filter(x => now.has(x));
      changed();
    });
    const l = el("label");
    l.append(cb, " " + s);
    statesBox.append(l);
  }
  if (!ownType) body.append(el("span", "rule-label"), statesBox);
  const opts = ownType ? el("div") : row("Options");
  for (const [flag, label, tip] of [["also", "also when taken"],
    ["skipDuplicates", "skip duplicates (one per name)"],
    ["exclude", "exclude", "It finds nothing: what it matches, this card's rules after it do not take (it stays free for other cards)"]]) {
    if (flag === "exclude" && M.ruleType(rule) !== "name") continue;   // a rule by name only
    const cb = el("input");
    cb.type = "checkbox";
    cb.checked = !!rule[flag];
    cb.addEventListener("change", () => { if (cb.checked) rule[flag] = true; else delete rule[flag]; changed(); });
    const l = el("label");
    if (tip) l.title = tip;
    l.append(cb, " " + label);
    opts.append(l);
  }
  {
    const cb = el("input");   // on by default: the file has "consume": false only when off
    cb.type = "checkbox";
    cb.checked = rule.consume !== false;
    cb.addEventListener("change", () => { if (cb.checked) delete rule.consume; else rule.consume = false; changed(); });
    const l = el("label");
    l.title = "Off: the item stays free, so later rules and the remaining card can show it too";
    l.append(cb, " consumes the item");
    opts.append(l);
  }
  const actions = el("div", "rule-actions");
  const del = el("button", "", "x");
  del.title = "Delete this rule";
  del.addEventListener("click", e => { e.stopPropagation(); M.deleteRule(linesOf(), card, index); selectedRule = -1; changed(); });
  actions.append(del);
  box.append(head, actions, handle, body);
  const problem = M.ruleProblem(rule);
  if (problem) box.append(el("div", "problem", problem));
  // selecting the rule only moves the highlights: a full render here would replace the checkbox or field this same
  // click is meant for (the first click was lost)
  box.addEventListener("click", () => {
    if (selectedRule === index) return;
    selectedRule = index;
    for (const r of $("card").querySelectorAll(".rule")) r.classList.toggle("selected", r === box);
    renderRules();
  });
  return box;
}

function renderCardPane() {
  const div = selectedId ? M.findDivider(linesOf(), selectedId) : null;
  if (div && div.entry.search) {
    $("cardHeading").textContent = "The search box";
    $("card").replaceChildren(el("p", "hint", "Shows where typing goes. A letter that is an access key picks its " +
      "item; any other letter starts the search: every item at any depth whose name holds the text (a leading / for a " +
      "regex). Without a search box, typing searches the same way."));
    return;
  }
  if (div) {
    // a divider: its text and where the text goes; its own look over the theme's (plan 03 3.8): height, background,
    // line colour (none: no line), label colour and font
    $("cardHeading").textContent = "A divider";
    const box = $("card");
    box.replaceChildren(textField("Text", div.entry.divider, v => { div.entry.divider = v; changed(); }, "(none: a plain line)"));
    const row = el("label", "field");
    const align = el("select");
    for (const a of ["left", "center", "right"]) { const o = el("option", "", a); o.value = a; align.append(o); }
    align.value = div.entry.align || "left";
    align.addEventListener("change", () => { if (align.value === "left") delete div.entry.align; else div.entry.align = align.value; changed(); });
    row.append(el("span", "", "Text aligned"), align);
    const e = div.entry;
    const own = name => ({ get: () => e[name], set: v => { if (v === undefined) delete e[name]; else e[name] = v; } });
    box.append(row,
      textField("Height", e.height === undefined ? "" : String(e.height), v => {
        const n = Number(v.trim());
        if (v.trim() && n > 0) e.height = n; else delete e.height;
        changed();
      }, "(the theme's) in DIP"),
      colorField("Background", own("background").get, own("background").set, true, true),
      colorField("Line colour", own("border").get, own("border").set, false, true),
      colorField("Text colour", own("foreground").get, own("foreground").set),
      ...fontFields(e));
    return;
  }
  // a template (plan 11 3.1): its texts that apply to every item, its layout and its style
  const tm = /^(.*)~t(\d+)$/.exec(selectedId || "");
  const holderAt = tm ? M.find(linesOf(), tm[1]) : null;
  if (holderAt && Array.isArray(holderAt.card.templates) && holderAt.card.templates[+tm[2]]) {
    const t = holderAt.card.templates[+tm[2]];
    $("cardHeading").textContent = "Template " + (+tm[2] + 1) + " of " + holderAt.card.card;
    const names = [...asTree([textField("Rename (regex)", t.rename && t.rename.regex, v => {
      if (v) t.rename = { regex: v, replace: (t.rename && t.rename.replace) || "" }; else delete t.rename;
      changed();
    }), textField("Replace with", t.rename && t.rename.replace, v => { if (t.rename) { t.rename.replace = v; changed(); } })]),
    ...asTree([textField("Extra text", t.extra, v => { if (v) t.extra = v; else delete t.extra; changed(); }, "(none) a smaller text with each title"),
    extraAtField(t)]),
    textField("Icon", t.icon, v => { if (v.trim()) t.icon = v.trim(); else delete t.icon; changed(); }, "(each item's own) e.g. E8C8"),
    textField("Hint", typeof t.hint === "string" ? t.hint : "", v => { if (v) t.hint = v; else delete t.hint; changed(); }, "(each item's own hint)")];
    $("card").replaceChildren(el("div", "hint", "Every inner card made for what " + holderAt.card.card + " finds follows a template: its title is the item's text."),
      renderPanels(t, { names, layout: sizeFields(t), style: lookFields(t) }));
    return;
  }
  if (selectedId === "menu") {
    // the menu card (plan 11 3.9): how its cards show, its submenus' default, its style; its name is the layout's
    const root = layout.menu;
    $("cardHeading").textContent = "The menu";
    const way = el("select");
    for (const [v, label] of [["", "as set for every menu (General)"], ["next", "next to the card"], ["under", "under the card"],
      ["replace", "in place of the menu (<< back)"]]) { const o = el("option", "", label); o.value = v; way.append(o); }
    way.value = root.submenus || "";
    way.addEventListener("change", () => { if (way.value) root.submenus = way.value; else delete root.submenus; changed(); });
    const wayRow = el("label", "field");
    wayRow.title = "How submenus open in this layout, unless a card says otherwise";
    wayRow.append(el("span", "", "Submenus open"), way);
    $("card").replaceChildren(el("div", "hint", "The menu itself, holding every card of the layout. It is not moved, copied or deleted."),
      renderPanels(root, { inside: [...showFields(root, false, true), wayRow], style: [...lookFields(root), ...(root.background === "none" ? [el("div", "hint", "No background: the menu is see-through, only its cards, dividers and rows drawn; each card on an opaque base (a card cannot be see-through then).")] : [])] }));
    return;
  }
  const at = selectedId ? M.find(linesOf(), selectedId) : null;
  if (!at) {
    $("cardHeading").textContent = "Card";
    $("card").replaceChildren(el("div", "hint", "Select a card to edit it and its rules."));
    return;
  }
  const card = at.card;
  if (M.isNote(card)) {
    // a note: its text only (several lines; no name, rules or menu)
    $("cardHeading").textContent = "A note";
    const area = el("textarea");
    area.rows = 6;
    area.value = card.note || "";
    area.placeholder = "(empty: a space in the menu)";
    area.addEventListener("change", () => { card.note = area.value; changed(); });
    area.title = "{date} and {time}: today's date and the time the menu opens, in Windows' short formats; " +
      "{date:dddd d MMMM} or {time:HH:mm}: in a format of your own; {file:<path>}: what the file holds (a local drive, " +
      "at most 320 characters); {{ and }}: a brace";
    const row = el("label", "field");
    const text = el("span");
    // File...: {file:<path>} at the cursor (plan 14)
    const fileButton = el("button", "", "File...");
    fileButton.title = "A file whose text the note shows: {file:<path>} where the cursor is";
    fileButton.addEventListener("click", e => {
      e.preventDefault();
      const at = area.selectionStart ?? area.value.length, to = area.selectionEnd ?? at;
      pickedNoteFile = m => {
        const ph = "{file:" + M.withVariables(m.path, m.appdata, m.userprofile) + "}";
        card.note = area.value.slice(0, at) + ph + area.value.slice(to);
        changed();
      };
      post({ type: "pickNoteFile" });
    });
    const hint = el("div", "hint", "{date}, {time}, {date:dddd d MMMM}, {time:HH:mm}, {file:<path>}: filled in when the menu opens ");
    hint.append(fileButton);
    text.append(area, hint);
    const label = el("span", "", "Text");
    label.style.alignSelf = "start";
    row.append(label, text);
    // where its text goes: the card's left edge, in line with the items' text, the middle, the right
    const place = el("select");
    for (const [v, label] of [["left", "left"], ["text", "aligned with the menu's text"], ["center", "centered"], ["right", "right"]]) {
      const o = el("option", "", label);
      o.value = v;
      place.append(o);
    }
    place.value = card.align || "left";
    place.addEventListener("change", () => { if (place.value === "left") delete card.align; else card.align = place.value; changed(); });
    const placeRow = el("label", "field");
    placeRow.append(el("span", "", "Text placed"), place);
    // an empty note (nothing typed, or a file giving nothing): shown as a space, or left out (plan 14)
    const emptyRow = selectRow("When empty", [["", "shown (a space)"], ["hide", "left out"]], card.empty || "",
      v => { if (v) card.empty = v; else delete card.empty; changed(); },
      "When its text ends up empty: nothing typed, or a file that gives nothing");
    $("card").replaceChildren(row, placeRow, emptyRow, ...sizeFields(card), ...lookFields(card, true),
      el("div", "hint", "A note is no button: it is shown as text, with nothing to click."));
    return;
  }
  $("cardHeading").textContent = M.isOwn(card) ? "Dexmenu's own item" : M.isRemaining(card) ? "The remaining card"
    : M.isHolder(card) ? "A card holding cards" : "A card with rules";
  const groups = cardGroups(card);
  $("card").replaceChildren(cardTop(card), renderPanels(card, groups));
  if (revealRule) {
    revealRule = false;
    requestAnimationFrame(() => { const r = $("card").querySelector(".rule.selected"); if (r) r.scrollIntoView({ block: "nearest" }); });
  }
}

// ---- the card panel's parts (plan 13): the name fixed at the top, the other fields in panels the user arranges -----

const holdMs = 150;   // how long a card's hover icon must be held down to act
let revealRule = false;   // a rule selected elsewhere (the rules view, the preview): shown once the panel is drawn
const chosenTabs = new Map();   // a set of tabs (by its panels) -> the tab chosen in it (by that tab's panels), this session
const panelsKey = "dexmenu.cardPanels";
let arrangement = (() => {
  try { return M.normalArrangement(JSON.parse(localStorage.getItem(panelsKey) || "null")); }
  catch (e) { return M.defaultArrangement(); }
})();
function keepArrangement() {
  try { localStorage.setItem(panelsKey, JSON.stringify(arrangement)); } catch (e) { /* not kept: this session only */ }
}

// Segoe Fluent Icons (Segoe MDL2 Assets on Windows 10): an open eye, and one struck through
const eyeShown = String.fromCharCode(0xE890), eyeHidden = String.fromCharCode(0xED1A);

// The fixed top: the card's name (Dexmenu's own item: its title) and, at its right, Hidden as an eye.
function cardTop(card) {
  const top = el("div", "card-top");
  const own = M.isOwn(card);
  const name = textField(own ? "Title" : "Name", card.card, v => {
    const before = card.card;
    card.card = v || (own ? (card.own === "windowsMenu" ? "Windows' menu" : "Edit menu...") : "Card");
    if (card.title !== undefined && card.title === before) card.title = card.card;   // a title that was the name follows it
    changed();
  });
  top.append(name);
  if (!M.isRemaining(card) && !own) {
    const eye = el("button", "eye" + (card.hidden ? " hidden" : ""), card.hidden ? eyeHidden : eyeShown);
    eye.title = card.hidden ? "Hidden: not shown; its rules still take their items, so they show nowhere (click to show it)"
      : "Shown (click to hide it: its rules still take their items, so they show nowhere, not in the remaining card either)";
    eye.addEventListener("click", () => { if (card.hidden) delete card.hidden; else card.hidden = true; changed(); });
    top.append(eye);
  }
  return top;
}

// A card's fields by panel (plan 13 3.1, 3.2): { names, rules, inside, layout, style }, each a list of elements; a
// panel the card's kind does not have is left out.
function cardGroups(card) {
  const own = M.isOwn(card), rest = M.isRemaining(card), withRules = !M.isHolder(card) && !rest && !own;
  const g = {};
  // Names: what it and its items show as text, the icon, the hint, the comment
  const names = [];
  if (own) {
    const which = el("select");
    for (const [v, label] of [["editMenu", "Edit menu...: this editor on the layout in use"], ["windowsMenu", "Windows' menu: shows Windows' own menu"]]) {
      const o = el("option", "", label);
      o.value = v;
      which.append(o);
    }
    which.value = card.own;
    which.addEventListener("change", () => { card.own = which.value; changed(); });
    const row = el("label", "field");
    row.append(el("span", "", "Item"), which);
    names.push(row);
  } else names.push(textField("Title", card.title, v => { if (v) card.title = v; else delete card.title; changed(); },
    M.isHolder(card) ? "(its name, shown as its submenu's item; none above what it holds)" : "(the item's own text for one item)"));
  if (M.isHolder(card) && card.show !== "submenu") {
    // a holder's title above what it holds: as a title, or as a divider with that text
    const titleAs = el("select");
    for (const [v, label] of [["", "a title"], ["divider", "a divider"]]) { const o = el("option", "", label); o.value = v; titleAs.append(o); }
    titleAs.value = card.titleAs || "";
    titleAs.addEventListener("change", () => { if (titleAs.value) card.titleAs = titleAs.value; else delete card.titleAs; changed(); });
    const row = el("label", "field");
    row.append(el("span", "", "Title shown as"), titleAs);
    names.push(row);
  }
  if (withRules) names.push(...asTree([textField("Rename (regex)", card.rename && card.rename.regex, v => {
    if (v) card.rename = { regex: v, replace: (card.rename && card.rename.replace) || "" }; else delete card.rename;
    changed();
  }), textField("Replace with", card.rename && card.rename.replace, v => {
    if (card.rename) { card.rename.replace = v; changed(); }
  })]));
  names.push(...asTree([textField("Extra text", card.extra, v => { if (v) card.extra = v; else delete card.extra; changed(); },
    "(none) a smaller text with the title"), extraAtField(card)]));
  // its icon (plan 02 3.8): a glyph of Segoe Fluent Icons by its code point, or an icon in a file; else the item's own
  if (!rest) names.push(textField("Icon", card.icon, v => { if (v.trim()) card.icon = v.trim(); else delete card.icon; changed(); },
    own ? "(none) e.g. E70F" : "(the item's own) e.g. E8C8, or shell32.dll,4"));
  if (!own) {
    // the hint on hover: a text in place of the item's own hint, or a regex on it (so it can be added to)
    const hint = card.hint;
    names.push(textField("Hint", typeof hint === "string" ? hint : "", v => {
      if (v) card.hint = v; else if (typeof card.hint === "string") delete card.hint;
      changed();
    }, "(the item's own hint)"), ...asTree([textField("Hint regex", hint && typeof hint === "object" ? hint.regex : "", v => {
      if (v) card.hint = { regex: v, replace: (card.hint && typeof card.hint === "object" && card.hint.replace) || "" };
      else if (card.hint && typeof card.hint === "object") delete card.hint;
      changed();
    }, "e.g. ^(.*)$ to add to it"), textField("Replace with", hint && typeof hint === "object" ? hint.replace : "", v => {
      if (card.hint && typeof card.hint === "object") { card.hint.replace = v; changed(); }
    }, "e.g. $1 (via LexPen)")]));
  }
  // the comment: for the editor only, never in the menu
  const comment = el("label", "field");
  const area = el("textarea");
  area.rows = 3;
  area.value = card.comment || "";
  area.placeholder = "(only here, never in the menu)";
  area.addEventListener("change", () => { if (area.value) card.comment = area.value; else delete card.comment; changed(); });
  comment.append(el("span", "", "Comment"), area);
  names.push(comment);
  g.names = names;
  // Rules: what it finds
  if (withRules) {
    const rules = [];
    const actions = el("div", "actions");
    const add = el("button", "", "+ Rule");
    add.addEventListener("click", () => { M.addRule(linesOf(), card); selectedRule = card.rules.length - 1; changed(); });
    actions.append(add);
    rules.push(actions, ...(card.rules || []).map((r, i) => ruleEditor(card, r, i)));
    // one item per name over all its rules (Windows 11 shows some items twice: a newer and an older copy)
    const cb = el("input");
    cb.type = "checkbox";
    cb.checked = !!card.skipDuplicates;
    cb.addEventListener("change", () => { if (cb.checked) card.skipDuplicates = true; else delete card.skipDuplicates; changed(); });
    const l = el("label", "field");
    l.title = "Of the items its rules find with the same name, only the first shows; the others show nowhere";
    l.append(el("span", "", "Duplicates"), el("span"));
    l.lastChild.append(cb, " skip: one item per name");
    rules.push(l);
    g.rules = rules;
  } else if (rest) g.rules = [el("div", "what", "Every item of Windows' menu that no rule took is placed here, each a card of its own, with its submenu. It can be moved, also into a card with a menu, but not deleted.")];
  // Inside: how what it found shows and opens
  if (!own) {
    const inside = [];
    if (withRules || M.isHolder(card)) inside.push(...showFields(card, withRules));
    // how what opens from this card opens: as set for every menu (main window), or its own way
    const way = el("select");
    for (const [v, label] of [["", "as set for every menu"], ["next", "next to the card"], ["under", "under the card"],
      ["replace", "in place of the menu (<< back)"]]) {
      const o = el("option", "", label);
      o.value = v;
      way.append(o);
    }
    way.value = card.submenus || "";
    way.addEventListener("change", () => { if (way.value) card.submenus = way.value; else delete card.submenus; changed(); });
    const row = el("label", "field");
    row.title = M.isHolder(card) ? "How this card's submenu opens" : "How the submenus of the items this card shows open";
    row.append(el("span", "", "Submenus open"), way);
    inside.push(row);
    g.inside = inside;
  }
  // Layout and Style: not the remaining card's (its items each take a line of their own, in their own look)
  if (!rest) {
    g.layout = sizeFields(card);
    g.style = lookFields(card);
  }
  return g;
}

// The panels as arranged (plan 13 3.3): on their own or in sets of tabs, only those the card has; each panel's name
// on its border line (or its tab) is the handle to drag it by.
function renderPanels(card, groups) {
  const shown = Object.keys(groups);
  const box = el("div", "panels");
  const ruleCount = (card.rules || []).filter(r => r !== "remaining").length;
  const invalid = (card.rules || []).some(r => r !== "remaining" && M.ruleProblem(r));
  // a panel's name as shown: a dot when something of its own is set; Rules its count, red when a rule is invalid
  const label = id => {
    const span = el("span", "panel-name" + (id === "rules" && invalid ? " bad" : ""), M.panelNames[id]);
    if (id === "rules" && groups.rules && !M.isRemaining(card)) span.append(el("span", "panel-count", " " + ruleCount));
    if (M.panelSet(card, id)) span.append(el("span", "panel-dot", ""));
    return span;
  };
  const handle = (elem, id) => {
    elem.draggable = true;
    elem.title = "Drag to move this panel: onto another (tabs), onto a tab (a new tab), into a tab, or above or below another";
    elem.addEventListener("dragstart", e => {
      e.stopPropagation();
      e.dataTransfer.setData("text/panel", id);
      e.dataTransfer.effectAllowed = "move";
    });
  };
  const panelBox = (id, where) => {
    const p = el("div", "cpanel");
    p.dataset.panel = id;
    p.dataset.where = where;   // "own": on its own; "tab": one of several in a tab
    const head = el("div", "cpanel-head");
    head.append(label(id));
    handle(head, id);
    const body = el("div", "cpanel-body");
    body.append(...groups[id]);
    p.append(head, body);
    return p;
  };
  for (const item of arrangement) {
    if (item.panel) { if (shown.includes(item.panel)) box.append(panelBox(item.panel, "own")); continue; }
    const tabs = item.tabs.map(t => t.filter(id => shown.includes(id))).filter(t => t.length);
    if (!tabs.length) continue;
    const setKey = item.tabs.flat().join(","), tabKey = t => t.join(",");
    // the first tab until the user chooses another; a rule selected elsewhere: the tab with Rules
    let chosen = tabs.find(t => tabKey(t) === chosenTabs.get(setKey)) || tabs[0];
    if (revealRule && tabs.some(t => t.includes("rules"))) chosen = tabs.find(t => t.includes("rules"));
    const set = el("div", "ctabs");
    set.dataset.set = setKey;
    const line = el("div", "ctab-line");
    for (const t of tabs) {
      const b = el("button", "ctab" + (t === chosen ? " on" : ""));
      b.dataset.tab = t[0];
      if (t.length === 1) { b.append(label(t[0])); handle(b, t[0]); }
      else {
        b.append(el("span", "panel-name", M.tabName(t, shown)));
        if (t.some(id => M.panelSet(card, id))) b.append(el("span", "panel-dot", ""));
      }
      b.addEventListener("click", () => { chosenTabs.set(setKey, tabKey(t)); renderCardPane(); });
      line.append(b);
    }
    const content = el("div", "ctab-content");
    for (const id of chosen) {
      if (chosen.length === 1) {
        // one panel in the tab: its fields; its name is on the tab
        const p = el("div", "cpanel-body");
        p.dataset.panel = id;
        p.dataset.where = "tab";
        p.append(...groups[id]);
        content.append(p);
      } else content.append(panelBox(id, "tab"));
    }
    set.append(line, content);
    box.append(set);
  }
  // a dragged panel dropped: where it would go shown while dragging; Esc cancels (the drag's own)
  const clear = () => { for (const x of box.querySelectorAll(".drop-above, .drop-below, .drop-onto")) x.classList.remove("drop-above", "drop-below", "drop-onto"); };
  const targetOf = e => {
    const set = e.target.closest(".ctabs"), y = e.clientY;
    if (set) {
      const r = set.getBoundingClientRect();
      if (y - r.top < 8) return { elem: set, cls: "drop-above", t: { kind: "above", of: set.dataset.set.split(",")[0] } };
      if (r.bottom - y < 8) return { elem: set, cls: "drop-below", t: { kind: "below", of: set.dataset.set.split(",")[0] } };
      const tab = e.target.closest(".ctab");
      if (tab) return { elem: tab, cls: "drop-onto", t: { kind: "tab", of: tab.dataset.tab } };
      const inner = e.target.closest("[data-where='tab']");
      if (inner) {
        const ir = inner.getBoundingClientRect(), below = y > ir.top + ir.height / 2;
        return { elem: inner, cls: below ? "drop-below" : "drop-above", t: { kind: "inTab", of: inner.dataset.panel, side: below ? "below" : "above" } };
      }
      const last = [...set.querySelectorAll("[data-where='tab']")].pop();
      return last ? { elem: last, cls: "drop-below", t: { kind: "inTab", of: last.dataset.panel, side: "below" } } : null;
    }
    const p = e.target.closest(".cpanel[data-where='own']");
    if (!p) return null;
    const r = p.getBoundingClientRect(), edge = Math.min(14, r.height / 4);
    if (y - r.top < edge) return { elem: p, cls: "drop-above", t: { kind: "above", of: p.dataset.panel } };
    if (r.bottom - y < edge) return { elem: p, cls: "drop-below", t: { kind: "below", of: p.dataset.panel } };
    return { elem: p, cls: "drop-onto", t: { kind: "onto", of: p.dataset.panel } };
  };
  box.addEventListener("dragover", e => {
    if (!e.dataTransfer.types.includes("text/panel")) return;
    e.preventDefault();
    clear();
    const t = targetOf(e);
    if (t) t.elem.classList.add(t.cls);
  });
  box.addEventListener("dragleave", e => { if (!box.contains(e.relatedTarget)) clear(); });
  box.addEventListener("drop", e => {
    if (!e.dataTransfer.types.includes("text/panel")) return;
    e.preventDefault();
    clear();
    const id = e.dataTransfer.getData("text/panel"), t = targetOf(e);
    if (!t) return;
    arrangement = M.arrangePanel(arrangement, id, t.t);
    keepArrangement();
    renderCardPane();
  });
  box.addEventListener("dragend", clear);
  return box;
}

// How a card shows what it found or holds (plan 11 3.1): Shows; a row's per row and rows, a column's per column and
// columns; the rest beyond them; a holder's shown when; with templates, how they are picked.
function showFields(card, withRules, isMenu = false) {
  const fields = [];
  const select = (label, title, options, value, set) => {
    const sel = el("select");
    for (const [v, text] of options) { const o = el("option", "", text); o.value = v; sel.append(o); }
    sel.value = value;
    sel.addEventListener("change", () => { set(sel.value); changed(); });
    const row = el("label", "field");
    row.title = title;
    row.append(el("span", "", label), sel);
    return row;
  };
  const shows = withRules
    ? [["", "each a card of its own (the card multiplied)"], ["submenu", "in a submenu"], ["row", "side by side inside it"], ["column", "under each other inside it"]]
    : isMenu ? [["column", "under each other (in columns with a number per column)"], ["row", "side by side"]]
    : [["submenu", "in a submenu"], ["row", "side by side inside it"], ["column", "under each other inside it"]];
  fields.push(select("Shows", withRules ? "How what its rules find shows" : "How the cards it holds show", shows,
    card.show || (withRules ? "" : "column"), v => {
      if (v) card.show = v; else delete card.show;
      // shown inside it: its title above them is its own; it starts as its name (an empty title shows none)
      if ((v === "row" || v === "column") && card.title === undefined) card.title = card.card;
    }));
  const number = (key, label, placeholder) => textField(label, card[key] === undefined ? "" : String(card[key]), v => {
    const n = Math.round(Number(v.trim()));
    if (v.trim() && n >= 1) card[key] = n; else delete card[key];
    changed();
  }, placeholder);
  if (card.show === "row") fields.push(number("perRow", "Per row", "(as many as fit)"), number("rows", "Rows", "(as many as needed)"));
  if (card.show === "column") fields.push(number("perColumn", "Per column", "(all in one column)"), number("columns", "Columns", "(as many as needed)"));
  if ((card.show === "row" && card.perRow && card.rows) || (card.show === "column" && card.perColumn && card.columns))
    fields.push(select("The rest", "What does not fit", [["", "in a \"More\" submenu"], ["none", "left out"]], card.rest || "",
      v => { if (v) card.rest = v; else delete card.rest; }));
  if (withRules && card.show && card.show !== "item") {
    const row = select("Templates picked", "With more than one template: by the inner card's place (in turn), or by the rule that found it",
      [["", "by place, in turn"], ["rule", "by rule"]], card.templatesBy || "", v => { if (v) card.templatesBy = v; else delete card.templatesBy; });
    if (!Array.isArray(card.templates) || card.templates.length < 2) row.querySelector("select").disabled = true;
    fields.push(row);
  }
  // what depends on Shows under it, with a tree line
  asTree(fields);
  if (M.isHolder(card) && !isMenu)
    fields.push(select("Shown when", "When this card shows: something in it can be chosen, anything in it shows, or always",
      [["", "something in it can be chosen"], ["anyItem", "anything in it shows"], ["always", "always"]], card.shownWhen || "",
      v => { if (v) card.shownWhen = v; else delete card.shownWhen; }));
  return fields;
}

// Extra text at: above or below the title (a Names field)
function extraAtField(card) {
  const extraAt = el("select");
  for (const [v, label] of [["", "below the title"], ["above", "above the title"]]) {
    const o = el("option", "", label);
    o.value = v;
    extraAt.append(o);
  }
  extraAt.value = card.extraAt || "";
  extraAt.addEventListener("change", () => { if (extraAt.value) card.extraAt = extraAt.value; else delete card.extraAt; changed(); });
  const extraRow = el("label", "field");
  extraRow.append(el("span", "", "Placed"), extraAt);
  return extraRow;
}

// ---- a card's style (its look, how it sits and opens), copied and pasted onto other cards, also in another layout's
// window (the clipboard) ----

// The selected card (not the remaining card, which has no style of its own), or null.
function styledCard() {
  // a template selected (plan 11): the template itself, not its card
  const tm = /^(.*)~t(\d+)$/.exec(selectedId || "");
  if (tm) {
    const holder = M.find(linesOf(), tm[1]);
    return holder && Array.isArray(holder.card.templates) ? holder.card.templates[+tm[2]] || null : null;
  }
  const at = selectedId ? M.find(linesOf(), selectedId) : null;
  return at && !M.isRemaining(at.card) ? at.card : null;
}

async function copyStyle() {
  const card = styledCard();
  if (!card) return;
  try { await navigator.clipboard.writeText(M.clip("style", M.styleOf(card))); } catch (e) { /* not copied */ }
}

async function pasteStyle(text) {
  const card = styledCard();
  if (!card) return;
  if (text === undefined) { try { text = await navigator.clipboard.readText(); } catch (e) { return; } }
  if (M.paste(layout, linesOf(), text, null, card)) changed();
}

// What the clipboard holds of Dexmenu's ("card", "style", ...; "" for nothing).
async function clipboardType() {
  try { return M.clipType(await navigator.clipboard.readText()); } catch (e) { return ""; }
}

// The selected card copied (Ctrl+C does the same): a duplicate can be pasted elsewhere, also in another layout.
async function copyCard() {
  const at = selectedId ? M.find(linesOf(), selectedId) : null;
  if (!at || M.isRemaining(at.card)) return;
  try { await navigator.clipboard.writeText(M.clip("card", at.card)); } catch (e) { /* not copied */ }
}

// The copied card pasted as a duplicate: inside a card ({ into }) or at the top level at a line's place ({ index }).
async function pasteCardAt(where) {
  let text = "";
  try { text = await navigator.clipboard.readText(); } catch (e) { return; }
  const pasted = M.pasteCard(layout, linesOf(), text, where);
  if (!pasted) return;
  if (where.into) collapsed.delete(where.into);
  select(pasted.id, -1);
  changed();
}

// The selected template copied (plan 11): its texts, layout and style, to paste onto another card.
async function copyTemplate() {
  const t = /~t\d+$/.test(selectedId || "") ? styledCard() : null;
  if (!t) return;
  try { await navigator.clipboard.writeText(M.clip("template", t)); } catch (e) { /* not copied */ }
}

// A copied template added to a card's templates, then selected.
async function pasteTemplate(card, text) {
  if (text === undefined) { try { text = await navigator.clipboard.readText(); } catch (e) { return; } }
  if (!M.paste(layout, linesOf(), text, null, card)) return;
  select(card.id + "~t" + (card.templates.length - 1), -1);
  changed();
}

// A small right-click menu at x, y (page pixels): items [label, title, action, disabled], null a line between them;
// closed by a choice, a click elsewhere, Esc, or scrolling.
function showContextMenu(x, y, items) {
  closeContextMenu();
  const menu = el("div", "context-menu");
  menu.id = "contextMenu";
  for (const item of items) {
    if (!item) { menu.append(el("div", "context-line")); continue; }
    const [label, title, action, disabled] = item;
    const b = el("button", "", label);
    b.title = title;
    b.disabled = !!disabled;
    b.addEventListener("click", e => { e.stopPropagation(); closeContextMenu(); action(); });
    menu.append(b);
  }
  document.body.append(menu);
  // kept inside the window
  const r = menu.getBoundingClientRect();
  menu.style.left = Math.max(0, Math.min(x, innerWidth - r.width - 4)) + "px";
  menu.style.top = Math.max(0, Math.min(y, innerHeight - r.height - 4)) + "px";
  const first = menu.querySelector("button:not(:disabled)");
  if (first) first.focus();
}

// The cards view's right-click outside a card: "Paste card" at the top level, where clicked: in the header at the
// top, below the last line at the bottom, in the gutter or between lines at that place.
document.querySelector("#cardsPane .cards-wrap").addEventListener("contextmenu", async e => {
  if (!layout || e.target.closest(".card")) return;
  e.preventDefault();
  const x = e.clientX, y = e.clientY;
  let index = 0;
  if (!e.target.closest(".cards-main > h2")) {
    // the top-level lines above the click: the card goes after them
    for (const elem of document.querySelectorAll("#cards > .lines > [data-top]")) {
      const r = elem.getBoundingClientRect();
      if (r.top + r.height / 2 < y) index = +elem.dataset.top + 1;
    }
  }
  const type = await clipboardType();
  showContextMenu(x, y, [["Paste card here", "The copied card, as a line of its own at this place (Ctrl+V pastes after the selected card)",
    () => pasteCardAt({ index }), type !== "card"]]);
});
function closeContextMenu() {
  const m = document.getElementById("contextMenu");
  if (m) m.remove();
}
document.addEventListener("mousedown", e => { if (!e.target.closest("#contextMenu")) closeContextMenu(); }, true);
document.addEventListener("keydown", e => { if (e.key === "Escape") closeContextMenu(); }, true);
window.addEventListener("blur", closeContextMenu);
document.addEventListener("scroll", closeContextMenu, true);

// ---- the rules view --------------------------------------------------------------------------------------------

function summary(rule) {
  const show = m => {
    const k = Object.keys(m || {})[0];
    if (!k) return "?";
    if (k === "wildcard" && m.wildcard === "*") return "any";
    return (k === "any" ? "one of" : k) + " " + (k === "any" ? "[" + m.any.join(", ") + "]" : '"' + m[k] + '"');
  };
  let s;
  if (M.ruleType(rule) === "editMenu" || M.ruleType(rule) === "windowsMenu") {
    s = "Dexmenu: " + (rule.own === "editMenu" ? "Edit menu..." : "Windows' menu");
  } else if (M.ruleType(rule) === "usage") {
    s = (rule.used === "recent" ? "most recent" : "most used") + (rule.rank === undefined ? "" : " " + rule.rank);
  } else {
    s = "name " + show(rule.name);
    if (rule.path) s += ", in a submenu " + show(rule.path);
    else if (rule.scope === "anywhere") s += ", anywhere";
  }
  if (rule.states && rule.states.length === 1) s += ", " + rule.states[0] + " only";
  if (rule.also) s += ", also";
  if (rule.consume === false) s += ", not consumed";
  if (rule.skipDuplicates) s += ", skip duplicates";
  if (rule.latest !== undefined) s += ", latest " + rule.latest;
  if (rule.exclude) s = "exclude: " + s;
  return s;
}

function renderRules() {
  const list = $("rules");
  list.replaceChildren();
  M.ruleList(linesOf()).forEach((r, i) => {
    const classes = [];
    if (r.card.id === selectedId) classes.push("mine");   // the selected card's rules
    if (r.card.id === selectedId && r.index === selectedRule) classes.push("selected");
    if (r.rule.exclude) classes.push("exclude");
    const li = el("li", classes.join(" "));
    li.title = "Drag to change its place in the list, or onto a card: move (Shift: copy)";
    li.draggable = true;
    li.append(el("span", "card-name", r.card.card), ": " + summary(r.rule));
    const problem = M.ruleProblem(r.rule);
    if (problem) li.append(el("span", "problem", problem));
    li.addEventListener("click", () => select(r.card.id, r.index));
    li.addEventListener("dragstart", e => { e.dataTransfer.setData("text/rule", String(i)); startRuleDrag(e, r.card, r.index); });
    li.addEventListener("dragover", e => { if (e.dataTransfer.types.includes("text/rule")) { e.preventDefault(); li.classList.add("over"); } });
    li.addEventListener("dragleave", () => li.classList.remove("over"));
    li.addEventListener("drop", e => {
      e.preventDefault();
      li.classList.remove("over");
      const from = +e.dataTransfer.getData("text/rule");
      if (!Number.isNaN(from) && from !== i) { M.moveRule(linesOf(), from, from < i ? i - 1 : i); changed(); }
    });
    list.append(li);
  });
  const rest = [...M.cards(linesOf())].find(a => M.isRemaining(a.card));
  const last = el("li", "fixed", "Last, always: " + (rest ? rest.card.card : "the remaining card") + " takes every item no rule took");
  // a rule dropped here goes to the end of the list (before this line, which always stays last)
  const count = M.ruleList(linesOf()).length;
  last.addEventListener("dragover", e => { if (e.dataTransfer.types.includes("text/rule")) { e.preventDefault(); last.classList.add("over"); } });
  last.addEventListener("dragleave", () => last.classList.remove("over"));
  last.addEventListener("drop", e => {
    e.preventDefault();
    last.classList.remove("over");
    const from = +e.dataTransfer.getData("text/rule");
    if (!Number.isNaN(from) && from !== count - 1) { M.moveRule(linesOf(), from, count - 1); changed(); }
  });
  list.append(last);
}

// ---- the whole page ------------------------------------------------------------------------------------------------

function render() {
  if (!layout) return;
  $("cards").replaceChildren(renderMenuCard());
  placeToggles();
  renderCardPane();
  renderRules();
}

// The fold toggles in the gutter, each level with its card's title; placed again whenever the cards move (a render,
// the pane resized, a card's text wrapping differently).
function placeToggles() {
  const gutter = $("cardsGutter");
  for (const t of gutter.querySelectorAll(".fold, .rest-mark, .use-count, .line-grip")) t.remove();
  const top = gutter.getBoundingClientRect().top;
  // a plain row selected (a click in the gutter): a grip beside it, as high as the row, to drag it by
  const row = selectedId && $("cards").querySelector(`.row-holder[data-holder="${selectedId}"]`);
  if (row) {
    const r = row.getBoundingClientRect(), grip = el("div", "line-grip");
    grip.title = "Drag to move this row with its cards; Esc cancels";
    grip.draggable = true;
    grip.style.top = (r.top - top) + "px";
    grip.style.height = r.height + "px";
    grip.addEventListener("dragstart", e => {
      e.dataTransfer.setData("text/card", selectedId);
      e.dataTransfer.effectAllowed = "move";
    });
    gutter.append(grip);
  }
  // the remaining card: a coloured line beside it
  const rest = $("cards").querySelector(".card.remaining");
  if (rest) {
    const r = rest.getBoundingClientRect(), mark = el("div", "rest-mark");
    mark.title = "The remaining card";
    mark.style.top = (r.top - top) + "px";
    mark.style.height = r.height + "px";
    gutter.append(mark);
  }
  // cards with a menu side by side on a line share one toggle: it collapses them all while one is open, else expands
  // them all (a double click on a card still folds that card alone)
  const rows = new Map();
  for (const box of $("cards").querySelectorAll(".card[data-fold]")) {
    const y = Math.round(box.getBoundingClientRect().top - top);
    if (!rows.has(y)) rows.set(y, []);
    rows.get(y).push(box);
  }
  for (const [y, boxes] of rows) {
    const ids = boxes.map(b => b.dataset.id), folded = boxes.every(b => b.dataset.fold === "folded");
    const t = el("button", "toggle fold", folded ? "+" : "-");
    t.title = (folded ? "Expand " : "Collapse ") + ids.map(id => M.find(linesOf(), id)?.card.card || "").join(", ");
    t.style.top = (y + 5) + "px";
    t.addEventListener("click", () => { for (const id of ids) folded ? collapsed.delete(id) : collapsed.add(id); render(); });
    gutter.append(t);
  }
  // the use counts (plan 02 3.9): how often the items a card got in the preview were chosen; a card with a menu the
  // sum of what is in it; under its fold toggle when it has one
  for (const box of $("cards").querySelectorAll(".card[data-id]")) {
    const n = useCount(box.dataset.id);
    if (!n) continue;
    const c = el("div", "use-count", n >= 10000 ? Math.round(n / 1000) + "k" : String(n));
    c.title = `Chosen ${n} times in this kind of right-click`;
    c.style.top = (box.getBoundingClientRect().top - top + (box.dataset.fold ? 22 : 5)) + "px";
    gutter.append(c);
  }
}

// A card's use count: its own (counts, by card id), or for a card with a menu the sum of the cards in it.
function useCount(id) {
  const at = M.find(linesOf(), id);
  if (!at) return 0;
  const sum = card => (counts[card.id] || 0) +
    (M.isHolder(card) ? card.content.reduce((t, entry) => t + (M.isDividerEntry(entry) ? 0 : sum(entry)), 0) : 0);
  return sum(at.card);
}
new ResizeObserver(() => { if (layout) placeToggles(); }).observe($("cards"));

// A click in the gutter selects the row beside it (the innermost there: a row inside a card before the row holding
// that card), or the card alone on its line there; a row is then dragged by the grip that shows beside it.
$("cardsGutter").addEventListener("click", e => {
  if (!layout || e.target.closest("button, .line-grip")) return;
  let best = null;
  for (const row of $("cards").querySelectorAll(".line")) {
    const r = row.getBoundingClientRect();
    if (e.clientY >= r.top && e.clientY <= r.bottom && (!best || r.height < best.getBoundingClientRect().height)) best = row;
  }
  if (!best) return;
  const id = best.dataset.holder || best.querySelector(":scope > .card")?.dataset.id;
  if (id) select(id, -1);
});

function load(state) {
  kind = state.kind;   // chosen above the preview (the app)
  if (document.activeElement !== $("layoutName")) $("layoutName").value = state.name || "";
  Theme.show(state.theme);
  $("error").hidden = !state.error;
  $("error").textContent = state.error || "";
  if (state.layout === loadedText && layout) { render(); return; }   // the same file again (after a save)
  loadedText = state.layout;
  let older = false;
  try {
    const current = M.upToDate(JSON.parse(M.withoutComments(state.layout)));
    if (!current.layout) {
      // an older form: not converted here (that was done once by a script); not opened
      layout = null;
      $("cards").replaceChildren(el("div", "problem", current.error));
      return;
    }
    layout = M.ensureIds(current.layout);
    older = current.changed;
  } catch (e) {
    layout = null;
    $("cards").replaceChildren(el("div", "problem", "The layout is not valid JSON: " + e.message));
    return;
  }
  dirty = false;
  $("dirty").hidden = true;
  lastSent = JSON.stringify(layout, null, 2);
  history = [lastSent];   // a layout opened (or read again): Undo goes back no further
  future = [];
  if (older) {
    // an older file brought to the current form: a change, written with the next Save (nothing else rewrites it)
    lastSent = "";
    if (selectedId && !M.find(linesOf(), selectedId)) selectedId = null;
    changed();
    return;
  }
  if (lastSent !== state.layout.trim()) post({ type: "edit", layout: lastSent, quiet: true });   // ids added: the preview knows them
  if (selectedId && !M.find(linesOf(), selectedId)) selectedId = null;
  render();
}

async function askName() {
  const dialog = $("nameDialog");
  $("nameInput").value = "";
  dialog.showModal();
  return new Promise(resolve => dialog.addEventListener("close", () => resolve(dialog.returnValue === "ok" ? $("nameInput").value.trim() : ""), { once: true }));
}

// Save: under the name at the top (a new name renames the layout, the kinds set to it follow); Save as: a copy
// under a new name, which this window then edits; Close: the app asks to save unsaved changes.
$("save").addEventListener("click", async () => {
  let name = $("layoutName").value.trim();
  if (!name) name = await askName();
  if (name) post({ type: "save", name, layout: JSON.stringify(layout, null, 2) });
});
$("saveAs").addEventListener("click", async () => {
  const name = await askName();
  if (name) post({ type: "saveAs", name, layout: JSON.stringify(layout, null, 2) });
});
$("close").addEventListener("click", () => post({ type: "close" }));
withIcon($("addTop"), "+ Card");
$("addDivider").replaceChildren(dividerIcon(), document.createTextNode(" + Divider"));
$("addNote").replaceChildren(noteIcon(), document.createTextNode(" + Note"));
$("addNote").addEventListener("click", () => { if (layout) addAfterSelected(M.addNote(layout, linesOf())); });
$("addNote").addEventListener("dragstart", e => { e.dataTransfer.setData("text/card", "newnote"); e.dataTransfer.effectAllowed = "copy"; });
$("addDivider").addEventListener("click", () => { if (layout) addAfterSelected(M.addDivider(layout, linesOf(), null)); });
$("addSearch").addEventListener("click", () => {
  if (!layout) return;
  const d = M.addSearch(layout, linesOf());
  select(d.id, -1);
  changed();
  focusNew(d.id);
});
$("addDivider").addEventListener("dragstart", e => { e.dataTransfer.setData("text/divider", "new"); e.dataTransfer.effectAllowed = "copy"; });
$("addTop").addEventListener("click", () => { if (layout) addAfterSelected(M.addCard(layout, linesOf(), null)); });
$("addGroup").addEventListener("click", () => { if (layout) addAfterSelected(M.addGroup(layout, linesOf())); });
$("addGroup").addEventListener("dragstart", e => { e.dataTransfer.setData("text/card", "newgroup"); e.dataTransfer.effectAllowed = "copy"; });
$("addTop").addEventListener("dragstart", e => { e.dataTransfer.setData("text/card", "new"); e.dataTransfer.effectAllowed = "copy"; });
$("collapseAll").addEventListener("click", () => {
  if (!layout) return;
  for (const at of M.cards(linesOf())) if (M.isHolder(at.card)) collapsed.add(at.card.id);
  render();
});
$("expandAll").addEventListener("click", () => { collapsed.clear(); render(); });

// The splitters between the panes: a splitter changes only the pane on its left (and so the room of the preview on
// the right, which takes the rest). The rules pane, the cards pane and the card's panel keep the width they were
// dragged to (kept in this page's storage, a convenience). Each pane has a minimum; a drag stops there. When the
// window is too narrow for the kept widths, they shrink in proportion for now; the kept widths stay for a wider one.
(() => {
  const key = "dexmenu.paneWidths";
  const min = { rulesPane: 320, cardsPane: 520, cardPane: 400, previewPane: 300 };
  let wish = {};
  try { wish = JSON.parse(localStorage.getItem(key) || "{}"); } catch (e) { /* no storage: default widths */ }
  const left = ["rulesPane", "cardsPane", "cardPane"];
  const room = () => $("panes").clientWidth - min.previewPane -
    [...document.querySelectorAll("#panes > .splitter")].reduce((n, s) => n + s.getBoundingClientRect().width, 0);
  const set = (id, w) => { $(id).style.flex = w ? "0 0 " + Math.round(w) + "px" : ""; };

  function apply() {
    const w = {};
    for (const id of left) w[id] = wish[id] > 0 ? Math.max(min[id], wish[id]) : null;
    // too wide for the window: the excess taken from what each kept width has above its minimum, in proportion (so
    // no pane goes below its minimum and the total fits; the preview keeps its minimum)
    const kept = left.filter(id => w[id]);
    const others = left.filter(id => !w[id]).reduce((n, id) => n + min[id], 0);   // the panes without a kept width
    const excess = kept.reduce((n, id) => n + w[id], 0) + others - room();
    if (excess > 0) {
      const slack = kept.reduce((n, id) => n + (w[id] - min[id]), 0);
      for (const id of kept) w[id] = slack > excess ? w[id] - excess * (w[id] - min[id]) / slack : min[id];
    }
    for (const id of left) set(id, w[id]);
    // what is still too wide when laid out (rounding, a pane's own content): taken off the kept widths too
    const over = $("panes").scrollWidth - $("panes").clientWidth;
    if (over > 0)
      for (const id of kept) {
        const take = Math.min(over, w[id] - min[id]);
        if (take > 0) { set(id, w[id] - take); break; }
      }
  }

  for (const splitter of document.querySelectorAll("#panes > .splitter")) {
    const pane = splitter.previousElementSibling;
    splitter.addEventListener("pointerdown", e => {
      e.preventDefault();
      splitter.setPointerCapture(e.pointerId);
      splitter.classList.add("dragging");
      // the panes as they are now; during the drag only this one changes
      for (const id of left) { wish[id] = $(id).getBoundingClientRect().width; set(id, wish[id]); }
      const startX = e.clientX, startW = wish[pane.id];
      const others = left.filter(id => id !== pane.id).reduce((n, id) => n + wish[id], 0);
      const move = ev => {
        wish[pane.id] = Math.max(min[pane.id], Math.min(startW + ev.clientX - startX, room() - others));   // the preview keeps its minimum
        set(pane.id, wish[pane.id]);
      };
      const up = () => {
        splitter.classList.remove("dragging");
        splitter.removeEventListener("pointermove", move);
        splitter.removeEventListener("pointerup", up);
        try { localStorage.setItem(key, JSON.stringify(wish)); } catch (e) { /* not kept */ }
      };
      splitter.addEventListener("pointermove", move);
      splitter.addEventListener("pointerup", up);
    });
  }
  window.addEventListener("resize", apply);
  apply();
})();

// While dragging (a card, a divider, a rule, "+ Card"), the pointer near a pane's top or bottom edge scrolls that pane,
// faster the nearer the edge: the browser only scrolls the page itself, and the cards list grows long. Caught before
// the cards' own handlers (capture), which stop the event.
(() => {
  const edge = 48, fastest = 24;   // CSS pixels: the zone at each edge; the most it scrolls per event (dragover repeats)
  for (const id of ["rulesPane", "cardsPane", "cardPane"]) {
    const pane = $(id);
    pane.addEventListener("dragover", e => {
      const r = pane.getBoundingClientRect();
      const sticky = id === "cardsPane" ? pane.querySelector(".cards-main > h2").getBoundingClientRect().height : 0;
      const top = r.top + sticky, bottom = r.bottom;
      if (e.clientY < top + edge) pane.scrollTop -= Math.ceil(fastest * (top + edge - e.clientY) / edge);
      else if (e.clientY > bottom - edge) pane.scrollTop += Math.ceil(fastest * (e.clientY - (bottom - edge)) / edge);
    }, true);
  }
})();

// ---- the preview pane ------------------------------------------------------------------------------------------------

// Where the preview's area is (CSS pixels within the page): the app places the preview window there (it lies over the
// page; nothing of the page shows below it).
(() => {
  let last = "";
  const report = () => {
    const r = $("previewArea").getBoundingClientRect();
    const rect = { x: r.left, y: r.top, w: r.width, h: r.height };
    const text = JSON.stringify(rect);
    if (text !== last) { last = text; post({ type: "previewRect", ...rect }); }
  };
  new ResizeObserver(report).observe($("previewArea"));
  window.addEventListener("resize", report);
  setInterval(report, 500);   // also when it moves without changing size (a splitter, the bar wrapping)
  report();
})();

// The preview's bar: the kind of right-click, the folder and the item(s) in it (the app keeps them and sends them back).
function showPreviewBar(b) {
  const kindSel = $("pvKind");
  if (kindSel.options.length !== b.kinds.length)
    kindSel.replaceChildren(...b.kinds.map(k => { const o = el("option", "", k.name); o.value = k.kind; return o; }));
  kindSel.value = b.kind;
  $("pvFolder").textContent = b.folder || "";
  $("pvNoFolder").hidden = !b.folder;
  $("pvWhere").hidden = b.kind === "desktop";
  const one = $("pvItem"), many = $("pvItems");
  one.hidden = !(b.folder && b.pick === "one");
  many.hidden = !(b.folder && b.pick === "many");
  if (!one.hidden) {
    one.replaceChildren(...b.entries.map(n => { const o = el("option", "", n); o.value = n; return o; }));
    one.value = b.chosen[0] || "";
  }
  if (!many.hidden) {
    const n = b.chosen.length;
    $("pvItemsText").textContent = n === 0 ? "Choose items..." : n + (n === 1 ? " item: " : " items: ") + b.chosen.slice(0, 2).join(", ") + (n > 2 ? ", ..." : "");
    $("pvItemsList").replaceChildren(...b.entries.map(name => {
      const l = el("label"), cb = el("input");
      cb.type = "checkbox";
      cb.checked = b.chosen.includes(name);
      cb.addEventListener("change", () => post({ type: "pickItems",
        names: [...$("pvItemsList").querySelectorAll("input")].filter(c => c.checked).map(c => c.parentElement.textContent.trim()) }));
      l.append(cb, " " + name);
      return l;
    }));
  }
  $("pvLast").disabled = !b.last;
  $("pvNotMeant").hidden = !b.notMeant;
  $("pvNotMeant").textContent = `Not used here: this right-click gets ${b.used}. Which layout each right-click gets is set in the main window.`;
  $("pvError").hidden = !b.liveError;
  $("pvError").textContent = b.liveError || "";
}
$("pvKind").addEventListener("change", () => post({ type: "previewKind", kind: $("pvKind").value }));
$("pvPick").addEventListener("click", () => post({ type: "pickFolder" }));
$("pvNoFolder").addEventListener("click", () => post({ type: "noFolder" }));
$("pvItem").addEventListener("change", () => post({ type: "pickItems", names: [$("pvItem").value] }));
$("pvLast").addEventListener("click", () => post({ type: "last" }));
// Tab and Shift+Tab in the card panel: leaving a field writes it, which draws the panel anew (the field left is
// replaced), so the browser has no field to go on from. The field's place in the panel is kept, and focus goes to the
// field after it (Shift+Tab: before it) in the panel as drawn now.
function focusables(box) {
  return [...box.querySelectorAll("input, select, textarea, button")].filter(x => !x.disabled && x.offsetParent !== null);
}
document.addEventListener("keydown", e => {
  if (e.key !== "Tab") return;
  const box = $("card"), from = document.activeElement;
  if (!box.contains(from)) return;
  const place = focusables(box).indexOf(from);
  if (place < 0) return;
  const back = e.shiftKey;
  setTimeout(() => {
    const now = document.activeElement;
    if (now && now !== document.body && now.isConnected) return;   // nothing drawn anew: the browser went on itself
    const fields = focusables($("card"));
    const to = fields[Math.max(0, Math.min(fields.length - 1, place + (back ? -1 : 1)))];
    if (to) { to.focus(); if (to.select && to.type === "text") to.select(); }
  }, 0);
}, true);

// Where the last click was: Delete removes the selected card only when that was in the cards view (a Delete meant for
// a field's text, with the field not focused, then deletes nothing).
let lastClickInCards = false;
document.addEventListener("mousedown", e => { lastClickInCards = !!e.target.closest("#cardsPane"); }, true);
$("undo").addEventListener("click", undo);
$("redo").addEventListener("click", redo);
document.addEventListener("keydown", async e => {
  const typing = ["INPUT", "TEXTAREA", "SELECT"].includes(document.activeElement.tagName);
  if (typing || !layout) return;   // in a field its own undo (Ctrl+Z) and Delete
  if (e.ctrlKey && (e.key === "z" || e.key === "Z")) { e.preventDefault(); if (e.shiftKey) redo(); else undo(); return; }
  if (e.ctrlKey && (e.key === "y" || e.key === "Y")) { e.preventDefault(); redo(); return; }
  if (e.key === "Delete" && lastClickInCards && selectedId && M.deleteCard(linesOf(), selectedId)) {
    selectedId = null;
    changed();
    return;
  }
  // Ctrl+C / Ctrl+X / Ctrl+V (plan 05 3.6): a card, a divider or the selected rule, also between editor windows
  // (another layout); Ctrl+X then Ctrl+V is a move.
  if (!e.ctrlKey || !["c", "x", "v"].includes(e.key.toLowerCase())) return;
  e.preventDefault();
  const key = e.key.toLowerCase();
  // Ctrl+Shift+C / Ctrl+Shift+V: the selected card's style copied, or pasted onto it
  if (e.shiftKey && key === "c") { copyStyle(); return; }
  if (e.shiftKey && key === "v") { pasteStyle(); return; }
  const at = selectedId ? M.find(linesOf(), selectedId) : null;
  const div = selectedId ? M.findDivider(linesOf(), selectedId) : null;
  if (key === "c" && /~t\d+$/.test(selectedId || "")) { copyTemplate(); return; }   // a template selected: the template
  if (key === "c" || key === "x") {
    let text = null;
    if (at && selectedRule >= 0 && at.card.rules && at.card.rules[selectedRule] !== undefined && at.card.rules[selectedRule] !== "remaining")
      text = M.clip("rule", at.card.rules[selectedRule]);
    else if (at && !M.isRemaining(at.card)) text = M.clip("card", at.card);
    else if (div) text = M.clip("divider", div.entry);
    if (!text) return;
    await navigator.clipboard.writeText(text);
    if (key === "x") {
      if (text.includes('"dexmenu":"rule"')) { M.deleteRule(linesOf(), at.card, selectedRule); selectedRule = -1; }
      else if (div) { M.deleteDivider(linesOf(), selectedId); selectedId = null; }
      else if (M.deleteCard(linesOf(), selectedId)) selectedId = null;
      changed();
    }
    return;
  }
  let text = "";
  try { text = await navigator.clipboard.readText(); } catch (err) { return; }
  if (text.includes('"dexmenu":"style"')) { pasteStyle(text); return; }   // a style: onto the selected card
  if (M.clipType(text) === "template") {
    // a template: onto the selected card, or the card of the selected template
    const holder = M.find(linesOf(), (selectedId || "").replace(/~t\d+$/, ""));
    if (holder) pasteTemplate(holder.card, text);
    return;
  }
  const onto = at && !M.isHolder(at.card) && !M.isRemaining(at.card) ? at.card : null;
  const pasted = M.paste(layout, linesOf(), text, at ? selectedId : null, onto);
  if (!pasted) return;
  if (pasted.id) select(pasted.id, -1);
  changed();
});

chrome.webview.addEventListener("message", e => {
  const m = e.data;
  if (m.type === "state") load(m);
  else if (m.type === "previewBar") showPreviewBar(m);
  else if (m.type === "theme") Theme.show(m.theme);
  else if (m.type === "problem") { $("error").hidden = false; $("error").textContent = m.text; }
  else if (m.type === "preview") { $("error").hidden = !m.error; $("error").textContent = m.error || ""; }
  else if (m.type === "placed" && m.cardId) {
    if (m.event === 2) select(m.cardId, m.rule);
    else if (hoverId !== m.cardId) { hoverId = m.cardId; render(); }
  }
  else if (m.type === "counts") { counts = m.counts || {}; placeToggles(); }
  else if (m.type === "ruleStates") {
    if (m.states !== generalStates) { generalStates = m.states; renderCardPane(); }
  }
  else if (m.type === "palette") {
    const next = m.palette || {};
    if (JSON.stringify(next) !== JSON.stringify(palette)) { palette = next; renderCardPane(); }
  }
  else if (m.type === "saved") { dirty = false; $("dirty").hidden = true; }
  else if (m.type === "fonts") { fonts = m.fonts || []; renderCardPane(); }
  else if (m.type === "pickedImage" && pickedImage) { const f = pickedImage; pickedImage = null; f(m.path); }
  else if (m.type === "pickedNoteFile" && pickedNoteFile) { const f = pickedNoteFile; pickedNoteFile = null; f(m); }
});

// The layout editor (docs/plans/02-PLAN-own-menu.md 3.3, 3.5; plan 00 step 5). Two views of one layout: the cards
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
function linesOf() { return layout.lines; }

function changed() {
  dirty = true;
  $("dirty").hidden = false;
  const text = JSON.stringify(layout, null, 2);
  if (text !== lastSent) { lastSent = text; post({ type: "edit", layout: text }); }
  render();
}

// ---- the cards view --------------------------------------------------------------------------------------------

function ruleBadges(card) {
  return (card.rules || []).filter(r => r !== "remaining").map(r => el("span", "badge", "#" + r.priority));
}

function describeCard(card) {
  if (card.hidden && !M.isRemaining(card)) return "hidden: what it finds is left out of the menu";
  if (card.menu) return "a card with a menu";
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
  const isNew = id === "new";
  if (isNew) id = isDivider ? M.addDivider(layout, linesOf(), null).id : M.addCard(layout, linesOf(), null).id;
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
  box.append(el("span", "rule-line"), el("span", "text", entry.divider || ""), el("span", "rule-line"));
  if (!entry.divider) box.classList.add("plain");
  const actions = el("div", "card-actions");
  const x = el("button", "", "x");
  x.title = "Delete this divider";
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

function renderLines(lines, parentId) {
  const box = el("div", "lines");
  lines.forEach((entry, index) => {
    box.append(dropZone("gap", (id, isDiv) => isDiv ? M.moveDivider(linesOf(), id, parentId, index) : M.moveCard(linesOf(), id, parentId, index)));
    if (entry.divider !== undefined) { box.append(renderDivider(entry)); return; }
    if (!entry.line) return;
    const row = el("div", "line");
    for (const card of entry.line) row.append(renderCard(card));
    row.append(dropZone("line-end", (id, isDiv) => isDiv ? M.moveDivider(linesOf(), id, parentId, index + 1)
      : M.moveCard(linesOf(), id, parentId, index, true)));
    box.append(row);
  });
  box.append(dropZone("gap", (id, isDiv) => isDiv ? M.moveDivider(linesOf(), id, parentId, lines.length)
    : M.moveCard(linesOf(), id, parentId, lines.length)));
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
  const folded = !!card.menu && collapsed.has(card.id);
  if (card.menu) box.dataset.fold = folded ? "folded" : "open";
  const title = el("div", "title");
  title.append(el("span", "name", card.card));   // its own element, so a long name wraps inside the card
  title.append(...ruleBadges(card));
  const cardsIn = card.menu ? [...M.cards(card.menu)].length : 0;
  box.append(cardActions(card), title,
    el("div", "what", describeCard(card) + (folded ? ", " + cardsIn + (cardsIn === 1 ? " card" : " cards") + " folded" : "")));
  if (card.menu && !folded) box.append(renderLines(card.menu, card.id));
  box.addEventListener("click", e => { e.stopPropagation(); select(card.id, -1); });
  // a double click on a card with a menu (its own space, not a card in it or a button) folds or unfolds it
  box.addEventListener("dblclick", e => {
    e.stopPropagation();
    if (!card.menu || e.target.closest("button")) return;
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
      if (!card.menu && !M.isRemaining(card)) box.classList.add("over");
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
    b.title = tip;
    b.draggable = false;
    b.addEventListener("click", e => { e.stopPropagation(); fn(); });
    into.append(b);
  };
  action(adds, "+ beside", "A new card beside this one", () => addAndFocus(M.addCard(layout, linesOf(), null, card.id)), true);
  if (card.menu) action(adds, "+ in menu", "A new card at the end of its menu", () => {
    collapsed.delete(card.id);
    addAndFocus(M.addCard(layout, linesOf(), card.id));
  }, true);
  if (!card.menu && !M.isRemaining(card)) action(rest, "menu", "Make it a card with a menu (its rules go to a first card in it)", () => {
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

function matchEditor(match, onChange) {
  const kindSel = el("select");
  for (const k of M.matchKinds) { const o = el("option", "", k); o.value = k; kindSel.append(o); }
  const current = match ? Object.keys(match)[0] : "contains";
  kindSel.value = current;
  const input = el("input");
  input.type = "text";
  input.value = match ? (current === "any" ? (match.any || []).join(", ") : match[current]) : "";
  input.placeholder = current === "any" ? "one, two, three" : "text";
  const update = () => {
    const k = kindSel.value;
    onChange(k === "any" ? { any: input.value.split(",").map(s => s.trim()).filter(Boolean) } : { [k]: input.value });
  };
  kindSel.addEventListener("change", update);
  input.addEventListener("change", update);
  return [kindSel, input];
}

function ruleEditor(card, rule, index) {
  const box = el("div", "rule" + (index === selectedRule ? " selected" : ""));
  // Reordered by dragging its handle (the card's rules keep their places in the priority list, swapped among
  // themselves); numbered within the card, with its number in the priority list beside it.
  const handle = el("span", "handle", "::");
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
  const head = el("div", "row");
  const number = el("span", "number", (index + 1) + ".");
  const priority = el("span", "badge", "#" + rule.priority);
  priority.title = "Its place in the priority list";
  head.append(handle, number, priority, el("span", "", "Name"),
    ...matchEditor(rule.name, m => { rule.name = m; changed(); }));
  const where = el("div", "row");
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
  where.append(el("span", "", "Where"), placeSel);
  if (rule.path) where.append(...matchEditor(rule.path, m => { rule.path = m; changed(); }));
  const opts = el("div", "row");
  const states = rule.states || ["enabled", "disabled"];
  for (const s of ["enabled", "disabled"]) {
    const cb = el("input");
    cb.type = "checkbox";
    cb.checked = states.includes(s);
    cb.addEventListener("change", () => {
      const now = new Set(rule.states || ["enabled", "disabled"]);
      cb.checked ? now.add(s) : now.delete(s);
      rule.states = [...now];
      if (rule.states.length === 2) delete rule.states;
      changed();
    });
    const l = el("label");
    l.append(cb, " " + s);
    opts.append(l);
  }
  for (const [flag, label] of [["caseSensitive", "case sensitive"], ["also", "also when taken"],
    ["skipDuplicates", "skip duplicates (one per name)"]]) {
    const cb = el("input");
    cb.type = "checkbox";
    cb.checked = !!rule[flag];
    cb.addEventListener("change", () => { if (cb.checked) rule[flag] = true; else delete rule[flag]; changed(); });
    const l = el("label");
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
  const del = el("button", "", "Delete rule");
  del.addEventListener("click", () => { M.deleteRule(linesOf(), card, index); selectedRule = -1; changed(); });
  opts.append(del);
  box.append(head, where, opts);
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
  if (div) {
    // a divider: its text and where the text goes; its look (height, colours) comes with the themes
    $("cardHeading").textContent = "A divider";
    const box = $("card");
    box.replaceChildren(textField("Text", div.entry.divider, v => { div.entry.divider = v; changed(); }, "(none: a plain line)"));
    const row = el("label", "field");
    const align = el("select");
    for (const a of ["left", "center", "right"]) { const o = el("option", "", a); o.value = a; align.append(o); }
    align.value = div.entry.align || "left";
    align.addEventListener("change", () => { if (align.value === "left") delete div.entry.align; else div.entry.align = align.value; changed(); });
    row.append(el("span", "", "Text aligned"), align);
    box.append(row);
    return;
  }
  const at = selectedId ? M.find(linesOf(), selectedId) : null;
  if (!at) {
    $("cardHeading").textContent = "Card";
    $("card").replaceChildren(el("div", "hint", "Select a card to edit it and its rules."));
    return;
  }
  const card = at.card;
  $("cardHeading").textContent = M.isRemaining(card) ? "The remaining card" : card.menu ? "A card with a menu" : "A card with rules";
  const box = $("card");
  box.replaceChildren();
  box.append(textField("Name", card.card, v => { card.card = v || "Card"; changed(); }));
  box.append(textField("Title", card.title, v => { if (v) card.title = v; else delete card.title; changed(); },
    card.menu ? "(its name)" : "(the item's own text for one item)"));
  box.append(textField("Extra text", card.extra, v => { if (v) card.extra = v; else delete card.extra; changed(); },
    "(shown with the look, step 6)"));
  // the hint on hover: a text in place of the item's own hint, or a regex on it (so it can be added to)
  const hint = card.hint;
  box.append(textField("Hint", typeof hint === "string" ? hint : "", v => {
    if (v) card.hint = v; else if (typeof card.hint === "string") delete card.hint;
    changed();
  }, "(the item's own hint)"));
  box.append(textField("Hint regex", hint && typeof hint === "object" ? hint.regex : "", v => {
    if (v) card.hint = { regex: v, replace: (card.hint && typeof card.hint === "object" && card.hint.replace) || "" };
    else if (card.hint && typeof card.hint === "object") delete card.hint;
    changed();
  }, "e.g. ^(.*)$ to add to it"), textField("... replace with", hint && typeof hint === "object" ? hint.replace : "", v => {
    if (card.hint && typeof card.hint === "object") { card.hint.replace = v; changed(); }
  }, "e.g. $1 (via LexPen)"));
  // the comment: for the editor only, never in the menu
  const comment = el("label", "field");
  const area = el("textarea");
  area.rows = 3;
  area.value = card.comment || "";
  area.placeholder = "(only here, never in the menu)";
  area.addEventListener("change", () => { if (area.value) card.comment = area.value; else delete card.comment; changed(); });
  comment.append(el("span", "", "Comment"), area);
  box.append(comment);
  if (!M.isRemaining(card)) {
    const cb = el("input");
    cb.type = "checkbox";
    cb.checked = !!card.hidden;
    cb.addEventListener("change", () => { if (cb.checked) card.hidden = true; else delete card.hidden; changed(); });
    const l = el("label", "field");
    l.title = "Its rules still take their items, so they show nowhere, not in the remaining card either";
    l.append(el("span", "", "Hidden"), el("span"));
    l.lastChild.append(cb, " not shown: what it finds is left out of the menu");
    box.append(l);
  }
  if (!card.menu && !M.isRemaining(card)) {
    // one item per name over all its rules (Windows 11 shows some items twice: a newer and an older copy)
    const cb = el("input");
    cb.type = "checkbox";
    cb.checked = !!card.skipDuplicates;
    cb.addEventListener("change", () => { if (cb.checked) card.skipDuplicates = true; else delete card.skipDuplicates; changed(); });
    const l = el("label", "field");
    l.title = "Of the items its rules find with the same name, only the first shows; the others show nowhere";
    l.append(el("span", "", "Duplicates"), el("span"));
    l.lastChild.append(cb, " skip: one item per name");
    box.append(l);
  }
  if (!card.menu)
    box.append(textField("Rename (regex)", card.rename && card.rename.regex, v => {
      if (v) card.rename = { regex: v, replace: (card.rename && card.rename.replace) || "" }; else delete card.rename;
      changed();
    }), textField("... replace with", card.rename && card.rename.replace, v => {
      if (card.rename) { card.rename.replace = v; changed(); }
    }));

  const actions = el("div", "actions");
  const button = (label, fn) => { const b = el("button", "", label); b.addEventListener("click", fn); actions.append(b); };
  if (!card.menu && !M.isRemaining(card))
    button("+ Rule", () => { M.addRule(linesOf(), card); selectedRule = card.rules.length - 1; changed(); });
  box.append(actions);
  if (!card.menu && !M.isRemaining(card)) (card.rules || []).forEach((r, i) => box.append(ruleEditor(card, r, i)));
  if (M.isRemaining(card)) box.append(el("div", "what", "Every item of Windows' menu that no rule took is placed here, each a card of its own, with its submenu. It can be moved, also into a card with a menu, but not deleted."));
}

// ---- the rules view --------------------------------------------------------------------------------------------

function summary(rule) {
  const show = m => { const k = Object.keys(m || {})[0]; return k ? k + " " + (k === "any" ? "[" + m.any.join(", ") + "]" : '"' + m[k] + '"') : "?"; };
  let s = "name " + show(rule.name);
  if (rule.path) s += ", in a submenu " + show(rule.path);
  else if (rule.scope === "anywhere") s += ", anywhere";
  if (rule.states && rule.states.length === 1) s += ", " + rule.states[0] + " only";
  if (rule.also) s += ", also";
  if (rule.consume === false) s += ", not consumed";
  if (rule.skipDuplicates) s += ", skip duplicates";
  return s;
}

function renderRules() {
  const list = $("rules");
  list.replaceChildren();
  M.ruleList(linesOf()).forEach((r, i) => {
    const classes = [];
    if (r.card.id === selectedId) classes.push("mine");   // the selected card's rules
    if (r.card.id === selectedId && r.index === selectedRule) classes.push("selected");
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
  $("cards").replaceChildren(renderLines(linesOf(), null));
  placeToggles();
  renderCardPane();
  renderRules();
}

// The fold toggles in the gutter, each level with its card's title; placed again whenever the cards move (a render,
// the pane resized, a card's text wrapping differently).
function placeToggles() {
  const gutter = $("cardsGutter");
  for (const t of gutter.querySelectorAll(".fold, .rest-mark")) t.remove();
  const top = gutter.getBoundingClientRect().top;
  // the remaining card: a coloured line beside it
  const rest = $("cards").querySelector(".card.remaining");
  if (rest) {
    const r = rest.getBoundingClientRect(), mark = el("div", "rest-mark");
    mark.title = "The remaining card";
    mark.style.top = (r.top - top) + "px";
    mark.style.height = r.height + "px";
    gutter.append(mark);
  }
  for (const box of $("cards").querySelectorAll(".card[data-fold]")) {
    const id = box.dataset.id, folded = box.dataset.fold === "folded";
    const t = el("button", "toggle fold", folded ? "+" : "-");
    t.title = (folded ? "Expand " : "Collapse ") + (M.find(linesOf(), id)?.card.card || "");
    t.style.top = (box.getBoundingClientRect().top - top + 5) + "px";
    t.addEventListener("click", () => { folded ? collapsed.delete(id) : collapsed.add(id); render(); });
    gutter.append(t);
  }
}
new ResizeObserver(() => { if (layout) placeToggles(); }).observe($("cards"));

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
$("addDivider").addEventListener("click", () => {
  if (!layout) return;
  const d = M.addDivider(layout, linesOf(), null);
  select(d.id, -1);
  changed();
  focusNew(d.id);
});
$("addDivider").addEventListener("dragstart", e => { e.dataTransfer.setData("text/divider", "new"); e.dataTransfer.effectAllowed = "copy"; });
$("addTop").addEventListener("click", () => { if (layout) addAndFocus(M.addCard(layout, linesOf(), null)); });
$("addTop").addEventListener("dragstart", e => { e.dataTransfer.setData("text/card", "new"); e.dataTransfer.effectAllowed = "copy"; });
$("collapseAll").addEventListener("click", () => {
  if (!layout) return;
  for (const at of M.cards(linesOf())) if (at.card.menu) collapsed.add(at.card.id);
  render();
});
$("expandAll").addEventListener("click", () => { collapsed.clear(); render(); });

// The splitters between the panes: dragging one gives the pane on its left a fixed width; the last pane takes the rest.
// The widths are kept in this page's storage (a convenience: without it the panes start at their default widths).
(() => {
  const key = "dexmenu.paneWidths";
  // a dragged width is the pane's wish; it shrinks when the window is too narrow for all, so no pane runs off
  const fix = (pane, w) => { pane.style.flex = "0 1 " + Math.round(w) + "px"; };
  try {
    const saved = JSON.parse(localStorage.getItem(key) || "{}");
    for (const [id, w] of Object.entries(saved)) if ($(id) && w > 0) fix($(id), w);
  } catch (e) { /* no storage: default widths */ }
  for (const splitter of document.querySelectorAll("#panes > .splitter")) {
    const pane = splitter.previousElementSibling;
    splitter.addEventListener("pointerdown", e => {
      e.preventDefault();
      splitter.setPointerCapture(e.pointerId);
      splitter.classList.add("dragging");
      const startX = e.clientX, startW = pane.getBoundingClientRect().width;
      const move = ev => fix(pane, Math.max(160, Math.min(startW + ev.clientX - startX, window.innerWidth - 320)));
      const up = () => {
        splitter.classList.remove("dragging");
        splitter.removeEventListener("pointermove", move);
        splitter.removeEventListener("pointerup", up);
        try {
          const saved = JSON.parse(localStorage.getItem(key) || "{}");
          saved[pane.id] = pane.getBoundingClientRect().width;
          localStorage.setItem(key, JSON.stringify(saved));
        } catch (e) { /* not kept */ }
      };
      splitter.addEventListener("pointermove", move);
      splitter.addEventListener("pointerup", up);
    });
  }
})();
document.addEventListener("keydown", async e => {
  const typing = ["INPUT", "TEXTAREA", "SELECT"].includes(document.activeElement.tagName);
  if (typing || !layout) return;
  if (e.key === "Delete" && selectedId && M.deleteCard(linesOf(), selectedId)) {
    selectedId = null;
    changed();
    return;
  }
  // Ctrl+C / Ctrl+X / Ctrl+V (plan 05 3.6): a card, a divider or the selected rule, also between editor windows
  // (another layout); Ctrl+X then Ctrl+V is a move.
  if (!e.ctrlKey || !["c", "x", "v"].includes(e.key.toLowerCase())) return;
  e.preventDefault();
  const key = e.key.toLowerCase();
  const at = selectedId ? M.find(linesOf(), selectedId) : null;
  const div = selectedId ? M.findDivider(linesOf(), selectedId) : null;
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
  const onto = at && !at.card.menu && !M.isRemaining(at.card) ? at.card : null;
  const pasted = M.paste(layout, linesOf(), text, at ? selectedId : null, onto);
  if (!pasted) return;
  if (pasted.id) select(pasted.id, -1);
  changed();
});

chrome.webview.addEventListener("message", e => {
  const m = e.data;
  if (m.type === "state") load(m);
  else if (m.type === "theme") Theme.show(m.theme);
  else if (m.type === "problem") { $("error").hidden = false; $("error").textContent = m.text; }
  else if (m.type === "preview") { $("error").hidden = !m.error; $("error").textContent = m.error || ""; }
  else if (m.type === "placed" && m.cardId) {
    if (m.event === 2) select(m.cardId, m.rule);
    else if (hoverId !== m.cardId) { hoverId = m.cardId; render(); }
  }
  else if (m.type === "saved") { dirty = false; $("dirty").hidden = true; }
});

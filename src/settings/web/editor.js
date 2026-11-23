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
  if (M.isNote(card)) return "a note: shown as text, no button";
  if (M.isOwn(card)) return "Dexmenu's own item: " + (card.own === "windowsMenu" ? "shows Windows' menu" : "opens this editor");
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
  const isNew = id === "new" || id === "newnote" || id === "newmostused";   // "+ Card", "+ Divider", "+ Note", "+ Most used"
  if (id === "newnote") id = M.addNote(layout, linesOf()).id;
  else if (id === "newmostused") id = M.addMostUsed(layout, linesOf()).id;
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
  if (entry.mostUsed || entry.search) {
    box.classList.add("mostused");
    box.append(el("span", "text", entry.search ? "Search box: what is typed searches every item"
      : "Most used row: the items chosen most, side by side"));
  } else {
    box.append(el("span", "rule-line"), el("span", "text", entry.divider || ""), el("span", "rule-line"));
    if (!entry.divider) box.classList.add("plain");
  }
  const actions = el("div", "card-actions");
  const x = el("button", "", "x");
  x.title = entry.search ? "Delete the search box" : entry.mostUsed ? "Delete the most used row" : "Delete this divider";
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
    if (entry.divider !== undefined || entry.mostUsed || entry.search) { box.append(renderDivider(entry)); return; }
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
  // its own element, so a long name wraps inside the card; a note shows its text (its first lines)
  title.append(M.isNote(card) ? el("span", "name note-text align-" + (card.align || "left"), card.note || "(empty)")
    : el("span", "name", card.card));
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
      if (!card.menu && !M.isRemaining(card) && !M.isNote(card) && !M.isOwn(card)) box.classList.add("over");
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
  if (!card.menu && !M.isRemaining(card) && !M.isNote(card) && !M.isOwn(card)) action(rest, "menu", "Make it a card with a menu (its rules go to a first card in it)", () => {
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

// A card's size on its line (plan 03 3.5): its share of the width, a minimum width, a height in lines, and how it fits
// a taller line. Empty: the default (weight 1, no minimum, its content's height, as the line says).
function sizeFields(card) {
  const number = (name, label, placeholder) => textField(label, card[name] === undefined ? "" : String(card[name]), v => {
    const n = Number(v.trim());
    if (v.trim() && n > 0) card[name] = n; else delete card[name];
    changed();
  }, placeholder);
  const fit = el("select");
  for (const [v, label] of [["", "as its line says (stretched)"], ["stretch", "stretched to the line"], ["top", "at the top"],
    ["center", "in the middle"], ["bottom", "at the bottom"]]) {
    const o = el("option", "", label);
    o.value = v;
    fit.append(o);
  }
  fit.value = card.cardFit || "";
  fit.addEventListener("change", () => { if (fit.value) card.cardFit = fit.value; else delete card.cardFit; changed(); });
  const fitRow = el("label", "field");
  fitRow.title = "Where a card lower than its line stands in it";
  fitRow.append(el("span", "", "Fit in line"), fit);
  // its title wrapping over more lines: within the height when one is set, else the card as high as it needs
  const wrap = el("input");
  wrap.type = "checkbox";
  wrap.checked = !!card.wrap;
  wrap.addEventListener("change", () => { if (wrap.checked) card.wrap = true; else delete card.wrap; changed(); });
  const wrapRow = el("label", "field");
  wrapRow.title = "The title wraps over more lines: within Height when it is set (the last line cut with ...), else the card is as high as its lines";
  wrapRow.append(el("span", "", "Wrap"), el("span"));
  wrapRow.lastChild.append(wrap, " the title over more lines");
  return [number("weight", "Weight", "1: its share of the line's width"),
    number("minWidth", "Min width", "(none) the line wraps when it does not fit"),
    number("height", "Height", "(its content) in lines of text"), wrapRow, fitRow];
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
  intensityBox.prepend("Intensity ");
  opacityBox.prepend(overrule, " Opacity ");
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
function colorField(label, get, set, gradients = false) {
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
    for (const [v, text] of [["colour", "a colour"], ...(gradients ? [["gradient", "a gradient"]] : []), ["json", "other (JSON)"]]) {
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
      else state = { kind: "json", text: current.ok && current.value !== undefined ? JSON.stringify(current.value) : "" };
      if (state.kind === "json" && !state.text) body.replaceChildren(...build());   // nothing to write yet
      else commit();
    });
    const first = el("div", "color-row");
    first.append(kind);
    if (state.kind === "colour") {
      first.append(colorControls(state.colour, true, commit));
      return [first];
    }
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
    const angleBox = el("label", "slider");
    angleBox.append("Angle ", angle);
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

// A card's own look over the theme's (plan 03 3.6): its colours as pickers (colorField), the hover background the
// same; the radius a number.
function lookFields(card) {
  const own = name => ({ get: () => card[name], set: v => { if (v === undefined) delete card[name]; else card[name] = v; } });
  const hover = {
    get: () => card.hover && card.hover.background,
    set: v => {
      if (v === undefined) { if (card.hover) { delete card.hover.background; if (!Object.keys(card.hover).length) delete card.hover; } }
      else card.hover = Object.assign(card.hover || {}, { background: v });
    }
  };
  const extraAt = el("select");
  for (const [v, label] of [["", "below the title"], ["above", "above the title"]]) {
    const o = el("option", "", label);
    o.value = v;
    extraAt.append(o);
  }
  extraAt.value = card.extraAt || "";
  extraAt.addEventListener("change", () => { if (extraAt.value) card.extraAt = extraAt.value; else delete card.extraAt; changed(); });
  const extraRow = el("label", "field");
  extraRow.append(el("span", "", "Extra text at"), extraAt);
  return [extraRow,
    colorField("Background", own("background").get, own("background").set, true),
    colorField("Text colour", own("foreground").get, own("foreground").set),
    colorField("Border", own("border").get, own("border").set),
    textField("Radius", card.radius === undefined ? "" : String(card.radius), v => {
      const n = Number(v.trim());
      if (v.trim() && n >= 0) card.radius = n; else delete card.radius;
      changed();
    }, "(the theme's) corners, in DIP"),
    colorField("Hover background", hover.get, hover.set, true)];
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
  // the rule's type (plan 09 3.3): Name or Usage, each with its own group of fields; only the chosen one shown
  const typeSel = el("select");
  for (const [t, label] of [["name", "Name"], ["usage", "Usage"]]) { const o = el("option", "", label); o.value = t; typeSel.append(o); }
  typeSel.value = M.ruleType(rule);
  typeSel.title = "What the rule finds items by: their name, or their use (the most used or most recently used)";
  typeSel.addEventListener("change", () => { M.setRuleType(rule, typeSel.value); changed(); });
  head.append(handle, number, priority, typeSel);
  const group = el("div", "rulegroup");
  if (M.ruleType(rule) === "usage") {
    const row = el("div", "row");
    const usedSel = el("select");
    for (const [u, label] of [["most", "most used"], ["recent", "most recently used"]]) { const o = el("option", "", label); o.value = u; usedSel.append(o); }
    usedSel.value = rule.used === "recent" ? "recent" : "most";
    usedSel.addEventListener("change", () => { rule.used = usedSel.value; changed(); });
    const rank = el("input");
    rank.type = "text";
    rank.className = "rank";
    rank.placeholder = "all";
    rank.title = "Empty: all of them, in order; a number from 1 (3: the third); a range (1-3), or from high to low (3-1: the same in reverse)";
    rank.value = rule.rank === undefined ? "" : String(rule.rank);
    rank.addEventListener("change", () => {
      const v = rank.value.trim();
      if (v === "") delete rule.rank;
      else rule.rank = /^\d+$/.test(v) ? +v : v;
      changed();
    });
    row.append(el("span", "", "Finds the"), usedSel, el("span", "", "Rank"), rank);
    group.append(row);
  } else {
    const nameRow = el("div", "row");
    nameRow.append(...matchEditor(rule.name, m => { rule.name = m; changed(); }));
    const cs = el("input");
    cs.type = "checkbox";
    cs.checked = !!rule.caseSensitive;
    cs.addEventListener("change", () => { if (cs.checked) rule.caseSensitive = true; else delete rule.caseSensitive; changed(); });
    const csl = el("label");
    csl.append(cs, " case sensitive");
    nameRow.append(csl);
    group.append(nameRow);
  }
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
  if (M.ruleType(rule) === "name") group.append(where);
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
  for (const [flag, label] of [["also", "also when taken"],
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
  box.append(head, group, opts);
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
  if (div && div.entry.mostUsed) {
    $("cardHeading").textContent = "The most used row";
    $("card").replaceChildren(el("p", "hint", "The items chosen most in this kind of right-click, side by side, most " +
      "first; also items inside submenus. How many: in the main window. Empty until items have been chosen."));
    return;
  }
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
  if (M.isNote(card)) {
    // a note: its text only (several lines; no name, rules or menu)
    $("cardHeading").textContent = "A note";
    const area = el("textarea");
    area.rows = 6;
    area.value = card.note || "";
    area.placeholder = "(empty: a space in the menu)";
    area.addEventListener("change", () => { card.note = area.value; changed(); });
    const row = el("label", "field");
    row.append(el("span", "", "Text"), area);
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
    $("card").replaceChildren(row, placeRow, ...sizeFields(card),
      el("div", "hint", "A note is no button: it is shown as text, with nothing to click."));
    return;
  }
  if (M.isOwn(card)) {
    // Dexmenu's own item: which one, its title and icon; no rules
    $("cardHeading").textContent = "Dexmenu's own item";
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
    $("card").replaceChildren(row,
      textField("Title", card.card, v => { card.card = v || (card.own === "windowsMenu" ? "Windows' menu" : "Edit menu..."); changed(); }),
      textField("Icon", card.icon, v => { if (v.trim()) card.icon = v.trim(); else delete card.icon; changed(); }, "(none) e.g. E70F"),
      textField("Extra text", card.extra, v => { if (v) card.extra = v; else delete card.extra; changed(); },
        "(none) a smaller text with the title"),
      ...sizeFields(card), ...lookFields(card),
      el("div", "hint", "Shown where it stands in the layout; a layout without it does not show it."));
    return;
  }
  $("cardHeading").textContent = M.isRemaining(card) ? "The remaining card" : card.menu ? "A card with a menu" : "A card with rules";
  const box = $("card");
  box.replaceChildren();
  box.append(textField("Name", card.card, v => { card.card = v || "Card"; changed(); }));
  box.append(textField("Title", card.title, v => { if (v) card.title = v; else delete card.title; changed(); },
    card.menu ? "(its name)" : "(the item's own text for one item)"));
  // its icon (plan 02 3.8): a glyph of Segoe Fluent Icons by its code point, or an icon in a file; else the item's own
  if (!M.isRemaining(card)) box.append(textField("Icon", card.icon, v => { if (v.trim()) card.icon = v.trim(); else delete card.icon; changed(); },
    "(the item's own) e.g. E8C8, or shell32.dll,4"));
  box.append(textField("Extra text", card.extra, v => { if (v) card.extra = v; else delete card.extra; changed(); },
    "(none) a smaller text with the title"));
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
  // how what opens from this card opens: as set for every menu (main window), or its own way
  {
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
    row.title = card.menu ? "How this card's menu opens" : "How the submenus of the items this card shows open";
    row.append(el("span", "", "Submenus open"), way);
    box.append(row);
  }
  // its size on its line and its own look; the remaining card's items each take a line of their own, in their own look
  if (!M.isRemaining(card)) box.append(...sizeFields(card), ...lookFields(card));
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
    // what it finds as buttons inside it, a found submenu unfolded (plan 02 3.3)
    const bt = el("input");
    bt.type = "checkbox";
    bt.checked = !!card.buttons;
    bt.addEventListener("change", () => { if (bt.checked) card.buttons = true; else delete card.buttons; changed(); });
    const lb = el("label", "field");
    lb.title = "What it finds shows as buttons inside it, side by side; an item with a submenu shows the items of that submenu";
    lb.append(el("span", "", "Items as buttons"), el("span"));
    lb.lastChild.append(bt, " inside the card");
    box.append(lb);
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
  let s;
  if (M.ruleType(rule) === "usage") {
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
  for (const t of gutter.querySelectorAll(".fold, .rest-mark, .use-count")) t.remove();
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
    (card.menu ? card.menu.reduce((t, entry) => t + (entry.line ? entry.line.reduce((u, c) => u + sum(c), 0) : 0), 0) : 0);
  return sum(at.card);
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
$("addNote").replaceChildren(noteIcon(), document.createTextNode(" + Note"));
$("addOwn").addEventListener("click", () => { if (layout) addAndFocus(M.addOwn(layout, linesOf())); });
$("addNote").addEventListener("click", () => { if (layout) addAndFocus(M.addNote(layout, linesOf())); });
$("addNote").addEventListener("dragstart", e => { e.dataTransfer.setData("text/card", "newnote"); e.dataTransfer.effectAllowed = "copy"; });
$("addDivider").addEventListener("click", () => {
  if (!layout) return;
  const d = M.addDivider(layout, linesOf(), null);
  select(d.id, -1);
  changed();
  focusNew(d.id);
});
$("addSearch").addEventListener("click", () => {
  if (!layout) return;
  const d = M.addSearch(layout, linesOf());
  select(d.id, -1);
  changed();
  focusNew(d.id);
});
$("addMostUsed").addEventListener("click", () => {
  if (!layout) return;
  const d = M.addMostUsed(layout, linesOf());
  select(d.id, -1);
  changed();
  focusNew(d.id);
});
$("addMostUsed").addEventListener("dragstart", e => { e.dataTransfer.setData("text/divider", "newmostused"); e.dataTransfer.effectAllowed = "copy"; });
$("addDivider").addEventListener("dragstart", e => { e.dataTransfer.setData("text/divider", "new"); e.dataTransfer.effectAllowed = "copy"; });
$("addTop").addEventListener("click", () => { if (layout) addAndFocus(M.addCard(layout, linesOf(), null)); });
$("addTop").addEventListener("dragstart", e => { e.dataTransfer.setData("text/card", "new"); e.dataTransfer.effectAllowed = "copy"; });
$("collapseAll").addEventListener("click", () => {
  if (!layout) return;
  for (const at of M.cards(linesOf())) if (at.card.menu) collapsed.add(at.card.id);
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
  else if (m.type === "previewBar") showPreviewBar(m);
  else if (m.type === "theme") Theme.show(m.theme);
  else if (m.type === "problem") { $("error").hidden = false; $("error").textContent = m.text; }
  else if (m.type === "preview") { $("error").hidden = !m.error; $("error").textContent = m.error || ""; }
  else if (m.type === "placed" && m.cardId) {
    if (m.event === 2) select(m.cardId, m.rule);
    else if (hoverId !== m.cardId) { hoverId = m.cardId; render(); }
  }
  else if (m.type === "counts") { counts = m.counts || {}; placeToggles(); }
  else if (m.type === "palette") {
    const next = m.palette || {};
    if (JSON.stringify(next) !== JSON.stringify(palette)) { palette = next; renderCardPane(); }
  }
  else if (m.type === "saved") { dirty = false; $("dirty").hidden = true; }
});

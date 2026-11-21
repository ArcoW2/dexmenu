// The layout editor (docs/plans/02-PLAN-own-menu.md 3.3, 3.5; plan 00 step 5). Two views of one layout: the cards
// (a tree of lines and submenus, dragged around; a card selected shows its name, title, extra text and rules) and the
// rules in priority order (dragged to change it). Every change goes to the app at once ({ type: "edit", layout }),
// which has the DLL draw the preview from it; saving writes the file. The app sends:
//   { type: "state", kind, kindName, layout, source, name, layouts, active, error }   a layout (re)loaded
//   { type: "preview", error }                                                      the preview of an edit
//   { type: "placed", event, cardId, rule }      the preview: an item hovered (1) or clicked (2): who placed it
// and gets { type: "edit" | "save" | "open" | "activate" | "mark", ... } back.
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
let dirty = false;
let lastSent = "";
let loadedText = "";

function el(tag, cls, text) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text !== undefined) e.textContent = text;
  return e;
}

// The lines of the kind being edited: its own, or the default's.
function linesOf() { return Array.isArray(layout[kind]) ? layout[kind] : layout.default; }

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
    onDrop(e.dataTransfer.getData("text/card"));
  });
  return z;
}

function renderLines(lines, parentId) {
  const box = el("div", "lines");
  lines.forEach((entry, index) => {
    box.append(dropZone("gap", id => { if (M.moveCard(linesOf(), id, parentId, index)) changed(); }));
    if (!entry.line) return;
    const row = el("div", "line");
    for (const card of entry.line) row.append(renderCard(card));
    row.append(dropZone("line-end", id => { if (M.moveCard(linesOf(), id, parentId, index, true)) changed(); }));
    box.append(row);
  });
  box.append(dropZone("gap", id => { if (M.moveCard(linesOf(), id, parentId, lines.length)) changed(); }));
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
  const title = el("div", "title", card.card);
  title.append(...ruleBadges(card));
  box.append(title, el("div", "what", describeCard(card)));
  if (card.menu) box.append(renderLines(card.menu, card.id));
  box.addEventListener("click", e => { e.stopPropagation(); select(card.id, -1); });
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
    box.classList.add(zoneClass(dropZoneOf(box, e)));
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
    const dragged = e.dataTransfer.getData("text/card"), zone = dropZoneOf(box, e);
    const done = zone === "onto" ? M.dropOnCard(layout, linesOf(), dragged, card.id) : M.moveCardNext(linesOf(), dragged, card.id, zone);
    if (done) changed();
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
function dropZoneOf(box, e) {
  const r = box.getBoundingClientRect();
  const x = e.clientX - r.left, y = e.clientY - r.top;
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
  for (const [flag, label] of [["caseSensitive", "case sensitive"], ["also", "also when taken"]]) {
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
  box.addEventListener("click", () => { if (selectedRule !== index) { selectedRule = index; render(); } });
  return box;
}

function renderCardPane() {
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
  if (!card.menu)
    box.append(textField("Rename (regex)", card.rename && card.rename.regex, v => {
      if (v) card.rename = { regex: v, replace: (card.rename && card.rename.replace) || "" }; else delete card.rename;
      changed();
    }), textField("... replace with", card.rename && card.rename.replace, v => {
      if (card.rename) { card.rename.replace = v; changed(); }
    }));

  const actions = el("div", "actions");
  const button = (label, fn) => { const b = el("button", "", label); b.addEventListener("click", fn); actions.append(b); };
  button("+ Card beside", () => { select(M.addCard(layout, linesOf(), null, card.id).id, -1); changed(); });
  if (card.menu) button("+ Card in its menu", () => { select(M.addCard(layout, linesOf(), card.id).id, -1); changed(); });
  if (!card.menu && !M.isRemaining(card)) {
    button("+ Rule", () => { M.addRule(linesOf(), card); selectedRule = card.rules.length - 1; changed(); });
    button("Make it a card with a menu", () => { M.makeMenu(layout, linesOf(), card.id); changed(); });
  }
  if (!M.isRemaining(card)) button("Delete card", () => { if (M.deleteCard(linesOf(), card.id)) { selectedId = null; changed(); } });
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
  list.append(last);
}

// ---- the whole page ------------------------------------------------------------------------------------------------

function render() {
  if (!layout) return;
  $("ownKind").hidden = Array.isArray(layout[kind]) || kind === "default";
  $("cards").replaceChildren(renderLines(linesOf(), null));
  renderCardPane();
  renderRules();
}

function load(state) {
  kind = state.kind;   // chosen above the preview (the app)
  $("kindName").textContent = "for a right-click on " + (state.kindName || kindNames[kind] || kind);
  const names = [...new Set([...(state.layouts || []), state.name].filter(Boolean))];
  $("layouts").replaceChildren(...names.map(n => {
    const o = el("option", "", n + (n === state.active ? " (active)" : ""));
    o.value = n;
    return o;
  }));
  $("layouts").value = state.name || "";
  $("error").hidden = !state.error;
  $("error").textContent = state.error || "";
  if (state.layout === loadedText && layout) { render(); return; }   // the same file again (after a save)
  loadedText = state.layout;
  try {
    layout = M.ensureIds(JSON.parse(M.withoutComments(state.layout)));
  } catch (e) {
    layout = null;
    $("cards").replaceChildren(el("div", "problem", "The layout is not valid JSON: " + e.message));
    return;
  }
  dirty = false;
  $("dirty").hidden = true;
  lastSent = JSON.stringify(layout, null, 2);
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

// Registration for this user (Registration.cs): the state, Register / Unregister, Explorer restarted when asked.
function showRegistration(r, error) {
  const s = $("regState");
  if (!r) return;
  if (r.registered && r.ours && r.enabled) { s.className = "on"; s.textContent = "Dexmenu is registered and on for you."; }
  else if (r.registered && !r.ours) { s.className = "other"; s.textContent = "Another DexmenuShell.dll is registered: " + r.dll; }
  else if (r.registered) { s.className = "off"; s.textContent = "Dexmenu is registered but switched off."; }
  else { s.className = "off"; s.textContent = "Dexmenu is not registered: right-clicks show Windows' own menu."; }
  if (error) { s.className = "other"; s.textContent = "Not done: " + error; }
  $("register").disabled = r.registered && r.ours && r.enabled;
  $("unregister").disabled = !r.registered;
}
$("register").addEventListener("click", () => post({ type: "register", restart: $("restart").checked }));
$("unregister").addEventListener("click", () => post({ type: "unregister", restart: $("restart").checked }));

$("layouts").addEventListener("change", () => post({ type: "open", name: $("layouts").value }));
$("save").addEventListener("click", async () => {
  let name = $("layouts").value;
  if (!name) name = await askName();
  if (name) post({ type: "save", name, layout: JSON.stringify(layout, null, 2) });
});
$("saveAs").addEventListener("click", async () => {
  const name = await askName();
  if (name) post({ type: "save", name, layout: JSON.stringify(layout, null, 2) });
});
$("activate").addEventListener("click", () => post({ type: "activate", name: $("layouts").value }));
$("addTop").addEventListener("click", () => { if (layout) { select(M.addCard(layout, linesOf(), null).id, -1); changed(); } });
$("makeOwn").addEventListener("click", () => { layout[kind] = JSON.parse(JSON.stringify(layout.default)); M.ensureIds(layout); changed(); });
document.addEventListener("keydown", e => {
  if (e.key === "Delete" && selectedId && document.activeElement.tagName !== "INPUT" && M.deleteCard(linesOf(), selectedId)) {
    selectedId = null;
    changed();
  }
});

chrome.webview.addEventListener("message", e => {
  const m = e.data;
  if (m.type === "state") { showRegistration(m.registration); load(m); }
  else if (m.type === "registration") showRegistration(m.registration, m.error);
  else if (m.type === "preview") { $("error").hidden = !m.error; $("error").textContent = m.error || ""; }
  else if (m.type === "placed" && m.cardId) {
    if (m.event === 2) select(m.cardId, m.rule);
    else if (hoverId !== m.cardId) { hoverId = m.cardId; render(); }
  }
  else if (m.type === "saved") { dirty = false; $("dirty").hidden = true; }
});

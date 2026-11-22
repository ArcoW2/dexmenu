// The main window's page (docs/plans/05-PLAN-settings-windows.md 3.3 - 3.5). The app (HomeForm.cs) sends
//   { type: "state", registration, kinds: [ { kind, name, layout } ], layouts: [ { name, kinds } ], theme }
//   { type: "problem", text }
// and gets { type: "register" | "unregister" | "restart" | "setKind" | "moveKind" | "edit" | "new" | "copy" | "rename"
// | "delete" | "theme" | "minsize", ... } back. A kind's layout: a name, "none" (Windows' own menu) or null (not set).
"use strict";

const $ = id => document.getElementById(id);
const post = message => chrome.webview.postMessage(message);
let state = null;
let selected = null;   // the layout selected in the Layouts panel
let shownTab = "general";

function el(tag, cls, text) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text !== undefined) e.textContent = text;
  return e;
}

// ---- General: the registration -----------------------------------------------------------------------------------

function renderRegistration(r) {
  const line = $("regLine");
  line.replaceChildren();
  line.className = r.registered ? (r.ours ? "on" : "other") : "";
  if (!r.registered) line.append("Dexmenu is not registered: right-clicks show Windows' own menu.");
  else if (r.ours) line.append("Dexmenu is registered for you" + (r.enabled ? "" : " (switched off)") + ": ", el("span", "path", r.dll));
  else line.append("Another DexmenuShell.dll is registered: ", el("span", "path", r.dll));
  if (r.restartPending) line.append(el("div", "hint", "The change takes effect in Explorer after a restart."));
  $("register").disabled = r.registered && r.ours;
  $("unregister").disabled = !r.registered;
  $("restart").classList.toggle("lit", !!r.restartPending);
  if (r.restartPending && document.activeElement !== $("restart")) $("restart").focus();
}

// ---- General: which layout each kind gets --------------------------------------------------------------------------

function renderKinds() {
  const list = $("kinds");
  list.replaceChildren();
  state.kinds.forEach((k, i) => {
    const fixed = k.kind === "default";   // every other right-click: always last, always set
    const li = el("li", fixed ? "fixed" : "");
    li.append(el("span", "grip", "::"), el("span", "name", k.name));
    const sel = el("select");
    const option = (value, label) => { const o = el("option", "", label); o.value = value; sel.append(o); };
    if (!fixed) option("", "Not set");
    option("none", "None (Windows' own menu)");
    for (const l of state.layouts) option("layout:" + l.name, l.name);
    sel.value = k.layout === null || k.layout === undefined ? "" : k.layout === "none" ? "none" : "layout:" + k.layout;
    if (k.layout && k.layout !== "none" && !state.layouts.some(l => l.name === k.layout)) {
      option("layout:" + k.layout, k.layout + " (missing)");
      sel.value = "layout:" + k.layout;
    }
    sel.addEventListener("change", () => post({ type: "setKind", kind: k.kind,
      layout: sel.value === "" ? null : sel.value === "none" ? "none" : sel.value.slice("layout:".length) }));
    li.append(sel);
    const edit = el("button", "", "Edit");
    edit.title = "Open this layout's editor";
    edit.disabled = !k.layout || k.layout === "none" || !state.layouts.some(l => l.name === k.layout);
    edit.addEventListener("click", () => post({ type: "edit", name: k.layout }));
    li.append(edit);
    if (!fixed) {
      li.draggable = true;
      li.addEventListener("dragstart", e => e.dataTransfer.setData("text/kind", String(i)));
    }
    li.addEventListener("dragover", e => { if (e.dataTransfer.types.includes("text/kind")) { e.preventDefault(); li.classList.add("over"); } });
    li.addEventListener("dragleave", () => li.classList.remove("over"));
    li.addEventListener("drop", e => {
      e.preventDefault();
      li.classList.remove("over");
      const from = +e.dataTransfer.getData("text/kind");
      if (!Number.isNaN(from) && from !== i) post({ type: "moveKind", from, to: from < i ? i - 1 : i });
    });
    list.append(li);
  });
}

// While a kind is dragged, the pointer near the list's top or bottom edge scrolls it, faster the nearer the edge.
(() => {
  const edge = 32, fastest = 16, list = $("kinds");
  list.addEventListener("dragover", e => {
    const r = list.getBoundingClientRect();
    if (e.clientY < r.top + edge) list.scrollTop -= Math.ceil(fastest * (r.top + edge - e.clientY) / edge);
    else if (e.clientY > r.bottom - edge) list.scrollTop += Math.ceil(fastest * (e.clientY - (r.bottom - edge)) / edge);
  }, true);
})();

// ---- Layouts ---------------------------------------------------------------------------------------------------------

function renderLayouts() {
  const list = $("layoutList");
  list.replaceChildren();
  if (!state.layouts.some(l => l.name === selected)) selected = state.layouts.length ? state.layouts[0].name : null;
  for (const l of state.layouts) {
    const li = el("li", l.name === selected ? "selected" : "");
    li.append(el("span", "name", l.name), el("span", "kinds", l.kinds.length ? "set for " + l.kinds.join(", ") : "set for no kind"));
    li.addEventListener("click", () => { selected = l.name; renderLayouts(); });
    li.addEventListener("dblclick", () => post({ type: "edit", name: l.name }));
    list.append(li);
  }
  for (const id of ["edit", "copy", "rename", "delete"]) $(id).disabled = !selected;
}

async function askName(label, value) {
  const dialog = $("nameDialog");
  $("nameLabel").textContent = label;
  $("nameInput").value = value || "";
  dialog.showModal();
  $("nameInput").select();
  return new Promise(resolve => dialog.addEventListener("close", () =>
    resolve(dialog.returnValue === "ok" ? $("nameInput").value.trim() : null), { once: true }));
}

async function confirmDelete(name) {
  const l = state.layouts.find(x => x.name === name);
  $("confirmText").textContent = "Delete the layout \"" + name + "\"?" + (l && l.kinds.length
    ? " It is set for " + l.kinds.join(", ") + "; when it is deleted, those are set to None (Windows' own menu)."
    : "");
  const dialog = $("confirmDialog");
  dialog.showModal();
  return new Promise(resolve => dialog.addEventListener("close", () => resolve(dialog.returnValue === "ok"), { once: true }));
}

$("new").addEventListener("click", async () => { const n = await askName("New layout's name"); if (n) post({ type: "new", name: n }); });
$("edit").addEventListener("click", () => { if (selected) post({ type: "edit", name: selected }); });
$("copy").addEventListener("click", async () => {
  if (!selected) return;
  const n = await askName("Copy \"" + selected + "\" as", selected + " copy");
  if (n) post({ type: "copy", from: selected, to: n });
});
$("rename").addEventListener("click", async () => {
  if (!selected) return;
  const n = await askName("Rename \"" + selected + "\" to", selected);
  if (n && n !== selected) { post({ type: "rename", from: selected, to: n }); selected = n; }
});
$("delete").addEventListener("click", async () => { if (selected && await confirmDelete(selected)) post({ type: "delete", name: selected }); });
$("submenus").addEventListener("change", () => post({ type: "setMenu", name: "submenus", value: $("submenus").value }));
for (const id of ["onClickOnly", "windowsMenu", "editMenu"])
  $(id).addEventListener("change", () => post({ type: "setMenu", name: id, value: $(id).checked }));
$("register").addEventListener("click", () => post({ type: "register" }));
$("unregister").addEventListener("click", () => post({ type: "unregister" }));
$("restart").addEventListener("click", () => post({ type: "restart" }));

// ---- the panels' arrangement (plan 05 3.3) -------------------------------------------------------------------------

const px = name => parseFloat(getComputedStyle(document.documentElement).getPropertyValue(name));

// Side by side when both fit at their minimum, else above each other when they fit so, else tabs.
function arrange() {
  const m = px("--margin"), w = window.innerWidth, h = window.innerHeight - px("--header-h");
  const gw = px("--general-min-w"), gh = px("--general-min-h"), lw = px("--layouts-min-w"), lh = px("--layouts-min-h");
  let mode = "tabs";
  if (w >= gw + lw + 3 * m && h >= Math.max(gh, lh) + 2 * m) mode = "side";
  else if (w >= Math.max(gw, lw) + 2 * m && h >= gh + lh + 3 * m) mode = "stack";
  document.body.className = mode;
  for (const p of document.querySelectorAll(".panel")) p.classList.toggle("shown", mode !== "tabs" || p.id === shownTab);
  for (const b of document.querySelectorAll("#tabs button")) b.classList.toggle("on", b.dataset.panel === shownTab);
}

// The window's minimum: one panel at its minimum, as a tab (the largest of both), with the margins, the header and
// the tabs.
function minimumSize() {
  const m = px("--margin");
  return {
    w: Math.max(px("--general-min-w"), px("--layouts-min-w")) + 2 * m,
    h: Math.max(px("--general-min-h"), px("--layouts-min-h")) + 2 * m + px("--header-h") + px("--tabs-h"),
  };
}

for (const b of document.querySelectorAll("#tabs button"))
  b.addEventListener("click", () => { shownTab = b.dataset.panel; arrange(); });
window.addEventListener("resize", arrange);
arrange();
post({ type: "minsize", ...minimumSize() });

chrome.webview.addEventListener("message", e => {
  const m = e.data;
  if (m.type === "state") {
    state = m;
    $("problem").hidden = true;
    Theme.show(m.theme);
    renderRegistration(m.registration);
    $("submenus").value = m.menu.submenus;
    $("onClickOnly").checked = m.menu.onClickOnly;
    $("windowsMenu").checked = m.menu.windowsMenu;
    $("editMenu").checked = m.menu.editMenu;
    $("onClickOnly").disabled = m.menu.submenus === "replace";   // in place of the menu: always on a click
    renderKinds();
    renderLayouts();
  } else if (m.type === "problem") {
    $("problem").hidden = false;
    $("problem").textContent = m.text;
  }
});

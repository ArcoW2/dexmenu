// The main window's page (docs/plans/executed/05-PLAN-settings-windows.md 3.3 - 3.5). The app (HomeForm.cs) sends
//   { type: "state", registration, kinds: [ { kind, name, layout } ], layouts: [ { name, kinds } ], theme }
//   { type: "problem", text }
//   { type: "diagnostics", measured: { kind: result }, timings: [ entry ], hangSeconds, measuring, dexmenu }
//   { type: "measuring", kind, name, index, count }    { type: "pickedMeasureFile", path }
// and gets { type: "register" | "unregister" | "restart" | "setKind" | "moveKind" | "edit" | "new" | "copy" | "rename"
// | "delete" | "theme" | "minsize" | "diagnostics" | "measure" | "stopMeasure" | "pickMeasureFile" | "switchHandler"
// | "setHang", ... } back. A kind's layout: a name, "none" (Windows' own menu) or null (not set).
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
for (const id of ["onClickOnly"])
  $(id).addEventListener("change", () => post({ type: "setMenu", name: id, value: $(id).checked }));
$("textSize").addEventListener("change", () => post({ type: "setMenu", name: "textSize", value: (+$("textSize").value || 100) / 100 }));
for (const id of ["submenuMark", "actionMark", "states", "themeLight", "themeDark"])
  $(id).addEventListener("change", () => post({ type: "setMenu", name: id, value: $(id).value }));
$("widths").addEventListener("change", () => post({ type: "setMenu", name: "widths",
  value: [...$("widths").querySelectorAll("tr")].slice(1).map(tr => {
    const [lo, hi] = [...tr.querySelectorAll("input")].map(i => Math.max(100, +i.value || 200));
    return { min: lo, max: Math.max(lo, hi) };
  }) }));
$("register").addEventListener("click", () => post({ type: "register" }));
$("unregister").addEventListener("click", () => post({ type: "unregister" }));
$("restart").addEventListener("click", () => post({ type: "restart" }));

// ---- Diagnostics (docs/plans/16-PLAN-diagnostics.md) ------------------------------------------------------------------

let diag = null;          // the last "diagnostics" message
let measureFile = "";     // the user's own file to measure a file's right-click with; "": the sample .txt
let measuringNow = null;  // { name, index, count, since } while a measurement runs
const handlerTotal = r => r && r.create !== undefined ? (r.create || 0) + (r.init || 0) + (r.query || 0) : undefined;

function cell(tr, text, cls, title) {
  const td = el("td", cls || "", text);
  if (title) td.title = title;
  tr.append(td);
  return td;
}

// One pass of a handler (fresh or warm): its time, or why there is none.
function passText(h, r) {
  if (h.blocked) return h.byDexmenu ? "switched off" : h.blocked === "machine" ? "blocked (machine)" : "blocked";
  if (h.hanging) return "hanging";
  if (h.stopped) return "stopped";
  if (h.error) return h.error;
  if (!r) return "--";
  if (r.error) return r.error;
  return handlerTotal(r) + " ms";
}

function renderMeasured() {
  const box = $("measured");
  box.replaceChildren();
  const kind = $("measureKind").value;
  const r = diag && diag.measured && diag.measured[kind];
  $("measureFileName").textContent = kind === "file" && measureFile ? measureFile : "";
  $("measureFile").hidden = kind !== "file";
  if (!r) { box.append(el("div", "hint", "Not measured yet.")); return; }
  box.append(el("div", "hint", "Measured " + r.at + " on " + r.sample + "; an extension stopped after " + r.hangSeconds + " s."));
  const w = r.windows || {};
  const pass = p => !p ? "--" : p.error ? p.error : (p.bind + p.query) + " ms (" + p.items + " items)";
  box.append(el("div", "diag-total", w.hanging ? "Windows' whole menu: hanging" : w.stopped ? "Windows' whole menu: stopped"
    : "Windows' whole menu: fresh " + pass(w.fresh) + ", warm " + pass(w.warm)));
  const table = el("table", "diag");
  const head = el("tr");
  for (const t of ["Extension", "File", "Fresh", "Warm", "Items", "On"]) head.append(el("th", ["Extension", "File"].includes(t) ? "" : "ms", t));
  table.append(head);
  const rows = (r.handlers || []).slice().sort((a, b) => (handlerTotal(b.fresh) ?? -1) - (handlerTotal(a.fresh) ?? -1));
  for (const h of rows) {
    const tr = el("tr", h.blocked ? "off" : "");
    const ours = h.clsid === diag.dexmenu;
    cell(tr, h.name + (ours && !/dexmenu/i.test(h.name) ? " (Dexmenu)" : ""), "", h.key + " " + h.clsid);
    cell(tr, (h.dll || "").split(/[\\/]/).pop(), "file", h.dll);   // the DLL's name; its path on hover
    const breakdown = p => p && p.create !== undefined ? `load ${p.create} ms, initialize ${p.init} ms, build ${p.query ?? "--"} ms` : "";
    const bad = h.hanging || h.error || (h.fresh && h.fresh.error);
    cell(tr, passText(h, h.fresh), "ms" + (bad ? " bad" : ""), breakdown(h.fresh));
    cell(tr, h.blocked || h.hanging || h.stopped || h.error || (h.fresh && h.fresh.error) ? "" : passText(h, h.warm), "ms", breakdown(h.warm));
    cell(tr, h.fresh && h.fresh.items !== undefined ? String(h.fresh.items) : "", "ms");
    const on = el("td");
    if (!ours && (!h.blocked || h.byDexmenu)) {
      const box2 = el("input");
      box2.type = "checkbox";
      box2.checked = !h.blocked;
      box2.title = h.blocked ? "Switched off from here: tick to switch it on again" : "Untick to switch this extension off";
      box2.addEventListener("change", () => post({ type: "switchHandler", clsid: h.clsid, name: h.name, off: !box2.checked }));
      on.append(box2);
    }
    tr.append(on);
    table.append(tr);
  }
  box.append(table);
  box.append(el("div", "hint", "Switching an extension off changes every program's right-click, not only Dexmenu's; a "
    + "program already running (Explorer) may keep it until it starts again. Only an extension switched off here can be "
    + "switched on here."));
}

const median = list => {
  const s = list.filter(x => x !== undefined).sort((a, b) => a - b);
  if (!s.length) return undefined;
  const m = s.length >> 1;
  return s.length % 2 ? s[m] : Math.round((s[m - 1] + s[m]) / 2);
};
const ownTime = e => e.shown === "dexmenu" ? (e.steps || []).reduce((t, [, ms]) => t + ms, 0) : undefined;

function renderTimings() {
  const box = $("timings");
  box.replaceChildren();
  const entries = (diag && diag.timings) || [];
  if (!entries.length) { box.append(el("div", "hint", "No right-clicks yet.")); return; }
  // per program, the most recent program first, each one's newest first
  const groups = new Map();
  for (const e of entries.slice().reverse()) {
    const key = (e.program || "").toLowerCase();
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(e);
  }
  for (const list of groups.values()) {
    const path = list[0].program || "";
    const name = path.split(/[\\/]/).pop();
    const mw = median(list.map(e => e.wait)), mo = median(list.map(ownTime));
    const title = el("div", "program", name);
    title.title = path;
    title.append(" ", el("span", "hint", "middle: wait " + (mw ?? "--") + " ms, Dexmenu " + (mo ?? "--") + " ms"));
    box.append(title);
    const table = el("table", "diag");
    const head = el("tr");
    for (const t of ["When", "Right-click", "Menu", "Wait", "Dexmenu", "Dexmenu's steps (ms)"]) head.append(el("th", ["Wait", "Dexmenu"].includes(t) ? "ms" : "", t));
    table.append(head);
    for (const e of list) {
      const tr = el("tr");
      cell(tr, (e.at || "").replace("T", " ").replace(/\.\d+$/, ""));
      cell(tr, e.kind || "");
      cell(tr, e.shown === "dexmenu" ? "Dexmenu's" + (e.first ? " (first in the program)" : "") : "Windows' (" + (e.why || "") + ")");
      cell(tr, e.wait !== undefined ? e.wait + " ms" : "--", "ms");
      cell(tr, ownTime(e) !== undefined ? ownTime(e) + " ms" : "--", "ms");
      cell(tr, (e.steps || []).map(([n, ms]) => n + " " + ms).join(", "), "file");
      table.append(tr);
    }
    box.append(table);
  }
}

function renderMeasuring() {
  const busy = !!(diag && diag.measuring) || !!measuringNow;
  $("measure").disabled = busy;
  $("stopMeasure").hidden = !busy;
  $("measureStatus").textContent = measuringNow
    ? (measuringNow.index > 0 ? `Measuring ${measuringNow.index} of ${measuringNow.count}: ` : "Measuring ")
      + `${measuringNow.name}, ${((Date.now() - measuringNow.since) / 1000).toFixed(1)} s`
    : "";
}
setInterval(() => { if (measuringNow) renderMeasuring(); }, 100);

$("measureKind").addEventListener("change", renderMeasured);
$("measureFile").addEventListener("click", () => post({ type: "pickMeasureFile" }));
$("measure").addEventListener("click", () => {
  const kind = $("measureKind").value;
  measuringNow = { name: "starting", index: 0, count: 0, since: Date.now() };
  renderMeasuring();
  post({ type: "measure", kind, file: kind === "file" ? measureFile : "" });
});
$("stopMeasure").addEventListener("click", () => post({ type: "stopMeasure" }));
$("hangSeconds").addEventListener("change", () => post({ type: "setHang", value: +$("hangSeconds").value }));

// ---- the panels' arrangement (plan 05 3.3) -------------------------------------------------------------------------

const px = name => parseFloat(getComputedStyle(document.documentElement).getPropertyValue(name));

// A list's minimum: its first three rows as they wrap now, or its CSS minimum when it has fewer.
function listMinimum(list) {
  const cs = getComputedStyle(list), rows = [...list.children].slice(0, 3);
  const h = rows.reduce((t, r) => t + r.offsetHeight, 0) + parseFloat(cs.borderTopWidth) + parseFloat(cs.borderBottomWidth);
  return Math.max(parseFloat(cs.minHeight), rows.length === 3 ? h : 0);
}

// Each panel's minimum height, measured at its minimum width: everything in it at its own height, a list at its
// minimum (three rows). Set as --general-min-h, --rightclicks-min-h and --layouts-min-h, so the panels' arrangement and the window's
// minimum follow what the panel holds.
function measureMinimums() {
  for (const id of ["general", "rightclicks", "layouts", "diagnostics"]) {
    const panel = $(id), saved = panel.getAttribute("style");
    panel.style.display = "flex";
    panel.style.flex = "none";
    panel.style.width = px(`--${id}-min-w`) + "px";
    const cs = getComputedStyle(panel);
    let h = ["paddingTop", "paddingBottom", "borderTopWidth", "borderBottomWidth"].reduce((t, k) => t + parseFloat(cs[k]), 0);
    for (const c of panel.children) {
      const ccs = getComputedStyle(c);
      if (ccs.display === "none") continue;
      // a list at three rows, a scrolling part at its CSS minimum
      h += (c.classList.contains("list") ? listMinimum(c) : c.classList.contains("scroll") ? parseFloat(ccs.minHeight) : c.offsetHeight)
        + parseFloat(ccs.marginTop) + parseFloat(ccs.marginBottom);
    }
    if (saved === null) panel.removeAttribute("style"); else panel.setAttribute("style", saved);
    document.documentElement.style.setProperty(`--${id}-min-h`, Math.ceil(h) + "px");
  }
}

// The panels as tabs, one shown at a time (plan 05 3.3).
function arrange() {
  document.body.className = "tabs";
  for (const p of document.querySelectorAll(".panel")) p.classList.toggle("shown", p.id === shownTab);
  for (const b of document.querySelectorAll("#tabs button[data-panel]")) b.classList.toggle("on", b.dataset.panel === shownTab);
}

// The window's minimum: one panel at its minimum, as a tab (the largest of them), with the margins and
// the tabs.
function minimumSize() {
  const m = px("--margin");
  return {
    w: Math.max(px("--general-min-w"), px("--rightclicks-min-w"), px("--layouts-min-w"), px("--diagnostics-min-w")) + 2 * m,
    h: Math.max(px("--general-min-h"), px("--rightclicks-min-h"), px("--layouts-min-h"), px("--diagnostics-min-h")) + 2 * m + px("--tabs-h"),
  };
}

for (const b of document.querySelectorAll("#tabs button[data-panel]"))   // the tabs, not the light / dark button
  b.addEventListener("click", () => {
    shownTab = b.dataset.panel;
    arrange();
    if (shownTab === "diagnostics") post({ type: "diagnostics" });   // the right-clicks' timings as they are now
  });
// Measured again whenever the page changes (a state fills the lists and the registration line); the window's minimum
// sent when it changed.
let sentMin = "";
function postMinimum() {
  measureMinimums();
  const m = minimumSize(), key = `${m.w}x${m.h}`;
  if (key !== sentMin) { sentMin = key; post({ type: "minsize", ...m }); }
}
arrange();
postMinimum();

chrome.webview.addEventListener("message", e => {
  const m = e.data;
  if (m.type === "state") {
    state = m;
    $("problem").hidden = true;
    Theme.show(m.theme);
    renderRegistration(m.registration);
    $("submenus").value = m.menu.submenus;
    $("onClickOnly").checked = m.menu.onClickOnly;
    for (const id of ["submenuMark", "actionMark"]) if (document.activeElement !== $(id)) $(id).value = m.menu[id];
    $("states").value = m.menu.states;
    for (const id of ["themeLight", "themeDark"]) {
      const sel = $(id);
      sel.replaceChildren(...m.themes.map(n => { const o = document.createElement("option"); o.value = o.textContent = n; return o; }));
      sel.value = m.menu[id];
    }
    if (document.activeElement !== $("textSize")) $("textSize").value = Math.round(m.menu.textSize * 100);
    const rows = [...$("widths").querySelectorAll("tr")].slice(1);
    rows.forEach((tr, i) => {
      const w = m.menu.widths[Math.min(i, m.menu.widths.length - 1)] || { min: 200, max: 480 };
      const [lo, hi] = tr.querySelectorAll("input");
      if (document.activeElement !== lo) lo.value = w.min;
      if (document.activeElement !== hi) hi.value = w.max;
    });
    $("onClickOnly").disabled = m.menu.submenus === "replace";   // in place of the menu: always on a click
    renderKinds();
    renderLayouts();
    postMinimum();
  } else if (m.type === "diagnostics") {
    diag = m;
    if (!m.measuring) measuringNow = null;
    if (document.activeElement !== $("hangSeconds")) $("hangSeconds").value = m.hangSeconds;
    renderMeasured();
    renderTimings();
    renderMeasuring();
  } else if (m.type === "measuring") {
    measuringNow = { name: m.name, index: m.index, count: m.count, since: Date.now() };
    renderMeasuring();
  } else if (m.type === "pickedMeasureFile") {
    measureFile = m.path;
    renderMeasured();
  } else if (m.type === "problem") {
    $("problem").hidden = false;
    $("problem").textContent = m.text;
  }
});

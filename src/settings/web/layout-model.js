// The layout as the editor changes it (docs/plans/executed/11-PLAN-cards-hold-content.md 3.1, 3.5; plan 02 3.3, 3.5): pure
// functions on the parsed layout, no page. A layout (format 2): { format: 2, menu: { content: [ ... ] } }, the menu one
// card holding the others. A container (the menu's content, a card's content) is a list of entries: cards, dividers
// ({ id, divider }) and the search box ({ id, search: true }). A card: { id, card (its name), rules: [ ... ] }, or
// { id, card, content: [ entries ], show } holding cards (show "submenu", "row" or "column"), with title, extra,
// rename, style where given. The remaining card's rule is the text "remaining"; a layout has exactly one. Every other
// rule has a priority (the priority list, lower first). The functions take the menu's content (`lines`) as the root.
// Tested by selftest.js (DexmenuSettings.exe --selftest).
"use strict";

const LayoutModel = (() => {
  const matchKinds = ["equals", "contains", "startsWith", "endsWith", "wildcard", "regex", "any"];

  function isRemaining(card) { return Array.isArray(card.rules) && card.rules.includes("remaining"); }
  // A note card ({ id, note: "<text>" }, plan 02 3.3): no button, no rules, holds nothing.
  function isNote(card) { return card.note !== undefined; }
  // A divider or the search box: an entry between cards, not a card.
  function isDividerEntry(entry) { return entry.divider !== undefined || entry.search === true; }
  // A card holding cards (plan 11): its content, shown as its show says.
  function isHolder(card) { return Array.isArray(card.content); }
  // A row card that only puts cards side by side, with nothing of its own (what a line was): made by a drop beside a
  // card, undone when one card is left in it.
  const plainRowKeys = ["id", "card", "show", "shownWhen", "content", "cardFit"];
  function isPlainRow(card) {
    return isHolder(card) && card.show === "row" && Object.keys(card).every(k => plainRowKeys.includes(k));
  }
  function isRow(card) { return isHolder(card) && card.show === "row"; }

  // Every card of a container, depth first, with where it is: its container (lines), its place in it (lineIndex, and
  // cardIndex the same), the card holding it (parent; null at the menu's top).
  function* cards(lines, parent = null) {
    for (let i = 0; i < lines.length; i++) {
      const card = lines[i];
      if (!card || isDividerEntry(card)) continue;
      yield { card, lines, lineIndex: i, cardIndex: i, parent };
      if (isHolder(card)) yield* cards(card.content, card);
    }
  }

  function find(lines, id) {
    for (const at of cards(lines)) if (at.card.id === id) return at;
    return null;
  }

  function contains(card, id) {
    if (!isHolder(card)) return false;
    for (const at of cards(card.content)) if (at.card.id === id) return true;
    return false;
  }

  // The menu's content of a layout.
  function rootOf(layout) { return layout && layout.menu && Array.isArray(layout.menu.content) ? layout.menu.content : []; }

  function allCards(layout) { return [...cards(rootOf(layout))].map(at => at.card); }

  // Every divider entry of a container, depth first: { entry, lines, index, parent }. A divider: { id, divider: "<text>"
  // or "", align: "left" | "center" | "right" }, between cards. The search box ({ id, search: true }) stands between
  // cards as a divider does, so it is handled as one: moved, deleted, copied.
  function* dividers(lines, parent = null) {
    for (let i = 0; i < lines.length; i++) {
      const entry = lines[i];
      if (!entry) continue;
      if (isDividerEntry(entry)) yield { entry, lines, index: i, parent };
      else if (isHolder(entry)) yield* dividers(entry.content, entry);
    }
  }
  function allDividers(layout) { return [...dividers(rootOf(layout))].map(d => d.entry); }
  function findDivider(lines, id) {
    for (const d of dividers(lines)) if (d.entry.id === id) return d;
    return null;
  }

  // A fresh id "c<n>" for a container's tree (the menu's content).
  function freshId(lines) {
    let max = 0;
    const see = id => { const m = /^c(\d+)$/.exec(id || ""); if (m) max = Math.max(max, +m[1]); };
    for (const at of cards(lines)) see(at.card.id);
    for (const d of dividers(lines)) see(d.entry.id);
    return "c" + (max + 1);
  }
  function newId(layout) { return freshId(rootOf(layout)); }

  // Ids on every card, each once, and a priority on every rule, so the editor, the file and the DLL name the same
  // things. A card whose id an earlier card has already gets a new one (a layout saved with a duplicate).
  function ensureIds(layout) {
    // the menu itself a card (plan 11 3.9): its id, its name, under each other unless it says otherwise
    if (layout && layout.menu) {
      layout.menu.id = "menu";
      if (typeof layout.menu.card !== "string") layout.menu.card = "Menu";
      if (!layout.menu.show) layout.menu.show = "column";
    }
    let next = +newId(layout).slice(1);
    const seen = new Set();
    for (const c of [...allCards(layout), ...allDividers(layout)]) {
      if (!c.id || seen.has(c.id)) c.id = "c" + next++;
      seen.add(c.id);
    }
    renumber(rootOf(layout));
    return layout;
  }

  // ---- rules ----------------------------------------------------------------------------------------------------

  // ---- colours (plan 03 3.2, 3.6) ---------------------------------------------------------------------------------

  const hexColor = /^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/i;
  const paletteName = /^[A-Za-z][\w-]*$/;

  // A colour value of a card's look as the picker shows it: mode "theme" (the theme's own colour, as it is or with an
  // intensity and an opacity: { "intensity", "opacity" } without "color"), "pick" (a colour or a palette name, with an
  // intensity and an opacity) or "json" (a gradient, "none", anything else, as text). overrule: the opacity is given
  // (else the colour's own alpha stays).
  function colorState(value) {
    const numbers = v => (v.intensity === undefined || typeof v.intensity === "number") &&
      (v.opacity === undefined || typeof v.opacity === "number");
    const adjust = v => ({ intensity: v.intensity === undefined ? 100 : v.intensity,
      opacity: v.opacity === undefined ? 100 : v.opacity, overrule: v.opacity !== undefined });
    if (value === undefined) return { mode: "theme", intensity: 100, opacity: 100, overrule: false };
    const isObject = value && typeof value === "object" && !Array.isArray(value);
    if (isObject && value.color === undefined && Object.keys(value).length > 0 &&
      Object.keys(value).every(k => k === "intensity" || k === "opacity") && numbers(value))
      return { mode: "theme", ...adjust(value) };
    let base = value, a = { intensity: 100, opacity: 100, overrule: false };
    if (isObject && typeof value.color === "string" && numbers(value) &&
      Object.keys(value).every(k => ["color", "intensity", "opacity"].includes(k))) {
      base = value.color;
      a = adjust(value);
    }
    if (typeof base === "string" && hexColor.test(base)) {
      let h = base.slice(1).toLowerCase();
      if (h.length === 3) h = [...h].map(c => c + c).join("");
      if (h.length === 8) {
        if (!a.overrule) a = { ...a, opacity: Math.round(parseInt(h.slice(6), 16) / 255 * 100), overrule: true };
        h = h.slice(0, 6);
      }
      return { mode: "pick", base: "#" + h, ...a };
    }
    if (typeof base === "string" && base !== "none" && paletteName.test(base)) return { mode: "pick", base, ...a };
    return { mode: "json", text: JSON.stringify(value) };
  }

  // The value written for a picker's state, in its shortest form. The theme's: nothing at intensity 100 without an
  // opacity of its own, else { intensity, opacity } with what is given. A colour or palette name: "#rrggbb" or the name
  // alone at intensity 100 without an opacity of its own, else { color, intensity, opacity } with what is given. JSON
  // text that does not parse: ok false (left as it was).
  function colorValue(state) {
    if (state.mode === "json") {
      try { return { ok: true, value: JSON.parse(state.text) }; } catch { return { ok: false }; }
    }
    const intensity = Math.max(0, Math.min(200, Math.round(state.intensity ?? 100)));
    const opacity = Math.max(0, Math.min(100, Math.round(state.opacity ?? 100)));
    const v = state.mode === "pick" ? { color: state.base } : {};
    if (intensity !== 100) v.intensity = intensity;
    if (state.overrule) v.opacity = opacity;
    if (Object.keys(v).length === 0) return { ok: true, value: undefined };
    if (Object.keys(v).length === 1 && v.color !== undefined) return { ok: true, value: v.color };
    return { ok: true, value: v };
  }

  // What a colour field holds (plan 03 3.6): kind "colour" (colour: a colorState that is not JSON), "gradient" (only
  // where a gradient can be drawn, gradients true: two colours, each a colour or a palette colour with its intensity
  // and opacity, start and end, and its angle, 90 when not given) or "json" (anything else, as text: a gradient of
  // more colours, "none").
  function fillState(value, gradients) {
    if (value === "none") return { kind: "none" };   // nothing drawn: no background, no border line
    // a background image (plan 03 3.4): { image, fit, opacity, tint, color }
    if (gradients && value && typeof value === "object" && !Array.isArray(value) && typeof value.image === "string")
      return { kind: "image", spec: JSON.parse(JSON.stringify(value)) };
    if (gradients && value && typeof value === "object" && !Array.isArray(value) && Array.isArray(value.gradient) &&
      value.gradient.length === 2 && Object.keys(value).every(k => k === "gradient" || k === "angle") &&
      (value.angle === undefined || typeof value.angle === "number")) {
      const start = colorState(value.gradient[0]), end = colorState(value.gradient[1]);
      if (start.mode === "pick" && end.mode === "pick")
        return { kind: "gradient", start, end, angle: value.angle === undefined ? 90 : value.angle };
    }
    const colour = colorState(value);
    if (colour.mode === "json") return { kind: "json", text: colour.text };
    return { kind: "colour", colour };
  }

  // The value written for a colour field's state; ok false when JSON text does not parse (left as it was). A
  // gradient: { "gradient": [ start, end ], "angle" } with each colour in its shortest form, the angle only when not 90.
  function fillValue(state) {
    if (state.kind === "none") return { ok: true, value: "none" };
    if (state.kind === "image") {
      // what is not set left out: stretch, full opacity, no tint and no colour under it are the defaults
      const v = { image: state.spec.image || "" };
      for (const k of ["fit", "opacity", "tint", "color"])
        if (state.spec[k] !== undefined && state.spec[k] !== "" && !(k === "fit" && state.spec[k] === "stretch") &&
          !(k === "opacity" && state.spec[k] === 100)) v[k] = state.spec[k];
      return { ok: true, value: v };
    }
    if (state.kind === "json") return colorValue({ mode: "json", text: state.text });
    if (state.kind === "colour") return colorValue(state.colour);
    const v = { gradient: [colorValue(state.start).value, colorValue(state.end).value] };
    if (Math.round(state.angle) !== 90) v.angle = Math.round(state.angle);
    return { ok: true, value: v };
  }

  // A picker's colour as CSS (the swatch), with the theme's palette ({ name: "#rrggbbaa" }, basecolor among them) for
  // a palette name and the intensity: 0 the base colour, 100 the colour, 200 the base colour inverted. "" unknown.
  function colorCss(state, palette) {
    if (state.mode !== "pick") return "";
    const rgba = text => {
      const h = (text || "").slice(1);
      if (!/^[0-9a-f]{6}([0-9a-f]{2})?$/i.test(h)) return null;
      return [0, 2, 4].map(i => parseInt(h.slice(i, i + 2), 16)).concat(h.length === 8 ? parseInt(h.slice(6), 16) / 255 : 1);
    };
    const c = rgba(hexColor.test(state.base) ? state.base : palette && palette[state.base]);
    if (!c) return "";
    const base = rgba(palette && palette.basecolor) || [0, 0, 0, 1];
    const t = state.intensity;
    const mixed = [0, 1, 2].map(i => Math.round(t <= 100 ? base[i] + (c[i] - base[i]) * t / 100
      : c[i] + (255 - base[i] - c[i]) * (t - 100) / 100));
    const alpha = state.overrule ? state.opacity / 100 : c[3];
    return "rgba(" + mixed.join(", ") + ", " + alpha + ")";
  }

  // A used rule's rank (plan 09 3.1): none, a number from 1, or a text of ranks and ranges separated by commas, as
  // pages to print ("3", "1-3", "3-1", "1,3,5", "1-2,5-6,8-10").
  function rankProblem(rank) {
    const problem = "rank: numbers from 1 and ranges, as 1-3 or 1,3,5 or 1-2,5-6";
    if (rank === undefined) return "";
    if (typeof rank === "number") return Number.isInteger(rank) && rank >= 1 ? "" : problem;
    if (typeof rank !== "string" || !rank.trim()) return problem;
    for (const part of rank.split(",")) {
      const m = /^\s*(\d+)\s*(?:-\s*(\d+)\s*)?$/.exec(part);
      if (!m || +m[1] < 1 || (m[2] !== undefined && +m[2] < 1)) return problem;
    }
    return "";
  }

  // The states a rule takes: its own ("states"), else what General sets for every rule ("both", "enabled",
  // "disabled"), as a list.
  function statesOf(rule, general) {
    if (Array.isArray(rule.states)) return rule.states;
    return general === "enabled" ? ["enabled"] : general === "disabled" ? ["disabled"] : ["enabled", "disabled"];
  }

  // The rule's type: "usage" (it has "used"), else "name".
  // The rule's type: "editMenu" or "windowsMenu" (it finds Dexmenu's own item, plan 12), "usage" (it has "used"), else
  // "name".
  function ruleType(rule) {
    if (!rule || typeof rule !== "object") return "name";
    if (rule.own === "editMenu" || rule.own === "windowsMenu") return rule.own;
    return rule.used !== undefined ? "usage" : "name";
  }

  // Switch a rule to another type: the other types' keys taken out, the new type's start put in. Dexmenu's own item
  // has no other fields: the shared ones go too.
  function setRuleType(rule, type) {
    if (ruleType(rule) === type) return;
    for (const k of ["name", "caseSensitive", "scope", "path", "used", "rank", "own", "latest", "exclude"]) delete rule[k];   // latest, exclude: by name only
    if (type === "usage") rule.used = "most";
    else if (type === "editMenu" || type === "windowsMenu") {
      for (const k of ["states", "also", "consume", "skipDuplicates", "order", "descending"]) delete rule[k];
      rule.own = type;
    }
    else rule.name = { contains: "" };
  }

  function ruleProblem(rule) {
    if (rule === "remaining") return "";
    if (typeof rule !== "object" || rule === null) return "a rule is an object";
    if (rule.verb !== undefined) return "a rule on the verb is not yet possible";
    if (rule.own !== undefined) {
      if (rule.name !== undefined || rule.used !== undefined) return "a rule finds Dexmenu's item, by a name or by use: one of them";
      return rule.own === "editMenu" || rule.own === "windowsMenu" ? "" : "own is editMenu or windowsMenu";
    }
    if (rule.used !== undefined) {
      if (rule.name !== undefined) return "a rule has a name or a use, not both";
      if (rule.exclude) return "an exclude rule is a rule by name";
      if (rule.used !== "most" && rule.used !== "recent") return "used is most or recent";
      const rank = rankProblem(rule.rank);
      if (rank) return rank;
      return commonProblem(rule);
    }
    if (rule.scope !== undefined && rule.path !== undefined) return "a scope and a path: only one of them";
    if (rule.scope !== undefined && rule.scope !== "top" && rule.scope !== "anywhere") return "scope is top or anywhere";
    for (const field of ["name", "path"]) {
      const m = rule[field];
      if (m === undefined) { if (field === "name") return "no name to match"; continue; }
      const keys = Object.keys(m);
      if (keys.length !== 1 || !matchKinds.includes(keys[0])) return field + ": one match kind";
      if (keys[0] === "any" ? !Array.isArray(m.any) || m.any.length === 0 : typeof m[keys[0]] !== "string" || m[keys[0]] === "")
        return field + ": nothing to match";
      if (keys[0] === "regex") { try { new RegExp(m.regex); } catch (e) { return field + ": the regex does not compile"; } }
    }
    if (rule.latest !== undefined && !(Number.isInteger(rule.latest) && rule.latest >= 1)) return "latest: a whole number from 1";
    return commonProblem(rule);
  }

  // What a rule of either type may get wrong
  function commonProblem(rule) {
    if (rule.consume !== undefined && typeof rule.consume !== "boolean") return "consume is true or false";
    if (rule.order !== undefined && !["recent", "used", "name"].includes(rule.order)) return "order is recent, used or name";
    if (rule.descending !== undefined && typeof rule.descending !== "boolean") return "descending is true or false";
    if (rule.states !== undefined && (!Array.isArray(rule.states) || rule.states.some(s => s !== "enabled" && s !== "disabled")))
      return "states: enabled and/or disabled";
    return "";
  }

  // A card that can never show anything (outlined red): a card with rules but none, or with an invalid rule.
  function useless(card) {
    if (isHolder(card) || isNote(card) || isOwn(card)) return false;
    const rules = card.rules || [];
    return rules.length === 0 || rules.every(r => r !== "remaining" && r.exclude === true) || rules.some(r => ruleProblem(r) !== "");
  }

  // The priority list: every rule but the remaining card's, lower priority first, then the layout's order (as the DLL).
  function ruleList(lines) {
    const list = [];
    let order = 0;
    for (const at of cards(lines))
      (at.card.rules || []).forEach((rule, index) => {
        if (rule !== "remaining") list.push({ card: at.card, rule, index, order: order++ });
      });
    const p = r => typeof r.rule.priority === "number" ? r.rule.priority : Infinity;
    list.sort((a, b) => p(a) - p(b) || a.order - b.order);
    return list;
  }

  // Priorities 1..n in the list's order; each card's rules kept in that order too (the remaining card's rule first).
  function renumber(lines) {
    ruleList(lines).forEach((r, i) => { r.rule.priority = i + 1; });
    for (const at of cards(lines))
      if (Array.isArray(at.card.rules))
        at.card.rules.sort((a, b) => (a === "remaining" ? 0 : a.priority) - (b === "remaining" ? 0 : b.priority));
  }

  // A card's rule moved within the card (from, to: places among the card's own rules, in priority order). The card's
  // rules keep the places they hold in the priority list; only their order among themselves changes.
  function moveCardRule(lines, card, from, to) {
    const own = card.rules.filter(r => r !== "remaining").sort((a, b) => a.priority - b.priority);
    if (from < 0 || from >= own.length || to < 0 || to >= own.length || from === to) return false;
    const slots = own.map(r => r.priority);
    const [moved] = own.splice(from, 1);
    own.splice(to, 0, moved);
    own.forEach((r, i) => { r.priority = slots[i]; });
    renumber(lines);
    return true;
  }

  // The rule at place `from` in the priority list moved to place `to`.
  function moveRule(lines, from, to) {
    const list = ruleList(lines);
    const [moved] = list.splice(from, 1);
    list.splice(to, 0, moved);
    list.forEach((r, i) => { r.rule.priority = i + 1; });
    renumber(lines);
  }

  // A card's rule (index: its place in fromCard.rules) moved, or copied, onto another card with rules. A moved rule keeps
  // its place in the priority list; a copy comes right after the original. Never the remaining card's rule, never onto
  // a card with a menu or the remaining card. The rule now on toCard, or null.
  function moveRuleToCard(lines, fromCard, index, toCard, copy) {
    const rule = fromCard.rules && fromCard.rules[index];
    if (!rule || rule === "remaining" || !toCard || isHolder(toCard) || isRemaining(toCard) || isNote(toCard)) return null;
    if (!copy && fromCard === toCard) return null;
    toCard.rules = toCard.rules || [];
    let placed = rule;
    if (copy) {
      placed = JSON.parse(JSON.stringify(rule));
      placed.priority = rule.priority + 0.5;   // renumbered right after the original
    } else fromCard.rules.splice(index, 1);
    toCard.rules.push(placed);
    renumber(lines);
    return placed;
  }

  function addRule(lines, card) {
    const rule = { name: { contains: "" }, priority: ruleList(lines).length + 1 };
    card.rules = card.rules || [];
    card.rules.push(rule);
    return rule;
  }

  function deleteRule(lines, card, index) {
    if (card.rules[index] === "remaining") return false;
    card.rules.splice(index, 1);
    renumber(lines);
    return true;
  }

  // ---- cards ----------------------------------------------------------------------------------------------------

  // A container cleaned up after a card left it: a plain row with one card left is that card again; one with none
  // goes; a submenu holder left empty becomes a card with rules that has none (it finds nothing, outlined red).
  function tidy(lines, holder) {
    if (!holder || !isHolder(holder)) return;
    const left = holder.content.filter(e => e && !isDividerEntry(e));
    if (isPlainRow(holder) && left.length <= 1) {
      const at = find(lines, holder.id);
      if (!at) return;
      if (left.length === 1) at.lines.splice(at.lineIndex, 1, left[0]);
      else at.lines.splice(at.lineIndex, 1);
      return;
    }
    if (holder.show === "submenu" && left.length === 0) {
      delete holder.content;
      delete holder.show;
      holder.rules = [];
    }
  }

  // A card taken out of its place; its container tidied (a plain row of one card undone).
  function takeOut(lines, id) {
    const at = find(lines, id);
    if (!at) return null;
    at.lines.splice(at.lineIndex, 1);
    tidy(lines, at.parent);
    return at.card;
  }

  // A card dropped onto another card: a card holding cards takes it at the end of its content; a card with rules
  // becomes a card with a submenu, its rules in a new first card (nothing lost), the dropped card after it.
  function dropOnCard(layout, lines, draggedId, targetId) {
    if (draggedId === targetId) return false;
    const dragged = find(lines, draggedId), target = find(lines, targetId);
    if (!dragged || !target || contains(dragged.card, targetId) || isNote(target.card)) return false;   // not onto a note
    const firstId = newId(layout);   // before the dragged card is taken out: else its id counts as free
    const card = takeOut(lines, draggedId);
    const t = find(lines, targetId).card;
    if (isHolder(t)) t.content.push(card);
    else {
      const first = { id: firstId, card: t.card, rules: t.rules || [] };
      for (const k of ["title", "rename"]) if (t[k] !== undefined) { first[k] = t[k]; delete t[k]; }
      delete t.rules;
      t.show = "submenu";
      t.content = [first, card];
    }
    return true;
  }

  // The container a card goes into: a card holding cards (parentId), or the menu's top (null).
  function containerOf(lines, parentId) {
    if (!parentId) return lines;
    const at = find(lines, parentId);
    return at && isHolder(at.card) ? at.card.content : null;
  }

  // A card moved into a container (parentId: a card holding cards, or null for the top) before the entry at index
  // (counted before it was taken out), or at the end. intoLine: no longer used (a row is a card holding cards).
  function moveCard(lines, draggedId, parentId, index, intoLine = false) {
    const dragged = find(lines, draggedId);
    if (!dragged) return false;
    if (parentId && (parentId === draggedId || contains(dragged.card, parentId))) return false;
    const level = containerOf(lines, parentId);
    if (!level) return false;
    // the entries it goes before, kept across taking it out (its own row may be undone, its place moving)
    const anchors = level.slice(index).filter(e => e !== dragged.card);
    const card = takeOut(lines, draggedId);
    const now = containerOf(lines, parentId) || lines;
    const survivor = anchors.find(a => now.includes(a));
    if (survivor) now.splice(now.indexOf(survivor), 0, card);
    else now.push(card);
    return true;
  }

  // A card dropped next to another card: beside it (side "before" / "after": into the target's row, or a new plain row
  // made of the two in the target's place), or above or below it ("above" / "below": in the target's container; a
  // card in a plain row: above or below that row).
  function moveCardNext(lines, draggedId, targetId, side) {
    if (draggedId === targetId) return false;
    const dragged = find(lines, draggedId), target = find(lines, targetId);
    if (!dragged || !target || contains(dragged.card, targetId)) return false;
    if (side === "above" || side === "below") {
      // a card in a plain row stands for the row: above or below the row
      const anchor = target.parent && isPlainRow(target.parent) && target.parent.id !== draggedId ? find(lines, target.parent.id) : target;
      return moveCard(lines, draggedId, anchor.parent ? anchor.parent.id : null, anchor.lineIndex + (side === "below" ? 1 : 0));
    }
    const id = freshId(lines);
    const card = takeOut(lines, draggedId);
    const t = find(lines, targetId);
    if (t.parent && isRow(t.parent)) t.lines.splice(t.lineIndex + (side === "after" ? 1 : 0), 0, card);
    else {
      const row = { id, card: "Line", show: "row", shownWhen: "always", content: side === "after" ? [t.card, card] : [card, t.card] };
      t.lines.splice(t.lineIndex, 1, row);
    }
    return true;
  }

  // ---- dividers ---------------------------------------------------------------------------------------------------

  function addDivider(layout, lines, parentId) {
    const entry = { id: newId(layout), divider: "" };
    (containerOf(lines, parentId) || lines).push(entry);
    return entry;
  }

  function addSearch(layout, lines) {
    const entry = { id: newId(layout), search: true };
    lines.unshift(entry);
    return entry;
  }

  function deleteDivider(lines, id) {
    const d = findDivider(lines, id);
    if (!d) return false;
    d.lines.splice(d.index, 1);
    return true;
  }

  // A divider moved into a container (parentId: a card holding cards, or null for the top) before the entry at index
  // (counted before it was taken out), or to the container's end.
  function moveDivider(lines, id, parentId, index) {
    const d = findDivider(lines, id);
    if (!d) return false;
    const level = containerOf(lines, parentId);
    if (!level) return false;
    const anchors = level.slice(index).filter(e => e !== d.entry);
    d.lines.splice(d.index, 1);
    const survivor = anchors.find(a => level.includes(a));
    level.splice(survivor ? level.indexOf(survivor) : level.length, 0, d.entry);
    return true;
  }

  // A divider dropped on a card's edge: on its left or right edge, when the card stands in a row (side by side), beside
  // it in that row, where it is drawn upright (plan 18); otherwise, and on its top or bottom edge, just above or below
  // it (a card in a plain row: that row).
  function moveDividerNext(lines, id, targetCardId, side) {
    let target = find(lines, targetCardId);
    if (!target) return false;
    if (side === "before" || side === "after") {
      if (target.parent && isRow(target.parent) && !target.parent.perRow) {
        const d = findDivider(lines, id);
        if (!d) return false;
        d.lines.splice(d.index, 1);
        const t = find(lines, targetCardId);   // its place again: taking the divider out may have moved it
        t.lines.splice(t.lineIndex + (side === "after" ? 1 : 0), 0, d.entry);
        return true;
      }
      side = side === "before" ? "above" : "below";
    }
    if (target.parent && isPlainRow(target.parent)) target = find(lines, target.parent.id);
    return moveDivider(lines, id, target.parent ? target.parent.id : null, target.lineIndex + (side === "below" ? 1 : 0));
  }

  // Deleting a card: never the remaining card, nor a card holding it; the last card of a submenu gives its rules to the
  // card holding it, which becomes a card with rules again (the reverse of dropping a card onto a card).
  function deleteCard(lines, id) {
    const at = find(lines, id);
    if (!at || isRemaining(at.card)) return false;
    if (isHolder(at.card) && [...cards(at.card.content)].some(c => isRemaining(c.card))) return false;
    const parent = at.parent;
    if (parent && parent.show === "submenu" && parent.content.filter(e => e && !isDividerEntry(e)).length === 1) {
      delete parent.content;
      delete parent.show;
      parent.rules = at.card.rules || [];
      return true;
    }
    takeOut(lines, id);
    return true;
  }

  // Dexmenu's own item as a card of its own (an earlier layout's; plan 12 turned it into a rule): no rules.
  function isOwn(card) { return typeof card.own === "string"; }
  function addNote(layout, lines) {
    const card = { id: newId(layout), note: "" };
    lines.push(card);
    return card;
  }

  // A new card: beside a card (as a drop after it), or at the end of a container (parentId, or the top).
  function addCard(layout, lines, parentId, besideId) {
    const card = { id: newId(layout), card: "New card", rules: [] };
    if (besideId) {
      lines.push(card);
      moveCardNext(lines, card.id, besideId, "after");
    } else (containerOf(lines, parentId) || lines).push(card);
    return card;
  }

  // A card holding cards without a style (plan 11 3.5 "+ Group"), its cards under each other, at the top's end.
  function addGroup(layout, lines) {
    const card = { id: newId(layout), card: "Group", show: "column", content: [] };
    lines.push(card);
    return card;
  }

  // An entry just added (a card, a note, a group or a divider) moved to just after the entry afterId (a card, a
  // template of one: its card, or a divider) in that one's container, so inside the group or submenu it is in; a
  // divider after a card in a plain row: after the row. Nothing selected, the menu itself or an id not found: it
  // stays where it is (the top's end). Says whether it moved.
  function putAfter(lines, id, afterId) {
    const base = (afterId || "").replace(/~t\d+$|~m$/, "");
    if (!base || base === id) return false;
    const c = find(lines, id), d = c ? null : findDivider(lines, id);
    const entry = c ? c.card : d ? d.entry : null;
    if (!entry || (c && contains(c.card, base))) return false;
    if (!find(lines, base) && !findDivider(lines, base)) return false;
    (c ? c.lines : d.lines).splice(c ? c.lineIndex : d.index, 1);
    let at = find(lines, base);
    if (at && d && at.parent && isPlainRow(at.parent)) at = find(lines, at.parent.id);
    if (at) at.lines.splice(at.lineIndex + 1, 0, entry);
    else {
      const ad = findDivider(lines, base);
      ad.lines.splice(ad.index + 1, 0, entry);
    }
    return true;
  }

  // A card made a card with a submenu: its rules go to a new first card in it.
  function makeMenu(layout, lines, id) {
    const t = find(lines, id).card;
    if (isHolder(t)) return false;
    const first = { id: newId(layout), card: t.card, rules: t.rules || [] };
    for (const k of ["title", "rename"]) if (t[k] !== undefined) { first[k] = t[k]; delete t[k]; }
    delete t.rules;
    t.show = "submenu";
    t.content = [first];
    return true;
  }

  // ---- copied between layouts (plan 05 3.6: Ctrl+C / Ctrl+V between editor windows) ---------------------------------

  // ---- the card panel's panels (plan 13): the groups of a card's fields, arranged by the user ---------------------

  const panelIds = ["names", "rules", "inside", "layout", "style"];
  const panelNames = { names: "Names", rules: "Rules", inside: "Inside", layout: "Layout", style: "Style" };

  // An arrangement: what stands under each other below the card's name, each { panel: id } on its own or
  // { tabs: [ [ids], [ids], ... ] }, a set of tabs, each tab its panels under each other. The first: every panel on its
  // own, in the order of panelIds.
  function defaultArrangement() { return panelIds.map(id => ({ panel: id })); }

  // An arrangement made whole (also one read back from storage, which may be anything): every panel once, unknown ones
  // and empty tabs dropped, a set of tabs left with one tab its panels on their own, a missing panel added at the end.
  function normalArrangement(arrangement) {
    const seen = new Set(), out = [];
    const take = id => typeof id === "string" && panelIds.includes(id) && !seen.has(id) && seen.add(id);
    for (const item of Array.isArray(arrangement) ? arrangement : []) {
      if (!item || typeof item !== "object") continue;
      if (typeof item.panel === "string") { if (take(item.panel)) out.push({ panel: item.panel }); continue; }
      if (!Array.isArray(item.tabs)) continue;
      const tabs = item.tabs.filter(Array.isArray).map(t => t.filter(take)).filter(t => t.length);
      if (tabs.length === 1) for (const id of tabs[0]) out.push({ panel: id });
      else if (tabs.length > 1) out.push({ tabs });
    }
    for (const id of panelIds) if (!seen.has(id)) out.push({ panel: id });
    return out;
  }

  // Where a panel is in an arrangement: { item, tab (-1 on its own), at (its place in the tab) }, or null.
  function locatePanel(arrangement, id) {
    for (let i = 0; i < arrangement.length; i++) {
      const item = arrangement[i];
      if (item.panel === id) return { item: i, tab: -1, at: 0 };
      if (item.tabs) for (let t = 0; t < item.tabs.length; t++) {
        const at = item.tabs[t].indexOf(id);
        if (at >= 0) return { item: i, tab: t, at };
      }
    }
    return null;
  }

  // The panel id moved (a new arrangement): target { kind, of, side } by the panel it is dropped on (of):
  //   "above" / "below": on its own above or below what of stands in (a panel on its own, or its set of tabs);
  //   "onto": of on its own and the panel become a set of tabs, a tab each (of in a set of tabs: as "tab");
  //   "tab": a new tab after the tab holding of (of on its own: as "onto");
  //   "inTab": into the tab holding of, before (side "above") or after it (of on its own: as "above" / "below").
  function arrangePanel(arrangement, id, target) {
    const arr = normalArrangement(JSON.parse(JSON.stringify(arrangement)));
    if (!target || target.of === id || !panelIds.includes(id)) return arr;
    // taken out first; a set left with one tab stays a set until the end, so the target's place holds
    const from = locatePanel(arr, id);
    if (from.tab < 0) arr.splice(from.item, 1);
    else {
      const tabs = arr[from.item].tabs;
      tabs[from.tab].splice(from.at, 1);
      if (!tabs[from.tab].length) tabs.splice(from.tab, 1);
    }
    const to = locatePanel(arr, target.of);
    if (!to) return normalArrangement(arr);
    let kind = target.kind;
    if (to.tab < 0 && kind === "tab") kind = "onto";
    if (to.tab >= 0 && kind === "onto") kind = "tab";
    if (to.tab < 0 && kind === "inTab") kind = target.side === "below" ? "below" : "above";
    if (kind === "above") arr.splice(to.item, 0, { panel: id });
    else if (kind === "below") arr.splice(to.item + 1, 0, { panel: id });
    else if (kind === "onto") arr[to.item] = { tabs: [[target.of], [id]] };
    else if (kind === "tab") arr[to.item].tabs.splice(to.tab + 1, 0, [id]);
    else if (kind === "inTab") arr[to.item].tabs[to.tab].splice(to.at + (target.side === "below" ? 1 : 0), 0, id);
    return normalArrangement(arr);
  }

  // A tab's name: its panels' names joined ("Layout/Style"), only those shown.
  function tabName(tab, shown) { return tab.filter(id => !shown || shown.includes(id)).map(id => panelNames[id]).join("/"); }

  // Whether a card has anything of its own set in a panel's fields (its mark). The Rules panel shows its count instead.
  const panelKeys = {
    names: ["title", "rename", "extra", "extraAt", "icon", "hint", "comment"],
    rules: ["skipDuplicates"],
    inside: ["buttons", "submenus"],
    layout: ["weight", "minWidth", "height", "wrap", "cardFit"],
    style: ["background", "foreground", "border", "borderWidth", "radius", "hover", "pressed"],
  };
  function panelSet(card, id) { return (panelKeys[id] || []).some(k => card[k] !== undefined); }

  // A card's style, what "Copy style" takes and "Paste style" puts on another card: its look (background, text
  // colour, border, radius, 3D border, shadow, the hover and pressed look, a note's font) and how it sits and opens
  // (height, square, wrap, fit in line, extra text at, submenus open). Not its name, texts, icon, rules or what it holds.
  const styleKeys = ["background", "foreground", "border", "borderWidth", "radius", "border3d", "dividerTop", "dividerBottom",
    "shadow", "font", "hover", "pressed", "disabled", "height", "square", "wrap", "cardFit", "extraAt", "submenus"];
  function styleOf(card) {
    const style = {};
    for (const k of styleKeys) if (card[k] !== undefined) style[k] = JSON.parse(JSON.stringify(card[k]));
    return style;
  }
  // The card's style replaced by this one: what the style does not have, the card loses too (the theme's again).
  function applyStyle(card, style) {
    for (const k of styleKeys) {
      if (style[k] !== undefined) card[k] = JSON.parse(JSON.stringify(style[k])); else delete card[k];
    }
  }

  // Whether a card can take a template: a card with rules (not the remaining card, a note, or one holding cards).
  function canTakeTemplate(card) {
    return !!card && !isHolder(card) && !isNote(card) && !isRemaining(card) && !isOwn(card);
  }

  // What the clipboard's text holds: "card", "divider", "rule", "style", "template", or "" (nothing of Dexmenu's).
  function clipType(text) {
    try { const d = JSON.parse(text); return d && typeof d.dexmenu === "string" && d.item ? d.dexmenu : ""; } catch (e) { return ""; }
  }

  // Whether a card can take a pasted card inside it: one holding cards (it joins them), or one with rules (it becomes
  // a card with a submenu, its rules in the first card, as when a card is dropped onto it); not a note, Dexmenu's own
  // item or the remaining card.
  function canHold(card) {
    return isHolder(card) || (!isNote(card) && !isOwn(card) && !isRemaining(card));
  }

  // A copied card pasted as a duplicate (new ids, its rules at the end of the priority list): inside the card into
  // (canHold), or at the top at index. What was pasted, or null.
  function pasteCard(layout, lines, text, where) {
    if (clipType(text) !== "card") return null;
    if (where.into) {
      const target = find(lines, where.into);
      if (!target || !canHold(target.card)) return null;
    }
    const item = paste(layout, lines, text, null, null);
    if (!item) return null;
    const ok = where.into ? dropOnCard(layout, lines, item.id, where.into) : moveCard(lines, item.id, null, where.index);
    if (!ok) { deleteCard(lines, item.id); return null; }
    renumber(lines);
    return item;
  }

  // What goes on the clipboard: { dexmenu: "card" | "divider" | "rule" | "style", item }, a deep copy.
  function clip(type, item) { return JSON.stringify({ dexmenu: type, item: JSON.parse(JSON.stringify(item)) }); }

  // A card, a divider or a rule from the clipboard into this layout. A card (with what it holds) gets new ids and its
  // rules places at the end of the priority list; it goes after the card afterId (a card in a plain row: after the
  // row), or at the end of the top. The remaining card is never pasted (each layout has its own). A rule goes to the
  // end of a card with rules (onto), at the end of the priority list. What was pasted, or null.
  function paste(layout, lines, text, afterId, onto) {
    let data;
    try { data = JSON.parse(text); } catch (e) { return null; }
    if (!data || typeof data.dexmenu !== "string" || !data.item) return null;
    const item = data.item;
    let nextId = +newId(layout).slice(1);   // counted on: the pasted items are not in the layout yet
    const fresh = () => "c" + nextId++;
    if (data.dexmenu === "style") {
      if (!onto || isRemaining(onto)) return null;
      applyStyle(onto, item);
      return onto;
    }
    if (data.dexmenu === "template") {
      // a template (plan 11 3.1): a copy added to the card's templates (a card with rules)
      if (!canTakeTemplate(onto)) return null;
      onto.templates = onto.templates || [];
      onto.templates.push(item);
      return item;
    }
    if (data.dexmenu === "rule") {
      if (!onto || isHolder(onto) || isRemaining(onto) || item === "remaining") return null;
      delete item.priority;
      onto.rules = onto.rules || [];
      onto.rules.push(item);
      item.priority = ruleList(lines).length + 1;
      renumber(lines);
      return item;
    }
    if (data.dexmenu !== "card" && data.dexmenu !== "divider") return null;
    if (data.dexmenu === "card") {
      const all = [item, ...(isHolder(item) ? [...cards(item.content)].map(a => a.card) : [])];
      if (all.some(isRemaining)) return null;
      let next = ruleList(lines).length + 1;
      for (const c of all) {
        c.id = "";
        for (const r of c.rules || []) if (r !== "remaining") r.priority = next++;
      }
      for (const c of all) c.id = fresh();
      if (isHolder(item)) for (const d of dividers(item.content)) d.entry.id = fresh();
    } else item.id = fresh();
    let at = afterId ? find(lines, afterId) : null;
    if (at && at.parent && isPlainRow(at.parent)) at = find(lines, at.parent.id);
    if (at) at.lines.splice(at.lineIndex + 1, 0, item); else lines.push(item);
    renumber(lines);
    return item;
  }

  // The layout's form (format 2, plan 11): { format: 2, menu: { content } }. The editor reads and writes only that; an
  // older file is not converted here (that was done once, tools/convert-layouts-to-format-2.py): it is not opened.
  const formatVersion = 2;
  function upToDate(layout) {
    if (layout && layout.format === formatVersion && layout.menu && Array.isArray(layout.menu.content))
      return { layout, changed: false };
    return { layout: null, changed: false, error: "This layout is not in the current form (format " + formatVersion +
      "): convert it once with tools/convert-layouts-to-format-2.py." };
  }

  function remainingCount(lines) {
    let n = 0;
    for (const at of cards(lines)) if (isRemaining(at.card)) n++;
    return n;
  }

  // JSON with // comments: a comment ends the line, except inside a string (as the DLL).
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

  // A path with the folder it starts in written as its variable (plan 14 3.3): under AppData %APPDATA%, else under the
  // user's profile %USERPROFILE%; else as it is. Folders compared without case, as Windows does.
  function withVariables(path, appdata, userprofile) {
    for (const [dir, name] of [[appdata, "%APPDATA%"], [userprofile, "%USERPROFILE%"]]) {
      if (!dir) continue;
      const d = dir.replace(/[\\/]+$/, "");
      if (path.length > d.length && path.slice(0, d.length).toLowerCase() === d.toLowerCase() && /[\\/]/.test(path[d.length]))
        return name + path.slice(d.length);
    }
    return path;
  }

  return { withVariables, canTakeTemplate, isHolder, isRow, isPlainRow, isDividerEntry, rootOf, containerOf, addGroup, putAfter, panelIds, panelNames, defaultArrangement, normalArrangement, arrangePanel, tabName, panelSet, styleOf, applyStyle, clipType, canHold, pasteCard, matchKinds, isRemaining, isNote, addNote, isOwn, cards, find, newId, ensureIds, ruleProblem, rankProblem, statesOf, colorState, colorValue, colorCss, fillState, fillValue,
    ruleType, setRuleType, useless, ruleList, renumber, moveRule, moveCardRule, moveRuleToCard,
    addRule, deleteRule, takeOut, dropOnCard, moveCard, moveCardNext, deleteCard,
    dividers, findDivider, addDivider, addSearch, deleteDivider, moveDivider, moveDividerNext, upToDate, formatVersion, clip, paste, addCard, makeMenu, remainingCount, withoutComments };
})();

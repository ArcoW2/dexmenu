// The layout as the editor changes it (docs/plans/02-PLAN-own-menu.md 3.3, 3.5; plan 00 step 5): pure functions on
// the parsed layout, no page. A layout: { "<kind>": [ { "line": [ card, ... ] }, ... ], ... }. A card: { id, card
// (its name), rules: [ ... ] } or { id, card, menu: [ lines ] }, with title, extra, rename where given. The remaining
// card's rule is the text "remaining"; every kind has exactly one. Every other rule has a priority (the priority
// list, lower first). Tested by selftest.js (DexmenuSettings.exe --selftest).
"use strict";

const LayoutModel = (() => {
  const matchKinds = ["equals", "contains", "startsWith", "endsWith", "wildcard", "regex", "any"];

  function isRemaining(card) { return Array.isArray(card.rules) && card.rules.includes("remaining"); }

  // Every card of some lines, depth first, with where it is.
  function* cards(lines, parent = null) {
    for (let li = 0; li < lines.length; li++) {
      const entry = lines[li];
      if (!entry.line) continue;
      for (let ci = 0; ci < entry.line.length; ci++) {
        const card = entry.line[ci];
        yield { card, lines, lineIndex: li, cardIndex: ci, parent };
        if (card.menu) yield* cards(card.menu, card);
      }
    }
  }

  function find(lines, id) {
    for (const at of cards(lines)) if (at.card.id === id) return at;
    return null;
  }

  function contains(card, id) {
    if (!card.menu) return false;
    for (const at of cards(card.menu)) if (at.card.id === id) return true;
    return false;
  }

  function allCards(layout) {
    const all = [];
    for (const kind of Object.keys(layout)) if (Array.isArray(layout[kind])) for (const at of cards(layout[kind])) all.push(at.card);
    return all;
  }

  function newId(layout) {
    let max = 0;
    for (const c of allCards(layout)) { const m = /^c(\d+)$/.exec(c.id || ""); if (m) max = Math.max(max, +m[1]); }
    return "c" + (max + 1);
  }

  // Ids on every card and a priority on every rule, so the editor, the file and the DLL name the same things.
  function ensureIds(layout) {
    let next = +newId(layout).slice(1);
    for (const c of allCards(layout)) if (!c.id) c.id = "c" + next++;
    for (const kind of Object.keys(layout)) if (Array.isArray(layout[kind])) renumber(layout[kind]);
    return layout;
  }

  // ---- rules ----------------------------------------------------------------------------------------------------

  function ruleProblem(rule) {
    if (rule === "remaining") return "";
    if (typeof rule !== "object" || rule === null) return "a rule is an object";
    if (rule.verb !== undefined) return "a rule on the verb is not yet possible";
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
    if (rule.states !== undefined && (!Array.isArray(rule.states) || rule.states.some(s => s !== "enabled" && s !== "disabled")))
      return "states: enabled and/or disabled";
    return "";
  }

  // A card that can never show anything (outlined red): a card with rules but none, or with an invalid rule.
  function useless(card) {
    if (card.menu) return false;
    const rules = card.rules || [];
    return rules.length === 0 || rules.some(r => ruleProblem(r) !== "");
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

  function renumber(lines) {
    ruleList(lines).forEach((r, i) => { r.rule.priority = i + 1; });
  }

  // The rule at place `from` in the priority list moved to place `to`.
  function moveRule(lines, from, to) {
    const list = ruleList(lines);
    const [moved] = list.splice(from, 1);
    list.splice(to, 0, moved);
    list.forEach((r, i) => { r.rule.priority = i + 1; });
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

  // A card taken out of its place: its line goes when empty; a submenu left empty makes its parent a card with rules
  // that has none (it finds nothing and is outlined red).
  function takeOut(lines, id) {
    const at = find(lines, id);
    if (!at) return null;
    const line = at.lines[at.lineIndex].line;
    line.splice(at.cardIndex, 1);
    if (line.length === 0) at.lines.splice(at.lineIndex, 1);
    if (at.parent && !at.parent.menu.some(e => e.line && e.line.length)) {
      delete at.parent.menu;
      at.parent.rules = [];
    }
    return at.card;
  }

  // A card dropped onto another card: a card with rules becomes a card with a menu, its rules in a new first card
  // (nothing lost), the dropped card after it; a card with a menu takes the dropped card as a new line at its end.
  function dropOnCard(layout, lines, draggedId, targetId) {
    if (draggedId === targetId) return false;
    const dragged = find(lines, draggedId), target = find(lines, targetId);
    if (!dragged || !target || contains(dragged.card, targetId)) return false;
    const card = takeOut(lines, draggedId);
    const t = find(lines, targetId).card;
    if (t.menu) t.menu.push({ line: [card] });
    else {
      const first = { id: newId(layout), card: t.card, rules: t.rules || [] };
      for (const k of ["title", "rename"]) if (t[k] !== undefined) { first[k] = t[k]; delete t[k]; }
      delete t.rules;
      t.menu = [{ line: [first] }, { line: [card] }];
    }
    return true;
  }

  // A card moved to a level (parentId: a card with a menu, or null for the top), as a new line at lineIndex, or into
  // an existing line (intoLine: that line's index) at its end.
  function moveCard(lines, draggedId, parentId, lineIndex, intoLine = false) {
    const dragged = find(lines, draggedId);
    if (!dragged) return false;
    if (parentId && (parentId === draggedId || contains(dragged.card, parentId))) return false;
    const levelOf = () => parentId ? find(lines, parentId).card.menu : lines;
    const level = levelOf();
    if (parentId && !level) return false;
    const anchor = level[lineIndex];   // the line it goes before / into, kept across taking it out
    const card = takeOut(lines, draggedId);
    const now = parentId ? (find(lines, parentId).card.menu || (find(lines, parentId).card.menu = [])) : lines;
    if (parentId) delete find(lines, parentId).card.rules;
    let at = anchor ? now.indexOf(anchor) : -1;
    if (intoLine && at >= 0) now[at].line.push(card);
    else if (at >= 0) now.splice(at, 0, { line: [card] });
    else now.push({ line: [card] });
    return true;
  }

  // Deleting a card: never the remaining card; the last card of a submenu gives its rules to its parent, which becomes
  // a card with rules again (the reverse of dropping a card onto a card).
  function deleteCard(lines, id) {
    const at = find(lines, id);
    if (!at || isRemaining(at.card)) return false;
    if (at.card.menu && [...cards(at.card.menu)].some(c => isRemaining(c.card))) return false;   // it holds the remaining card
    const last = at.parent && at.parent.menu.reduce((n, e) => n + (e.line ? e.line.length : 0), 0) === 1;
    if (last) {
      const parent = at.parent;
      delete parent.menu;
      parent.rules = at.card.rules || [];
      return true;
    }
    takeOut(lines, id);
    return true;
  }

  function addCard(layout, lines, parentId, besideId) {
    const card = { id: newId(layout), card: "New card", rules: [] };
    if (besideId) {
      const at = find(lines, besideId);
      at.lines[at.lineIndex].line.splice(at.cardIndex + 1, 0, card);
    } else {
      const level = parentId ? find(lines, parentId).card.menu : lines;
      level.push({ line: [card] });
    }
    return card;
  }

  // A card made a card with a menu: its rules go to a new first card in the menu.
  function makeMenu(layout, lines, id) {
    const t = find(lines, id).card;
    if (t.menu) return false;
    const first = { id: newId(layout), card: t.card, rules: t.rules || [] };
    for (const k of ["title", "rename"]) if (t[k] !== undefined) { first[k] = t[k]; delete t[k]; }
    delete t.rules;
    t.menu = [{ line: [first] }];
    return true;
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

  return { matchKinds, isRemaining, cards, find, newId, ensureIds, ruleProblem, useless, ruleList, renumber, moveRule,
    addRule, deleteRule, takeOut, dropOnCard, moveCard, deleteCard, addCard, makeMenu, remainingCount, withoutComments };
})();

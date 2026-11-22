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

  // Every divider entry of some lines, depth first: { entry, lines, index, parent }. A divider: { id, divider: "<text>"
  // or "", align: "left" | "center" | "right" }, between lines of cards.
  function* dividers(lines, parent = null) {
    for (let i = 0; i < lines.length; i++) {
      const entry = lines[i];
      if (entry.divider !== undefined) yield { entry, lines, index: i, parent };
      if (entry.line) for (const card of entry.line) if (card.menu) yield* dividers(card.menu, card);
    }
  }
  function allDividers(layout) {
    const all = [];
    for (const kind of Object.keys(layout)) if (Array.isArray(layout[kind])) for (const d of dividers(layout[kind])) all.push(d.entry);
    return all;
  }
  function findDivider(lines, id) {
    for (const d of dividers(lines)) if (d.entry.id === id) return d;
    return null;
  }

  function newId(layout) {
    let max = 0;
    for (const c of [...allCards(layout), ...allDividers(layout)]) { const m = /^c(\d+)$/.exec(c.id || ""); if (m) max = Math.max(max, +m[1]); }
    return "c" + (max + 1);
  }

  // Ids on every card, each once, and a priority on every rule, so the editor, the file and the DLL name the same
  // things. A card whose id an earlier card has already gets a new one (a layout saved with a duplicate).
  function ensureIds(layout) {
    let next = +newId(layout).slice(1);
    const seen = new Set();
    for (const c of [...allCards(layout), ...allDividers(layout)]) {
      if (!c.id || seen.has(c.id)) c.id = "c" + next++;
      seen.add(c.id);
    }
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
    if (rule.consume !== undefined && typeof rule.consume !== "boolean") return "consume is true or false";
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
    if (!rule || rule === "remaining" || !toCard || toCard.menu || isRemaining(toCard)) return null;
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
    const firstId = newId(layout);   // before the dragged card is taken out: else its id counts as free
    const card = takeOut(lines, draggedId);
    const t = find(lines, targetId).card;
    if (t.menu) t.menu.push({ line: [card] });
    else {
      const first = { id: firstId, card: t.card, rules: t.rules || [] };
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
    // the lines it goes before / into, kept across taking it out: its own line may go with it (it was alone there),
    // then the line after that one is the place
    const intoAnchor = intoLine ? level[lineIndex] : null;
    const anchors = level.slice(lineIndex);
    const card = takeOut(lines, draggedId);
    const now = parentId ? (find(lines, parentId).card.menu || (find(lines, parentId).card.menu = [])) : lines;
    if (parentId) delete find(lines, parentId).card.rules;
    const survivor = anchors.find(a => now.includes(a));
    let at = survivor ? now.indexOf(survivor) : -1;
    if (intoLine && intoAnchor && now.includes(intoAnchor)) now[now.indexOf(intoAnchor)].line.push(card);
    else if (at >= 0) now.splice(at, 0, { line: [card] });
    else now.push({ line: [card] });
    return true;
  }

  // A card dropped next to another card: beside it in its line (side "before" / "after"), or on a line of its own
  // just above or below that card's line ("above" / "below": a card that shared a line becomes menu-wide again).
  function moveCardNext(lines, draggedId, targetId, side) {
    if (draggedId === targetId) return false;
    const dragged = find(lines, draggedId), target = find(lines, targetId);
    if (!dragged || !target || contains(dragged.card, targetId)) return false;
    if (side === "above" || side === "below") {
      const parentId = target.parent ? target.parent.id : null;
      return moveCard(lines, draggedId, parentId, target.lineIndex + (side === "below" ? 1 : 0));
    }
    const card = takeOut(lines, draggedId);
    const t = find(lines, targetId);
    const line = t.lines[t.lineIndex].line;
    line.splice(t.cardIndex + (side === "after" ? 1 : 0), 0, card);
    return true;
  }

  // ---- dividers ---------------------------------------------------------------------------------------------------

  function addDivider(layout, lines, parentId) {
    const entry = { id: newId(layout), divider: "" };
    const level = parentId ? find(lines, parentId).card.menu : lines;
    level.push(entry);
    return entry;
  }

  function deleteDivider(lines, id) {
    const d = findDivider(lines, id);
    if (!d) return false;
    d.lines.splice(d.index, 1);
    return true;
  }

  // A divider moved to a level (parentId: a card with a menu, or null for the top) before the entry at lineIndex
  // (counted before it was taken out), or to the level's end.
  function moveDivider(lines, id, parentId, lineIndex) {
    const d = findDivider(lines, id);
    if (!d) return false;
    const level = parentId ? (find(lines, parentId) || {}).card?.menu : lines;
    if (!level) return false;
    const anchors = level.slice(lineIndex).filter(e => e !== d.entry);
    d.lines.splice(d.index, 1);
    const survivor = anchors.find(a => level.includes(a));
    const at = survivor ? level.indexOf(survivor) : level.length;
    level.splice(at, 0, d.entry);
    return true;
  }

  // A divider dropped on a card's top or bottom edge: just above or below that card's line.
  function moveDividerNext(lines, id, targetCardId, side) {
    const target = find(lines, targetCardId);
    if (!target) return false;
    return moveDivider(lines, id, target.parent ? target.parent.id : null, target.lineIndex + (side === "below" ? 1 : 0));
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

  return { matchKinds, isRemaining, cards, find, newId, ensureIds, ruleProblem, useless, ruleList, renumber, moveRule, moveCardRule, moveRuleToCard,
    addRule, deleteRule, takeOut, dropOnCard, moveCard, moveCardNext, deleteCard,
    dividers, findDivider, addDivider, deleteDivider, moveDivider, moveDividerNext, addCard, makeMenu, remainingCount, withoutComments };
})();

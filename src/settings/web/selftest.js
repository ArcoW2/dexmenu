// The editor's operations tested (plan 02 3.12 "Editing"; plan 00 step 5), run in WebView2 by
// DexmenuSettings.exe --selftest <file>: each check PASS / FAIL, the failures counted; the app writes them to the file
// and exits with that count.
"use strict";

(() => {
  const M = LayoutModel;
  const out = [];
  let failures = 0;
  const check = (ok, what) => { out.push((ok ? "PASS " : "FAIL ") + what); if (!ok) failures++; };
  const titles = lines => lines.map(e => e.line.map(c => c.card + (c.menu ? "[" + titles(c.menu) + "]" : "")).join(" | ")).join(" / ");

  function sample() {
    return M.ensureIds({ default: [
      { line: [ { card: "LexPen", rules: [ { name: { contains: "LexPen" } } ] } ] },
      { line: [ { card: "Clip", rules: [ { name: { any: ["Cut", "Copy"] } } ] }, { card: "Zip", rules: [ { name: { startsWith: "7" } } ] } ] },
      { line: [ { card: "Tools", menu: [ { line: [ { card: "Git", rules: [ { name: { contains: "Git" } } ] } ] } ] } ] },
      { line: [ { card: "Rest", rules: [ "remaining" ] } ] }
    ] });
  }
  const id = (layout, name) => [...M.cards(layout.default)].find(a => a.card.card === name).card.id;

  // ids and priorities
  let L = sample();
  check([...M.cards(L.default)].every(a => /^c\d+$/.test(a.card.id)), "every card gets an id");
  check(M.ruleList(L.default).map(r => r.rule.priority).join() === "1,2,3,4", "every rule a priority, in the layout's order");

  // a card dropped onto a card with rules: that card becomes a card with a menu, its rules in a new first card
  L = sample();
  const clipRules = JSON.stringify([...M.cards(L.default)].find(a => a.card.card === "Clip").card.rules);
  check(M.dropOnCard(L, L.default, id(L, "LexPen"), id(L, "Clip")), "drop LexPen onto Clip");
  check(titles(L.default) === "Clip[Clip / LexPen] | Zip / Tools[Git] / Rest", "Clip has a menu: a first card Clip, then LexPen; LexPen's line gone: " + titles(L.default));
  const clip = [...M.cards(L.default)].find(a => a.card.card === "Clip" && a.card.menu).card;
  check(!clip.rules && JSON.stringify(clip.menu[0].line[0].rules) === clipRules, "Clip's rules moved to the first card in its menu, not lost");

  // the newest card dropped onto a card: the card made first in the menu gets an id of its own, not the dropped one's
  L = sample();
  const fresh = M.addCard(L, L.default, null);
  check(M.dropOnCard(L, L.default, fresh.id, id(L, "Zip")), "a new card dropped onto Zip");
  const ids = [...M.cards(L.default)].map(a => a.card.id);
  check(new Set(ids).size === ids.length, "every card's id once: " + ids.join());
  // a layout saved with a duplicate id: the later card gets a new one when opened
  L = M.ensureIds({ default: [ { line: [ { id: "c2", card: "A", menu: [ { line: [ { id: "c3", card: "B", rules: [] } ] } ] } ] },
    { line: [ { id: "c2", card: "Rest", rules: [ "remaining" ] } ] } ] });
  check(L.default[0].line[0].id === "c2" && L.default[1].line[0].id === "c4", "a duplicate id made unique: " + L.default[1].line[0].id);

  // onto a card with a menu: a new line at its end
  L = sample();
  M.dropOnCard(L, L.default, id(L, "Zip"), id(L, "Tools"));
  check(titles(L.default) === "LexPen / Clip / Tools[Git / Zip] / Rest", "drop Zip onto Tools (a menu): Zip joins it: " + titles(L.default));

  // not into itself
  L = sample();
  check(!M.dropOnCard(L, L.default, id(L, "Tools"), id(L, "Git")), "a card is not dropped into its own menu");

  // the last card of a submenu deleted: its rules go to the parent
  L = sample();
  const gitRules = JSON.stringify([...M.cards(L.default)].find(a => a.card.card === "Git").card.rules);
  check(M.deleteCard(L.default, id(L, "Git")), "delete Git, the last card of Tools' menu");
  const tools = [...M.cards(L.default)].find(a => a.card.card === "Tools").card;
  check(!tools.menu && JSON.stringify(tools.rules) === gitRules, "Tools is a card with rules again, with Git's rules");

  // the last card dragged out of a submenu: the parent keeps no rules and is outlined red
  L = sample();
  check(M.moveCard(L.default, id(L, "Git"), null, 0), "drag Git out of Tools, to the top");
  const tools2 = [...M.cards(L.default)].find(a => a.card.card === "Tools").card;
  check(!tools2.menu && tools2.rules.length === 0 && M.useless(tools2), "Tools: a card with rules but none, useless (red)");
  check(titles(L.default) === "Git / LexPen / Clip | Zip / Tools / Rest", "Git is the first line now: " + titles(L.default));

  // the remaining card: moved, never deleted, always one
  L = sample();
  check(!M.deleteCard(L.default, id(L, "Rest")), "the remaining card cannot be deleted");
  check(M.moveCard(L.default, id(L, "Rest"), id(L, "Tools"), 1), "the remaining card moved into Tools' menu");
  check(M.remainingCount(L.default) === 1 && titles(L.default) === "LexPen / Clip | Zip / Tools[Git / Rest]", "still exactly one, now in Tools: " + titles(L.default));
  check(!M.deleteCard(L.default, id(L, "Tools")), "a card holding the remaining card cannot be deleted");
  check(M.moveCard(L.default, id(L, "Rest"), null, 99), "and back to the top");
  check(M.remainingCount(L.default) === 1 && titles(L.default) === "LexPen / Clip | Zip / Tools[Git] / Rest", "at the end of the top: " + titles(L.default));

  // a card moved into a line (beside others)
  L = sample();
  check(M.moveCard(L.default, id(L, "LexPen"), null, 1, true), "LexPen moved into Clip's line");
  check(titles(L.default) === "Clip | Zip | LexPen / Tools[Git] / Rest", "three cards on one line: " + titles(L.default));

  // a card alone on its line moved to the gap before that line, or after it: it stays there (not to the end)
  L = sample();
  check(M.moveCard(L.default, id(L, "LexPen"), null, 0), "LexPen dropped on the gap before its own line");
  check(titles(L.default) === "LexPen / Clip | Zip / Tools[Git] / Rest", "LexPen stays first: " + titles(L.default));
  L = sample();
  check(M.moveCard(L.default, id(L, "LexPen"), null, 1), "LexPen dropped on the gap after its own line");
  check(titles(L.default) === "LexPen / Clip | Zip / Tools[Git] / Rest", "LexPen still first: " + titles(L.default));
  L = sample();
  check(M.moveCard(L.default, id(L, "Tools"), null, 3), "Tools dropped on the gap before Rest");
  check(titles(L.default) === "LexPen / Clip | Zip / Tools[Git] / Rest", "Tools stays before Rest: " + titles(L.default));
  L = sample();
  check(M.moveCard(L.default, id(L, "Zip"), null, 0), "Zip from a shared line to the top");
  check(titles(L.default) === "Zip / LexPen / Clip / Tools[Git] / Rest", "Zip first, Clip alone: " + titles(L.default));

  // a card dropped next to another: beside it in its line, or on a line of its own above / below that line
  L = sample();
  check(M.moveCardNext(L.default, id(L, "LexPen"), id(L, "Zip"), "before"), "LexPen dropped left of Zip");
  check(titles(L.default) === "Clip | LexPen | Zip / Tools[Git] / Rest", "LexPen between Clip and Zip: " + titles(L.default));
  check(M.moveCardNext(L.default, id(L, "LexPen"), id(L, "Zip"), "after"), "LexPen dropped right of Zip");
  check(titles(L.default) === "Clip | Zip | LexPen / Tools[Git] / Rest", "LexPen after Zip: " + titles(L.default));
  check(M.moveCardNext(L.default, id(L, "LexPen"), id(L, "Clip"), "above"), "LexPen dropped above Clip's line");
  check(titles(L.default) === "LexPen / Clip | Zip / Tools[Git] / Rest", "LexPen menu-wide again, above: " + titles(L.default));
  check(M.moveCardNext(L.default, id(L, "Zip"), id(L, "Clip"), "below"), "Zip dropped below its own line");
  check(titles(L.default) === "LexPen / Clip / Zip / Tools[Git] / Rest", "Zip on a line of its own: " + titles(L.default));
  check(M.moveCardNext(L.default, id(L, "Rest"), id(L, "Git"), "after"), "the remaining card beside Git, in Tools' menu");
  check(titles(L.default) === "LexPen / Clip / Zip / Tools[Git | Rest]", "Rest beside Git: " + titles(L.default));
  check(!M.moveCardNext(L.default, id(L, "Tools"), id(L, "Git"), "before"), "a card not next to a card in its own menu");

  // dividers: added, moved between lines and into a card's menu, deleted; ids of their own
  L = sample();
  const lineNames = lines => lines.map(e => e.divider !== undefined ? "D(" + e.divider + ")" : e.line.map(c => c.card).join("|")).join(" / ");
  const dv = M.addDivider(L, L.default, null);
  check(/^c\d+$/.test(dv.id) && lineNames(L.default) === "LexPen / Clip|Zip / Tools / Rest / D()", "a divider added at the end: " + lineNames(L.default));
  dv.divider = "Programs";
  check(M.moveDivider(L.default, dv.id, null, 1), "the divider moved before Clip's line");
  check(lineNames(L.default) === "LexPen / D(Programs) / Clip|Zip / Tools / Rest", "between LexPen and Clip: " + lineNames(L.default));
  check(M.moveDividerNext(L.default, dv.id, id(L, "Git"), "above"), "the divider moved above Git, in Tools' menu");
  check(lineNames([...M.cards(L.default)].find(a => a.card.card === "Tools").card.menu) === "D(Programs) / Git", "in Tools' menu: first");
  check(M.moveDivider(L.default, dv.id, null, 0) && lineNames(L.default) === "D(Programs) / LexPen / Clip|Zip / Tools / Rest", "back to the top: " + lineNames(L.default));
  const ids2 = [...[...M.cards(L.default)].map(a => a.card.id), ...[...M.dividers(L.default)].map(d => d.entry.id)];
  check(new Set(ids2).size === ids2.length, "a divider's id is not a card's");
  check(M.deleteDivider(L.default, dv.id) && lineNames(L.default) === "LexPen / Clip|Zip / Tools / Rest", "the divider deleted");

  // the priority list
  L = sample();
  M.moveRule(L.default, 3, 0);
  check(M.ruleList(L.default).map(r => r.card.card).join() === "Git,LexPen,Clip,Zip", "Git's rule moved to the top of the priority list");
  check(M.ruleList(L.default).map(r => r.rule.priority).join() === "1,2,3,4", "priorities renumbered 1..n");
  M.moveRule(L.default, 0, 3);   // dropped on the last line of the list: to the end
  check(M.ruleList(L.default).map(r => r.card.card).join() === "LexPen,Clip,Zip,Git", "the first rule moved to the end of the list");
  const added = M.addRule(L.default, [...M.cards(L.default)].find(a => a.card.card === "Zip").card);
  check(added.priority === 5 && M.ruleList(L.default).length === 5, "a new rule goes at the end of the list");
  M.deleteRule(L.default, [...M.cards(L.default)].find(a => a.card.card === "Zip").card, 1);
  check(M.ruleList(L.default).length === 4, "a rule deleted");

  // a card's own rules reordered: they keep their places in the priority list, swapped among themselves
  L = M.ensureIds({ default: [
    { line: [ { card: "A", rules: [ { name: { equals: "a1" } }, { name: { equals: "a2" } } ] } ] },
    { line: [ { card: "B", rules: [ { name: { equals: "b1" } } ] } ] },
    { line: [ { card: "Rest", rules: [ "remaining" ] } ] }
  ] });
  const a = [...M.cards(L.default)].find(x => x.card.card === "A").card;
  M.moveRule(L.default, 2, 1);   // the list: a1, b1, a2
  check(M.ruleList(L.default).map(r => r.rule.name.equals).join() === "a1,b1,a2", "the list: a1, b1, a2");
  check(M.moveCardRule(L.default, a, 1, 0), "card A's second rule (a2) moved to its first place");
  check(M.ruleList(L.default).map(r => r.rule.name.equals).join() === "a2,b1,a1", "a2 took a1's place (#1), a1 a2's (#3); b1 stays #2");
  check(a.rules.map(r => r.name.equals).join() === "a2,a1" && a.rules.map(r => r.priority).join() === "1,3",
    "the card lists its rules in priority order: a2 #1, a1 #3");
  check(!M.moveCardRule(L.default, a, 0, 5), "a place beyond the card's rules: refused");

  // a rule moved or copied onto another card
  L = sample();
  const zipCard = () => [...M.cards(L.default)].find(x => x.card.card === "Zip").card;
  const lexCard = () => [...M.cards(L.default)].find(x => x.card.card === "LexPen").card;
  const moved = M.moveRuleToCard(L.default, zipCard(), 0, lexCard(), false);
  check(moved && lexCard().rules.length === 2 && zipCard().rules.length === 0, "Zip's rule moved onto LexPen");
  check(moved.priority === 3 && M.ruleList(L.default).map(r => r.rule.priority).join() === "1,2,3,4", "it keeps its place in the list (#3)");
  check(M.useless(zipCard()), "Zip has no rules left: outlined red");
  L = sample();
  const copied = M.moveRuleToCard(L.default, lexCard(), 0, zipCard(), true);
  check(copied && lexCard().rules.length === 1 && zipCard().rules.length === 2, "LexPen's rule copied onto Zip");
  check(M.ruleList(L.default).map(r => r.card.card).join() === "LexPen,Zip,Clip,Zip,Git", "the copy right after the original: " +
    M.ruleList(L.default).map(r => r.card.card).join());
  check(copied !== lexCard().rules[0] && JSON.stringify(copied.name) === JSON.stringify(lexCard().rules[0].name), "a copy, not the same rule");
  L = sample();
  const toolsCard = () => [...M.cards(L.default)].find(x => x.card.card === "Tools").card;
  const restCard = () => [...M.cards(L.default)].find(x => x.card.card === "Rest").card;
  check(!M.moveRuleToCard(L.default, lexCard(), 0, toolsCard(), false), "not onto a card with a menu");
  check(!M.moveRuleToCard(L.default, lexCard(), 0, restCard(), false), "not onto the remaining card");
  check(!M.moveRuleToCard(L.default, restCard(), 0, lexCard(), false), "the remaining card's rule is not moved");
  check(!M.moveRuleToCard(L.default, lexCard(), 0, lexCard(), false), "moved onto its own card: nothing");

  // useless cards and rule problems
  check(M.useless({ card: "x", rules: [] }), "no rules: useless");
  check(M.useless({ card: "x", rules: [ { name: { regex: "(" } } ] }), "a regex that does not compile: useless");
  check(M.useless({ card: "x", rules: [ { name: { equals: "a" }, scope: "top", path: { equals: "b" } } ] }), "a scope and a path: useless");
  check(M.useless({ card: "x", rules: [ { name: { contains: "" } } ] }), "nothing to match: useless");
  check(!M.useless({ card: "x", rules: [ { name: { equals: "Cut" } } ] }), "a valid rule: not useless");
  check(!M.useless({ card: "x", rules: [ { name: { equals: "Cut" }, consume: false } ] }), "consume false: valid");
  check(M.useless({ card: "x", rules: [ { name: { equals: "Cut" }, consume: "no" } ] }), "consume not true or false: useless");
  check(!M.useless({ card: "x", menu: [] }), "a card with a menu: not outlined");

  // made a card with a menu
  L = sample();
  M.makeMenu(L, L.default, id(L, "Zip"));
  const zip = [...M.cards(L.default)].find(a => a.card.card === "Zip" && a.card.menu).card;
  check(zip && zip.menu[0].line[0].rules[0].name.startsWith === "7", "made a menu: its rules in the first card");

  // copied between layouts (plan 05 3.6): a card with its menu gets new ids and its rules at the end of the list; a rule
  // onto a card at the end; the remaining card never pasted
  {
    const from = sample(), to = sample();
    const tools = [...M.cards(from.default)].find(x => x.card.card === "Tools").card;
    const pasted = M.paste(to, to.default, M.clip("card", tools), id(to, "LexPen"));
    const ids = [...M.cards(to.default)].map(a => a.card.id);
    check(pasted && new Set(ids).size === ids.length, "a card with a menu pasted: every id new");
    check(titles(to.default) === "LexPen / Tools[Git] / Clip | Zip / Tools[Git] / Rest", "after LexPen's line: " + titles(to.default));
    check(M.ruleList(to.default).map(r => r.card.card).join() === "LexPen,Clip,Zip,Git,Git", "its rule at the end of the list");
    const rest = [...M.cards(from.default)].find(x => x.card.card === "Rest").card;
    check(!M.paste(to, to.default, M.clip("card", rest), null), "the remaining card is not pasted");
    const zip = [...M.cards(to.default)].find(x => x.card.card === "Zip").card;
    const lexRule = [...M.cards(from.default)].find(x => x.card.card === "LexPen").card.rules[0];
    check(M.paste(to, to.default, M.clip("rule", lexRule), null, zip) && zip.rules.length === 2
      && M.ruleList(to.default).slice(-1)[0].card === zip, "a rule pasted onto a card: at the end of the list");
    check(!M.paste(to, to.default, "not ours", null), "other clipboard text: nothing");
  }

  // note cards: added at the end, never useless, nothing dropped onto them, no rule onto them
  {
    const L2 = sample();
    const note = M.addNote(L2, L2.default);
    check(M.isNote(note) && !M.useless(note) && L2.default[L2.default.length - 1].line[0] === note, "a note added at the end, not outlined red");
    check(!M.dropOnCard(L2, L2.default, id(L2, "Zip"), note.id), "a card is not dropped onto a note");
    const lex = [...M.cards(L2.default)].find(x => x.card.card === "LexPen").card;
    check(!M.moveRuleToCard(L2.default, lex, 0, note, true), "a rule is not put on a note");
  }

  // the current form (plan 05 3.1): an older file brought to it by its default menu; a current one left as it is
  const old = M.upToDate({ default: [ { line: [ { card: "Rest", rules: [ "remaining" ] } ] } ], folder: [ { line: [] } ] });
  check(old.changed && old.layout.format === M.formatVersion && old.layout.lines[0].line[0].card === "Rest" && !old.layout.folder,
    "an older file: its default menu as the layout's lines, the other kinds gone, marked changed");
  const cur = M.upToDate({ format: M.formatVersion, lines: [] });
  check(!cur.changed, "a current file: unchanged");

  // a rule's type (plan 09 3.3): Name or Usage, the other type's keys taken out on a switch; the rank checked
  {
    const r = { name: { contains: "x" }, caseSensitive: true, scope: "anywhere", states: ["enabled"], also: true, priority: 2 };
    check(M.ruleType(r) === "name", "a rule with a name: type Name");
    M.setRuleType(r, "usage");
    check(M.ruleType(r) === "usage" && r.used === "most" && r.name === undefined && r.caseSensitive === undefined &&
      r.scope === undefined && r.states.length === 1 && r.also && r.priority === 2 && M.ruleProblem(r) === "",
      "to Usage: most used, the name, case sensitive and where taken out, the shared fields kept, valid");
    r.rank = "1-3";
    M.setRuleType(r, "name");
    check(M.ruleType(r) === "name" && r.used === undefined && r.rank === undefined && r.name.contains === "" && r.also,
      "back to Name: used and rank taken out, an empty contains");
    const used = rank => M.ruleProblem({ used: "recent", rank });
    check([undefined, 1, 3, "2", "1-3", "3-1", " 2 - 5 "].every(k => used(k) === ""),
      "a rank: none, a number, a text with one, a range, a range from high to low");
    check([0, -1, 1.5, "0", "0-3", "3-0", "x", "", "1-"].every(k => used(k) !== ""),
      "a wrong rank outlined red: 0 or lower, a fraction, text, half a range");
    check(M.ruleProblem({ used: "often" }) !== "" && M.ruleProblem({ used: "most", name: { equals: "a" } }) !== "",
      "an unknown use, or both a name and a use: outlined red");
    check(M.useless({ card: "U", rules: [ { used: "most", rank: 0 } ] }) && !M.useless({ card: "U", rules: [ { used: "most", rank: "3-1" } ] }),
      "a card with a wrong rank outlined red, with a reversed range not");
  }

  // a card's style copied and pasted onto another card
  {
    const from = { card: "A", rules: [ { name: { equals: "a" } } ], background: { gradient: ["accent", "surface"] }, radius: 8,
      hover: { background: "accent" }, height: 2, wrap: true, cardFit: "top", extraAt: "above", submenus: "under", icon: "E8C8", extra: "x" };
    const style = M.styleOf(from);
    check(Object.keys(style).sort().join() === "background,cardFit,extraAt,height,hover,radius,submenus,wrap",
      "a card's style: its look, height, wrap, fit, extra text at and submenus; not its name, icon, texts or rules");
    const L3 = M.ensureIds({ format: M.formatVersion, lines: [ { line: [ { card: "B", rules: [ { name: { equals: "b" } } ], border: "#ff0000", icon: "E700" } ] },
      { line: [ { card: "Rest", rules: [ "remaining" ] } ] } ] });
    const to = L3.lines[0].line[0];
    check(M.paste(L3, L3.lines, M.clip("style", style), null, to) === to && to.radius === 8 && to.wrap && to.border === undefined &&
      to.icon === "E700" && to.card === "B" && to.rules[0].name.equals === "b" && to.background !== from.background,
      "the style pasted: the card's look replaced (what the style does not set gone), its name, icon and rules kept, a copy");
    check(M.paste(L3, L3.lines, M.clip("style", style), null, L3.lines[1].line[0]) === null, "no style onto the remaining card");
  }

  // a card copied and pasted as a duplicate: at the top, at a place, inside a card; not inside a note
  {
    const L4 = M.ensureIds({ format: M.formatVersion, lines: [
      { line: [ { card: "A", rules: [ { name: { equals: "a" } } ] } ] },
      { line: [ { card: "M", menu: [ { line: [ { card: "In", rules: [ { name: { equals: "in" } } ] } ] } ] } ] },
      { line: [ { card: "N", note: "n" } ] },
      { line: [ { card: "Rest", rules: [ "remaining" ] } ] } ] });
    const names = () => L4.lines.map(e => e.line ? e.line.map(c => c.card).join("|") : "-").join(" / ");
    const a = L4.lines[0].line[0];
    const text = M.clip("card", a);
    check(M.clipType(text) === "card" && M.clipType("hello") === "" && M.clipType(M.clip("style", {})) === "style", "what the clipboard holds");
    const top = M.pasteCard(L4, L4.lines, text, { index: 0 });
    check(top && top.id !== a.id && names() === "A / A / M / N / Rest" && L4.lines[0].line[0] === top, "pasted at the top: a duplicate, its own id: " + names());
    const mid = M.pasteCard(L4, L4.lines, text, { index: 3 });
    check(mid && names() === "A / A / M / A / N / Rest", "pasted at a place: " + names());
    const m = L4.lines[2].line[0];
    const inside = M.pasteCard(L4, L4.lines, text, { into: m.id });
    check(inside && m.menu.length === 2 && m.menu[1].line[0] === inside, "pasted inside a card with a menu: it joins the menu");
    check(M.canHold(a) && !M.canHold(L4.lines[4].line[0]) && !M.canHold(L4.lines[5].line[0]) &&
      M.pasteCard(L4, L4.lines, text, { into: L4.lines[4].line[0].id }) === null, "not inside a note or the remaining card");
    const ids = [...M.cards(L4.lines)].map(c => c.card.id);
    check(new Set(ids).size === ids.length && M.ruleList(L4.lines).map(r => r.rule.priority).every((p, i) => p === i + 1),
      "every id once; the priorities 1..n");
  }

  // a line's cards moved together (the gutter's line drag): the first placed as a dragged card, the others after it
  {
    const L5 = M.ensureIds({ format: M.formatVersion, lines: [
      { line: [ { card: "A", rules: [ { name: { equals: "a" } } ] }, { card: "B", rules: [ { name: { equals: "b" } } ] } ] },
      { line: [ { card: "X", rules: [ { name: { equals: "x" } } ] } ] },
      { line: [ { card: "Rest", rules: [ "remaining" ] } ] } ] });
    const names = () => L5.lines.map(e => e.line.map(c => c.card).join("|")).join(" / ");
    const idOf = n => [...M.cards(L5.lines)].find(c => c.card.card === n).card.id;
    const ids = [idOf("A"), idOf("B")];
    const moveLine = place => { if (!place(ids[0])) return false; for (let i = 1; i < ids.length; i++) M.moveCardNext(L5.lines, ids[i], ids[i - 1], "after"); return true; };
    check(moveLine(id => M.moveCard(L5.lines, id, null, 3)) && names() === "X / Rest / A|B", "a line moved below the last: " + names());
    check(moveLine(id => M.moveCardNext(L5.lines, id, idOf("X"), "after")) && names() === "X|A|B / Rest", "into another line, beside a card: " + names());
    check(moveLine(id => M.moveCardNext(L5.lines, id, idOf("Rest"), "above")) && names() === "X / A|B / Rest", "as a line of its own again: " + names());
  }

  // the card panel's panels arranged (plan 13 3.3)
  {
    const show = a => a.map(i => i.panel || "[" + i.tabs.map(t => t.join("+")).join(" | ") + "]").join(" / ");
    let a = M.defaultArrangement();
    check(show(a) === "names / rules / inside / layout / style", "the first arrangement: each on its own, in order");
    a = M.arrangePanel(a, "style", { kind: "onto", of: "layout" });
    check(show(a) === "names / rules / inside / [layout | style]", "onto another: a set of tabs, a tab each: " + show(a));
    a = M.arrangePanel(a, "inside", { kind: "tab", of: "layout" });
    check(show(a) === "names / rules / [layout | inside | style]", "onto a tab: a new tab after it: " + show(a));
    a = M.arrangePanel(a, "names", { kind: "inTab", of: "style", side: "above" });
    check(show(a) === "rules / [layout | inside | names+style]", "into a tab, above a panel: " + show(a));
    a = M.arrangePanel(a, "rules", { kind: "inTab", of: "style", side: "below" });
    check(show(a) === "[layout | inside | names+style+rules]" && M.tabName(["names", "style", "rules"]) === "Names/Style/Rules",
      "into a tab, below a panel; the tab named for its panels: " + show(a));
    a = M.arrangePanel(a, "names", { kind: "above", of: "layout" });
    check(show(a) === "names / [layout | inside | style+rules]", "above a set of tabs: on its own: " + show(a));
    a = M.arrangePanel(a, "inside", { kind: "below", of: "names" });
    a = M.arrangePanel(a, "layout", { kind: "below", of: "inside" });
    check(show(a) === "names / inside / layout / style / rules", "a set left with one tab: its panels on their own: " + show(a));
    check(M.tabName(["layout", "style"], ["style"]) === "Style", "a tab's name: only the panels shown");
    check(show(M.normalArrangement([{ panel: "rules" }, { tabs: [["x"], ["style", "rules"]] }, 5])) === "rules / style / names / inside / layout",
      "an arrangement read back: unknown and twice dropped, a set of one tab undone, the missing added");
    check(M.panelSet({ wrap: true }, "layout") && !M.panelSet({ wrap: true }, "style") && M.panelSet({ hover: {} }, "style"),
      "a panel marked when something of its own is set");
  }

  // Dexmenu's own item found by a rule (plan 12): its types, the switch, an own card of an earlier layout made one
  {
    const r = { name: { contains: "x" }, caseSensitive: true, states: ["enabled"], also: true, priority: 4 };
    M.setRuleType(r, "editMenu");
    check(M.ruleType(r) === "editMenu" && r.own === "editMenu" && r.name === undefined && r.states === undefined && r.also === undefined &&
      r.priority === 4 && M.ruleProblem(r) === "", "to Edit Dexmenu: own written, the name and the shared fields gone, valid");
    M.setRuleType(r, "windowsMenu");
    check(r.own === "windowsMenu", "to Windows' menu");
    M.setRuleType(r, "usage");
    check(r.own === undefined && r.used === "most", "away from it: own taken out");
    check(M.ruleProblem({ own: "other" }) !== "" && M.ruleProblem({ own: "editMenu", name: { equals: "a" } }) !== "",
      "an unknown tag, or own with a name: outlined red");
    const up = M.upToDate({ format: M.formatVersion, lines: [
      { line: [ { card: "Edit menu...", own: "editMenu" }, { card: "Back to Windows", own: "windowsMenu" } ] },
      { line: [ { card: "M", menu: [ { line: [ { card: "Windows' menu", own: "windowsMenu" } ] } ] } ] } ] });
    const [e, w] = up.layout.lines[0].line, inner = up.layout.lines[1].line[0].menu[0].line[0];
    check(up.changed && e.own === undefined && e.rules[0].own === "editMenu" && e.title === undefined &&
      w.rules[0].own === "windowsMenu" && w.title === "Back to Windows" && inner.rules[0].own === "windowsMenu",
      "an own card of an earlier layout: a card with an own rule, its name its title when not the item's own; also in a menu");
  }

  // a rule's states: its own, else what General sets
  check(M.statesOf({}, "enabled").join() === "enabled" && M.statesOf({}, "both").join() === "enabled,disabled" &&
    M.statesOf({ states: ["enabled", "disabled"] }, "enabled").join() === "enabled,disabled",
    "a rule's states: as General sets unless its own (both kept when General says enabled)");
  // an earlier layout's most used row: three cards with used rules (plan 09 6.5)
  {
    const r = M.upToDate({ format: M.formatVersion, lines: [ { mostUsed: true }, { line: [ { card: "M", menu: [ { mostUsed: true } ] } ] } ] });
    check(r.changed && r.layout.lines[0].line.map(c => c.rules[0].rank).join() === "1,2,3" &&
      r.layout.lines[0].line.every(c => c.rules[0].used === "most") && r.layout.lines[1].line[0].menu[0].line.length === 3,
      "an earlier most used row: three cards with used rules 1, 2, 3, also in a card's menu");
  }

  // the colour pickers (plan 03 3.6): read, written in the shortest form, shown
  {
    const back = v => JSON.stringify(M.colorValue(M.colorState(v)).value);
    const st = M.colorState(undefined);
    check(st.mode === "theme" && !st.overrule && M.colorValue(st).value === undefined, "nothing given: the theme's, as it is");
    check(back({ intensity: 80 }) === '{"intensity":80}' && back({ opacity: 40 }) === '{"opacity":40}' &&
      M.colorState({ intensity: 80 }).mode === "theme" && M.colorValue({ mode: "theme", intensity: 100, opacity: 30, overrule: false }).value === undefined,
      "the theme's colour adjusted: an intensity, an opacity; an opacity not overruled not written");
    check(back("#D03030") === '"#d03030"' && back("#abc") === '"#aabbcc"' && back("accent") === '"accent"',
      "a colour and a palette name: written alone");
    check(back({ color: "accent", intensity: 100 }) === '"accent"' && back({ color: "accent", opacity: 100 }) === '{"color":"accent","opacity":100}',
      "intensity 100: left out; an opacity given (overruled) kept, also 100");
    check(back({ color: "surface", intensity: 80 }) === '{"color":"surface","intensity":80}' &&
      back("#11223380") === '{"color":"#112233","opacity":50}', "an intensity; #rrggbbaa read as an overruled opacity");
    check(M.colorState({ gradient: ["a", "b"] }).mode === "json" && M.colorState("none").mode === "json" &&
      back({ gradient: ["a", "b"] }) === '{"gradient":["a","b"]}', "a gradient and none: JSON, kept");
    check(!M.colorValue({ mode: "json", text: "{ bad" }).ok, "JSON that does not parse: not written");
    const fill = (v, g = true) => JSON.stringify(M.fillValue(M.fillState(v, g)).value);
    const two = { gradient: ["accent", { color: "#112233", intensity: 80, opacity: 50 }] };
    check(M.fillState(two, true).kind === "gradient" && M.fillState(two, true).angle === 90 &&
      fill(two) === JSON.stringify(two), "a gradient of two colours: From and To, each with its intensity and opacity; angle 90 left out");
    check(fill({ gradient: ["#fff", "accent"], angle: 0 }) === '{"gradient":["#ffffff","accent"],"angle":0}', "a gradient's angle kept");
    check(M.fillState(two, false).kind === "json", "where no gradient is drawn (text colour, border): a gradient as JSON");
    check(M.fillState({ gradient: ["a", "b", "c"] }, true).kind === "json" && M.fillState({ gradient: ["a", { intensity: 5 }] }, true).kind === "json",
      "a gradient of more colours, or with the theme's colour in it: as JSON");
    check(M.fillState("accent", true).kind === "colour" && fill("accent") === '"accent"' && fill(undefined) === undefined,
      "a colour field holding a colour, or nothing");
    const pal = { basecolor: "#000000ff", accent: "#ff0000ff", glass: "#ffffff80" };
    check(M.colorCss(M.colorState("accent"), pal) === "rgba(255, 0, 0, 1)" &&
      M.colorCss(M.colorState({ color: "accent", intensity: 50 }), pal) === "rgba(128, 0, 0, 1)" &&
      M.colorCss(M.colorState({ color: "accent", intensity: 200 }), pal) === "rgba(255, 255, 255, 1)" &&
      M.colorCss(M.colorState("glass"), pal) === "rgba(255, 255, 255, 0.5019607843137255)" &&
      M.colorCss(M.colorState({ color: "glass", opacity: 20 }), pal) === "rgba(255, 255, 255, 0.2)",
      "the swatch: a palette colour, an intensity towards the base and past it, the palette's alpha, an opacity");
  }

  // comments
  check(M.withoutComments('{ "r": "a//b" } // c') === '{ "r": "a//b" } \n', "// inside a string kept, after it a comment");

  // the editor's page script parses (not run: it needs the page); a syntax error there shows nowhere else
  // the pages' scripts parse (not run: they need their page); a syntax error there shows nowhere else
  Promise.all(["editor.js", "main.js", "theme.js"].map(file => fetch(file).then(r => r.text()).then(text => {
    try { new Function(text); check(true, file + " parses"); }
    catch (e) { check(false, file + " parses: " + e.message); }
  }).catch(e => check(false, file + " read: " + e.message)))).finally(() => {
    out.push(failures ? failures + " FAILED" : "OK");
    chrome.webview.postMessage({ type: "selftest", lines: out, failures });
  });
})();

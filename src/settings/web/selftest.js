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

  // the priority list
  L = sample();
  M.moveRule(L.default, 3, 0);
  check(M.ruleList(L.default).map(r => r.card.card).join() === "Git,LexPen,Clip,Zip", "Git's rule moved to the top of the priority list");
  check(M.ruleList(L.default).map(r => r.rule.priority).join() === "1,2,3,4", "priorities renumbered 1..n");
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

  // comments
  check(M.withoutComments('{ "r": "a//b" } // c') === '{ "r": "a//b" } \n', "// inside a string kept, after it a comment");

  out.push(failures ? failures + " FAILED" : "OK");
  chrome.webview.postMessage({ type: "selftest", lines: out, failures });
})();

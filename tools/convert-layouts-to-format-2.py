# One-time conversion of Dexmenu's layouts to format 2 (docs/plans/11-PLAN-cards-hold-content.md 3.7). Not part of the
# settings app or the DLL: run once, by hand.
#
#   python tools/convert-layouts-to-format-2.py [layouts folder] [--to <folder>]
#
# The layouts folder defaults to %APPDATA%\Dexmenu\layouts. Every *.json in it of format 1 (or the older form without
# "format") is converted; files already of format 2 are left alone. Without --to, the old files are first copied into
# a backup folder beside the layouts folder (layouts-format1-backup) and the converted ones written in place; with
# --to, the converted files are written there and the layouts folder is not touched (to look before converting).
#
# How: the menu's lines become the menu card's content. A line of one card: that card. A line of more: a card holding
# them side by side ("show": "row", no style, shown whenever anything in it shows: what a line was), the line's
# cardFit on it. A divider and the search box
# stay entries. A card with a menu: "show": "submenu" with its menu converted as its content. A card with buttons:
# "show": "row" (its found items inside it). Dexmenu's own card: a card with an own rule. The most used row: three
# cards with used rules in a row. Everything else as it is. Comments in the files (// ...) are not kept.

import json
import os
import shutil
import sys


def without_comments(text):
    # JSON with // comments: a comment ends the line, except inside a string (as the DLL and the editor read them)
    out = []
    in_string = False
    i = 0
    while i < len(text):
        c = text[i]
        if in_string:
            out.append(c)
            if c == "\\" and i + 1 < len(text):
                i += 1
                out.append(text[i])
            elif c == '"':
                in_string = False
        elif c == '"':
            in_string = True
            out.append(c)
        elif c == "/" and i + 1 < len(text) and text[i + 1] == "/":
            while i < len(text) and text[i] != "\n":
                i += 1
            out.append("\n")
            continue
        else:
            out.append(c)
        i += 1
    return "".join(out)


OWN_TEXT = {"editMenu": "Edit menu...", "windowsMenu": "Windows' menu"}


class Converter:
    def __init__(self, layout):
        self.used = set()
        self.collect_ids(layout)
        self.next = 1

    def collect_ids(self, value):
        if isinstance(value, dict):
            if isinstance(value.get("id"), str):
                self.used.add(value["id"])
            for v in value.values():
                self.collect_ids(v)
        elif isinstance(value, list):
            for v in value:
                self.collect_ids(v)

    def new_id(self):
        while "line%d" % self.next in self.used:
            self.next += 1
        made = "line%d" % self.next
        self.used.add(made)
        return made

    def card(self, card):
        if not isinstance(card, dict) or "note" in card:
            return card
        card = dict(card)
        if isinstance(card.get("own"), str):
            own = card.pop("own")
            card["rules"] = [{"own": own}]
            if card.get("card") and card["card"] != OWN_TEXT.get(own) and "title" not in card:
                card["title"] = card["card"]
        if "menu" in card:
            card["content"] = self.lines(card.pop("menu"))
            card["show"] = "submenu"
        if card.pop("buttons", False):
            card["show"] = "row"
        return card

    def lines(self, lines):
        content = []
        for entry in lines if isinstance(lines, list) else []:
            if not isinstance(entry, dict):
                continue
            if "divider" in entry or entry.get("search") is True:
                content.append(entry)
            elif entry.get("mostUsed") is True:
                content.append({"id": self.new_id(), "card": "Most used", "show": "row", "shownWhen": "always", "content": [
                    {"card": "Most used %d" % n, "rules": [{"used": "most", "rank": n, "states": ["enabled"],
                                                           "also": True, "consume": False}]} for n in (1, 2, 3)]})
            elif isinstance(entry.get("line"), list):
                cards = [self.card(c) for c in entry["line"]]
                if len(cards) == 1:
                    content.append(cards[0])
                elif cards:
                    row = {"id": self.new_id(), "card": "Line", "show": "row", "shownWhen": "always", "content": cards}
                    if "cardFit" in entry:
                        row["cardFit"] = entry["cardFit"]
                    content.append(row)
        return content


def convert(layout):
    version = layout.get("format", 0)
    if version >= 2:
        return None
    lines = layout.get("lines") if version >= 1 else layout.get("default")
    converter = Converter(layout)
    return {"format": 2, "menu": {"content": converter.lines(lines)}}


def main(argv):
    to = None
    if "--to" in argv:
        i = argv.index("--to")
        to = argv[i + 1]
        argv = argv[:i] + argv[i + 2:]
    folder = argv[0] if argv else os.path.join(os.environ["APPDATA"], "Dexmenu", "layouts")
    names = sorted(n for n in os.listdir(folder) if n.lower().endswith(".json"))
    converted = {}
    for name in names:
        with open(os.path.join(folder, name), encoding="utf-8-sig") as f:
            layout = json.loads(without_comments(f.read()))
        result = convert(layout)
        if result is None:
            print("format 2 already, left alone: " + name)
        else:
            converted[name] = result
    if not converted:
        print("nothing to convert")
        return 0
    if to is None:
        backup = os.path.join(os.path.dirname(os.path.abspath(folder)), "layouts-format1-backup")
        os.makedirs(backup, exist_ok=True)
        for name in converted:
            shutil.copy2(os.path.join(folder, name), os.path.join(backup, name))
        print("the old files kept in " + backup)
        to = folder
    os.makedirs(to, exist_ok=True)
    for name, result in converted.items():
        with open(os.path.join(to, name), "w", encoding="utf-8", newline="\r\n") as f:
            f.write(json.dumps(result, indent=2, ensure_ascii=True) + "\n")
        print("converted: " + name)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

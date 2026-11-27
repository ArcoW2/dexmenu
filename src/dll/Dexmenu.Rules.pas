unit Dexmenu.Rules;

// A rule (docs/plans/executed/02-PLAN-own-menu.md 3.3; plan 00 step 5): which items of Windows' menu a card takes.
//
//   { "name": { "contains": "LexPen" },            the item's text without &: equals, contains, startsWith,
//                                                   endsWith, wildcard (* ?), regex; or "any": [ ... ] (equals one)
//     "scope": "top" | "anywhere",                  where to look: Windows' top level, or every level
//     "path": { "startsWith": "7-Zip" },            or instead: (part of) the submenu path the item sits in
//     "states": [ "enabled", "disabled" ],         the states taken (default: both)
//     "caseSensitive": false, "also": false,       also: shown here even when an earlier rule took it
//     "consume": true,                              false: the item stays free for later rules and the remaining card
//     "skipDuplicates": false,                      true: of items of one name it finds, only the first shows
//     "latest": 1,                                  of the items it finds only the ones seen most recently show,
//                                                   this many (none: all); the others are taken all the same
//     "priority": 3 }                               its place in the priority list (lower first)
//
// Or by use instead of by name (docs/plans/executed/09-PLAN-used-rules.md 3.1): { "used": "most" | "recent", "rank": 3 | "1-3" }:
// the most used or most recently used items of this menu, at any depth; no rank: all of them, in order; a range from
// high to low ("3-1") the same items in reverse order. The match kind, caseSensitive, scope and path have no function
// there. A rank of 0 or lower, or one that is no number or range, makes the rule invalid.
//
// Or Dexmenu's own item (docs/plans/executed/12-PLAN-own-rules.md): { "own": "editMenu" | "windowsMenu" } finds that item, once,
// tagged so that, chosen, the DLL starts what the tag names; only its priority has a function there.
//
// A rule with both a scope and a path, an unknown match kind or a regex that does not compile is invalid: it finds
// nothing (the editor outlines its card red).

interface

uses
  System.JSON, System.RegularExpressions;

type
  TMatchKind = (mkEquals, mkContains, mkStartsWith, mkEndsWith, mkWildcard, mkRegex, mkAny);

  TMatch = record
    Present: Boolean;
    Kind: TMatchKind;
    Pattern: string;
    Any: TArray<string>;
    Regex: TRegEx;
    function Test(const Text: string; CaseSensitive: Boolean): Boolean;
  end;

  TScope = (scTop, scAnywhere, scPath);
  TStates = set of (stEnabled, stDisabled);
  TUsedKind = (ukNone, ukMost, ukRecent);   // a rule by name; by the most used; by the most recently used
  // one part of a used rule's ranks: a rank (From = To) or a range, From > To in reverse
  TRankRange = record
    From, To_: Integer;
  end;

  TRuleSpec = record
    Valid: Boolean;
    Problem: string;
    Name, Path: TMatch;
    Scope: TScope;
    States: TStates;
    CaseSensitive: Boolean;
    Also: Boolean;
    Consume: Boolean;    // default True
    SkipDuplicates: Boolean;
    // "latest": of the items found only this many show, the ones seen most recently (Dexmenu.Seen: the preview's
    // seen items; at a right-click all are there now: the first in the menu's order); 0: all
    Latest: Integer;
    Priority: Integer;   // -1: none given
    Used: TUsedKind;     // ukNone: a rule by name
    // the ranks a used rule finds, from 1, in the order written ("1,3,5", "1-2,5-6,8-10"; a range from high to low in
    // reverse); none: all of them
    Ranks: TArray<TRankRange>;
    Own: string;         // a rule finding Dexmenu's own item: its tag, "editMenu" or "windowsMenu"; '' none
  end;

function ParseRule(Obj: TJSONObject): TRuleSpec;

var
  // The states a rule takes when it does not say (the global settings' "states", plan 02 3.4; set by
  // Dexmenu.Layout.CurrentLayout before a layout is read)
  DefaultStates: TStates = [stEnabled, stDisabled];

implementation

uses
  System.SysUtils, System.StrUtils;

function ParseMatch(Value: TJSONValue; const What: string; out M: TMatch; var Problem: string): Boolean;
const
  Names: array[TMatchKind] of string = ('equals', 'contains', 'startsWith', 'endsWith', 'wildcard', 'regex', 'any');
var
  Obj: TJSONObject;
  K: TMatchKind;
  V, Item: TJSONValue;
begin
  M := Default(TMatch);
  Result := False;
  if not (Value is TJSONObject) or (TJSONObject(Value).Count <> 1) then
  begin
    Problem := What + ': one match kind, as { "contains": "..." }';
    Exit;
  end;
  Obj := TJSONObject(Value);
  for K := Low(TMatchKind) to High(TMatchKind) do
  begin
    V := Obj.GetValue(Names[K]);
    if V = nil then
      Continue;
    M.Present := True;
    M.Kind := K;
    if K = mkAny then
    begin
      if not (V is TJSONArray) then
      begin
        Problem := What + ': "any" takes a list';
        Exit;
      end;
      for Item in TJSONArray(V) do
        M.Any := M.Any + [Item.Value];
    end
    else if V is TJSONString then
      M.Pattern := V.Value
    else
    begin
      Problem := What + ': "' + Names[K] + '" takes a text';
      Exit;
    end;
    Exit(True);
  end;
  Problem := What + ': unknown match kind "' + Obj.Pairs[0].JsonString.Value + '"';
end;

function Wildcard(Pattern, Text: PChar): Boolean;
begin
  if Pattern^ = #0 then
    Exit(Text^ = #0);
  if Pattern^ = '*' then
    Exit(Wildcard(Pattern + 1, Text) or ((Text^ <> #0) and Wildcard(Pattern, Text + 1)));
  if Text^ = #0 then
    Exit(False);
  if (Pattern^ <> '?') and (Pattern^ <> Text^) then
    Exit(False);
  Result := Wildcard(Pattern + 1, Text + 1);
end;

function TMatch.Test(const Text: string; CaseSensitive: Boolean): Boolean;
var
  T, P, A: string;
begin
  if Kind = mkRegex then
    Exit(Regex.IsMatch(Text));
  if CaseSensitive then
  begin
    T := Text;
    P := Pattern;
  end
  else
  begin
    T := AnsiLowerCase(Text);
    P := AnsiLowerCase(Pattern);
  end;
  case Kind of
    mkEquals: Result := T = P;
    mkContains: Result := Pos(P, T) > 0;
    mkStartsWith: Result := StartsStr(P, T);
    mkEndsWith: Result := EndsStr(P, T);
    mkWildcard: Result := Wildcard(PChar(P), PChar(T));
    mkAny:
      begin
        for A in Any do
          if (CaseSensitive and (A = Text)) or (not CaseSensitive and (AnsiLowerCase(A) = T)) then
            Exit(True);
        Result := False;
      end;
  else
    Result := False;
  end;
end;

// "rank": a number from 1, or a text of ranks and ranges separated by commas, as pages to print: "3", "1-3", "3-1",
// "1,3,5", "1-2,5-6,8-10". Every rank from 1.
function ParseRank(V: TJSONValue; out Ranks: TArray<TRankRange>; var Problem: string): Boolean;
var
  M: System.RegularExpressions.TMatch;
  D: Double;
  Part: string;
  R: TRankRange;
begin
  Result := False;
  Ranks := nil;
  if V is TJSONNumber then
  begin
    D := TJSONNumber(V).AsDouble;
    if (Frac(D) = 0) and (D >= 1) and (D <= MaxInt) then
    begin
      R.From := Trunc(D);
      R.To_ := R.From;
      Ranks := [R];
      Exit(True);
    end;
  end
  else if (V is TJSONString) and (Trim(V.Value) <> '') then
  begin
    for Part in V.Value.Split([',']) do
    begin
      M := TRegEx.Match(Part, '^\s*(\d{1,9})\s*(?:-\s*(\d{1,9})\s*)?$');
      if not M.Success then
      begin
        Ranks := nil;
        Break;
      end;
      R.From := StrToInt(M.Groups[1].Value);
      R.To_ := R.From;
      if (M.Groups.Count > 2) and (M.Groups[2].Value <> '') then
        R.To_ := StrToInt(M.Groups[2].Value);
      if (R.From < 1) or (R.To_ < 1) then
      begin
        Ranks := nil;
        Break;
      end;
      Ranks := Ranks + [R];
    end;
    if Ranks <> nil then
      Exit(True);
  end;
  Problem := 'rank: numbers from 1 and ranges, as "1-3" or "1,3,5" or "1-2,5-6"';
end;

function ParseRule(Obj: TJSONObject): TRuleSpec;
var
  V, S: TJSONValue;
  Options: TRegExOptions;
begin
  Result := Default(TRuleSpec);
  Result.Priority := -1;
  Result.States := DefaultStates;
  Result.Scope := scTop;
  if Obj.GetValue('verb') <> nil then
  begin
    Result.Problem := 'a rule on the verb: not yet possible (the verb cannot be read from the menu yet)';
    Exit;
  end;
  V := Obj.GetValue('own');
  if V <> nil then
  begin
    if (Obj.GetValue('name') <> nil) or (Obj.GetValue('used') <> nil) then
    begin
      Result.Problem := 'a rule finds by "own", "name" or "used": one of them';
      Exit;
    end;
    if not (V is TJSONString) or ((V.Value <> 'editMenu') and (V.Value <> 'windowsMenu')) then
    begin
      Result.Problem := '"own" is "editMenu" or "windowsMenu"';
      Exit;
    end;
    Result.Own := V.Value;
    if Obj.GetValue('priority') is TJSONNumber then
      Result.Priority := TJSONNumber(Obj.GetValue('priority')).AsInt;
    Result.Valid := True;
    Exit;
  end;
  V := Obj.GetValue('used');
  if V <> nil then
  begin
    if Obj.GetValue('name') <> nil then
    begin
      Result.Problem := 'a rule has either "name" or "used", not both';
      Exit;
    end;
    if V.Value = 'most' then
      Result.Used := ukMost
    else if V.Value = 'recent' then
      Result.Used := ukRecent
    else
    begin
      Result.Problem := '"used" is "most" or "recent"';
      Exit;
    end;
    if (Obj.GetValue('rank') <> nil) and not ParseRank(Obj.GetValue('rank'), Result.Ranks, Result.Problem) then
      Exit;
  end
  else
  begin
    V := Obj.GetValue('name');
    if V = nil then
    begin
      Result.Problem := 'a rule needs "name" or "used"';
      Exit;
    end;
    if not ParseMatch(V, 'name', Result.Name, Result.Problem) then
      Exit;
  end;
  // a used rule: the match kind, caseSensitive, scope and path have no function (a used item is found at any depth)
  if Result.Used = ukNone then
  begin
    if (Obj.GetValue('scope') <> nil) and (Obj.GetValue('path') <> nil) then
    begin
      Result.Problem := 'a rule has either a scope or a path, not both';
      Exit;
    end;
    V := Obj.GetValue('scope');
    if V <> nil then
      if V.Value = 'top' then
        Result.Scope := scTop
      else if V.Value = 'anywhere' then
        Result.Scope := scAnywhere
      else
      begin
        Result.Problem := 'scope is "top" or "anywhere"';
        Exit;
      end;
    V := Obj.GetValue('path');
    if V <> nil then
    begin
      if not ParseMatch(V, 'path', Result.Path, Result.Problem) then
        Exit;
      Result.Scope := scPath;
    end;
  end;
  V := Obj.GetValue('states');
  if V <> nil then
  begin
    if not (V is TJSONArray) then
    begin
      Result.Problem := '"states" is a list of "enabled" and "disabled"';
      Exit;
    end;
    Result.States := [];
    for S in TJSONArray(V) do
      if S.Value = 'enabled' then
        Include(Result.States, stEnabled)
      else if S.Value = 'disabled' then
        Include(Result.States, stDisabled)
      else
      begin
        Result.Problem := '"states" is a list of "enabled" and "disabled"';
        Exit;
      end;
  end;
  if Obj.GetValue('caseSensitive') is TJSONBool then
    Result.CaseSensitive := TJSONBool(Obj.GetValue('caseSensitive')).AsBoolean;
  if Obj.GetValue('also') is TJSONBool then
    Result.Also := TJSONBool(Obj.GetValue('also')).AsBoolean;
  Result.Consume := True;
  if Obj.GetValue('skipDuplicates') is TJSONBool then
    Result.SkipDuplicates := TJSONBool(Obj.GetValue('skipDuplicates')).AsBoolean;
  if Obj.GetValue('consume') is TJSONBool then
    Result.Consume := TJSONBool(Obj.GetValue('consume')).AsBoolean;
  V := Obj.GetValue('latest');
  if V <> nil then
  begin
    if not (V is TJSONNumber) or (TJSONNumber(V).AsDouble <> Trunc(TJSONNumber(V).AsDouble)) or
      (TJSONNumber(V).AsDouble < 1) then
    begin
      Result.Problem := '"latest" is a whole number from 1';
      Exit;
    end;
    Result.Latest := TJSONNumber(V).AsInt;
  end;
  if Obj.GetValue('priority') is TJSONNumber then
    Result.Priority := TJSONNumber(Obj.GetValue('priority')).AsInt;
  // regexes compiled once
  Options := [];
  if not Result.CaseSensitive then
    Options := [roIgnoreCase];
  try
    // TRegEx compiles on first use: a match forces it here, so a bad pattern is found now
    if Result.Name.Kind = mkRegex then
    begin
      Result.Name.Regex := TRegEx.Create(Result.Name.Pattern, Options);
      Result.Name.Regex.IsMatch('');
    end;
    if Result.Path.Present and (Result.Path.Kind = mkRegex) then
    begin
      Result.Path.Regex := TRegEx.Create(Result.Path.Pattern, Options);
      Result.Path.Regex.IsMatch('');
    end;
  except
    on E: Exception do
    begin
      Result.Problem := 'the regex does not compile: ' + E.Message;
      Exit;
    end;
  end;
  Result.Valid := True;
end;

end.

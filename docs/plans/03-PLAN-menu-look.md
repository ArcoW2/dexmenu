# Plan 03: The menu's look: what the Delphi DLL draws, and themes made for it

Status: partly executed; see Status.

- 2026-11-21: draft.
- 2026-11-22: partly executed: theme files; the shipped themes; gradients.
- 2026-11-23: partly executed: lines and cards; the card.

Plan 02 (`02-PLAN-own-menu.md`) decides what goes where: lines of cards found by rules, submenus, the preview. This
plan decides how it looks and what the drawing engine in the Delphi DLL (plan 01 3.2) must be able to draw. The
engine draws the real menu and the settings app's preview alike (plan 02 3.8).

## 1. What this is about

Before the Delphi DLL is built it has to be known exactly what it draws. The menu is lines of cards: a card alone on
a line looks and feels like a menu item; several cards share a line. A card can have its own height, a minimum
width, a background colour or image of its own, and is an action or opens a submenu. The menu needs themes as LexPen
and Foldex have, but much simpler, with a background colour, shade or image for the menu as a wish. LexPen's and
Foldex's themes are CSS colour variables that a web view draws with; the DLL paints every pixel itself, so its themes
need a structure of their own.

## 2. The solution, in brief

A drawing engine in the Delphi DLL with Direct2D and DirectWrite draws a fixed set of elements: the menu window,
lines, cards, dividers, the icon row, the search box, submenu panels and a scrollbar, each in a fixed set
of states (normal, hover, pressed, focused, disabled, unavailable). A theme is a JSON file as in LexPen (a name, a base
theme, only what differs), but what it holds is per element and per state: colours, a background (colour, gradient
or image), border, corner radius, padding, gap and font. The colours come from the theme's palette: named colours and
a base colour, an element naming a palette colour and how strongly it shows against the base colour. The layout
positions cards on lines by the level's width,
the cards' minimum widths and weights, and their heights; a single card on a line is drawn as a menu item. A card can
overrule its background and colours in the layout. Settings pick a theme for light and one for dark.

## Status

### Built

| Part | What | Reference |
|---|---|---|
| Engine | Direct2D and DirectWrite in the DLL (`Dexmenu.Draw`): solid and gradient brushes, rounded boxes, text and text layouts, bitmaps (icons), stripes; drawing into a layered window (the menu) or an image in memory (the preview, the screenshots); image files come with Menu window | 3.1 |
| Gradients | a background as a colour or a linear gradient (`"gradient": [ colours ]`, `"angle"`), for the menu, a card and a hovered card | 3.4; 6.3 |
| Shipped themes | `light-parchment`, `dark-parchment`, `light-sky`, `dark-ocean`, `light-seafoam`, `dark-forest`, built into the DLL on the built-in light and dark, LexPen's colours as their palette; cards get their own background (`bgSide`) | 3.3; 6.2 |
| Card | a card alone on its line drawn as the theme's `item`, others as its `card`; the extra text above or below the title; icon on top for a tall or square card; its own background, foreground, border, radius and hover / pressed look from the layout; the pressed state; the card panel's fields | 3.6; 3.7; 6.5 |
| Lines and cards | a card's `weight`, `minWidth`, `height` (in lines) and `cardFit`, a line's `cardFit`; the level grown for minimum widths up to its maximum, then the last cards wrapped; the theme's gaps between cards and lines; the card panel's size fields | 3.5; 6.4 |
| Theme files | `Dexmenu.Theme`: JSON with comments, `base` (chains merged), the palette with `basecolor`, colours as a literal, a palette name or `{ color, intensity, opacity }`; built-in `light` and `dark`; the user's themes folder, then the DLL's, then the built-in; read again when a file changes; chosen per light and dark in the main window (`themeLight`, `themeDark`); the menu and the preview draw their colours and radii from it | 3.2; 3.3; 6.1 |

### Not yet built

| Part | What | Waits for | Reference |
|---|---|---|---|
| Animation | none, slide (direction), fade, crossfade, with a time; for submenus and `replace` | Submenu panels | 3.9 |
| Menu window | popup, corners, shadow, border, background image, placement, scrolling | Engine | 3.4 |
| Dividers | a line between lines, with an optional label (left, middle, right), own height, background and colours | Engine | 3.8 |
| Other elements | icon row, search box, most used row, `<<` | -- | 3.8 |
| Own cards' icons | an icon of their own for Dexmenu's own cards ("Edit menu...", "Windows' menu", command cards) where the layout gives none | Theme files | 3.8 |
| Submenu panels | next, under, replace: where they appear and how they look | -- | 3.9 |
| Blur | the screen behind the menu copied and blurred as a background, for the menu or per card; a later step, after the menu works | Menu window | 3.4 |
| Preview marks | striped unavailable items, new | -- | 3.10 |
| Tests | 3.11 | -- | 3.11 |

## 3. Details

### 3.1 The engine: what it can draw

Checked in the Delphi 10.4 on this machine: `Winapi.D2D1` (Direct2D 1.0 with DirectWrite), `Winapi.Wincodec` (WIC),
`Winapi.DwmApi`, `Winapi.UxTheme`. From them:

- **Shapes:** rectangles with rounded corners, filled and outlined, lines.
- **Brushes:** a solid colour with alpha; a linear or radial gradient between colours (the "shade"); a bitmap, drawn
  stretched, fitted, centred, or tiled across, down or both (3.4).
- **Images:** PNG, JPG, BMP and ICO from a file through WIC; the icons of plan 02 3.8.
- **Text:** DirectWrite: any installed font, size, weight, one line with an ellipsis or wrapped to a number of
  lines, the `&` letter underlined, ClearType.
- **Stripes:** diagonal stripes for unavailable items (plan 02 3.8), drawn as lines clipped to the card.
- **See-through:** the menu is a layered window with a transparency per pixel: Direct2D draws into a 32-bit image
  in memory (`ID2D1DCRenderTarget`, premultiplied alpha), which `UpdateLayeredWindow` shows. So a theme can have no
  menu background at all: cards "in space", what is behind the menu visible between them and around their rounded
  corners. Checked with a probe built with the Delphi here: three rounded cards (one with a gradient) over a coloured
  window, that colour seen in the gaps and at the corners, edges smooth. The gaps are fully see-through; a click
  there goes to the window behind, as a click outside the menu, and closes the menu.
- **Targets:** a window's own surface (the menu) and an image in memory (the preview's pictures for tests, plan 02
  3.12). The same drawing code for both.
- **Window:** a layered popup window (see-through, above); its corners, border and shadow drawn by Dexmenu (3.4),
  not by DWM.
- **Not in Delphi 10.4:** Direct2D 1.1 (`D2D1_1`) and its effects (blur, drop shadow of an element). Blur is
  Dexmenu's own (3.4).
- **Per-monitor DPI:** everything in device-independent units, scaled to the monitor the menu is on.

### 3.2 Themes: the structure

A theme is drawn by Dexmenu itself, so it names every element and state the engine draws, with typed values.

- **The file, as in LexPen and Foldex:** JSON with comments (plan 02 3.5), `name`, `description`, `base` (another
  theme), and only what differs from the base. `light` and `dark` are the roots and set everything. Shipped themes in
  the DLL's folder, the user's own in `%APPDATA%\Dexmenu\themes`; a file of the user's with the same name wins.
- **What it holds:** per element, per state, a set of properties:
  - Elements: `menu` (the window), `line`, `card`, `item` (a card alone on a line), `divider`, `row` (an icon row
    and its icons), `search`, `panel` (a submenu panel), `back` (the `<<` line), `scrollbar`, `badge` (new).
  - States: `normal`, `hover`, `pressed`, `focused` (the keyboard's), `disabled`, `checked`, `default` (Windows'
    default item, bold there), `unavailable` (the preview's stripes). A state lists only what differs from `normal`.
  - Properties (what the user sets per theme: the line around a card, the roundness of its corners, its background,
    the menu's background, the space between cards and dividers): `background` (3.4; `none` for the menu: cards in
    space), `foreground` (the title, a divider's label), `extra` (the extra text's colour
    and font), `mark` (the action and submenu marks' colour), `border` (colour and width), `radius`, `padding`,
    `gap` (between cards on a line and
    between lines), `font` (family, size, weight), `iconSize`, `opacity`.
- **A palette makes the colours:** named colours at the top of the theme (`accent`, `text`, `surface`, ...) and a
  `basecolor`, the theme's generic base colour. The elements use the palette's colours by name, so a theme on a
  base can change a few palette colours (or only the base colour) and recolour every element using them. This takes
  the place of LexPen's CSS variables.
- **A colour in an element:** an object naming a palette colour and its intensity against the base colour:
  `{ "color": "surface", "intensity": 80 }` is surface moved a little towards the base colour. The intensity runs
  from 0 to 200: 0 the base colour, 100 the palette colour itself, the values between a mix of the two (80: four
  parts surface, one part base); above 100 the palette colour mixed with the base colour inverted (each channel 255
  minus the base's), so it moves away from the base: 200 is that inverse. On black, red at 150 is rose and 200 is
  white; on white, 200 is black. The mix is per channel in sRGB: each of red, green and blue as stored,
  `a + (b - a) x t`.
  `intensity` left out: 100. Short for 100: the palette name alone, `"surface"`.
- **Translucency is separate:** the intensity mixes the colour only, never its alpha. How see-through a colour is,
  is its `opacity`, 0 (invisible) to 100 (solid): `{ "color": "accent", "intensity": 30, "opacity": 40 }`. Given,
  it overrules the palette colour's own alpha; left out, the palette colour's alpha stays. Wherever a colour goes: a
  background, a gradient's stops, a tint, the foreground, the border, the mark.
- **Spelling, as LexPen and Foldex:** `color` in the JSON names (`color`, `basecolor`), "colour" in the text.
- **Colours in the palette:** `#rgb`, `#rrggbb`, `#rrggbbaa`, `rgba(r, g, b, a)` as in LexPen's themes; in an
  element a literal colour is allowed too, for the rare one the palette does not hold.
- **Following Windows:** `accent` can be `system` (Windows' accent colour); light or dark per Windows' mode, as the
  global settings say (plan 02 3.4: `themeLight`, `themeDark`).
- An example, in the shape it may take:

  ```json
  // Dark ocean: on Dark, bluer.
  { "name": "Dark ocean", "base": "dark",
    "palette": { "basecolor": "#161c27", "surface": "#1d2533", "text": "#d8e0ee", "accent": "#6aa8ff" },
    "menu": { "normal": { "background": { "gradient": [ "basecolor", { "color": "surface", "intensity": 60 } ],
                                          "angle": 90 } } },
    "card": { "normal": { "radius": 6, "background": { "color": "surface", "intensity": 80 },
                          "foreground": "text" },
              "hover": { "background": { "color": "accent", "intensity": 30 } } }
  }
  ```

  (The values in the example show the shape only; the shipped values are [not yet decided].)

### 3.3 Shipped themes

- `light` and `dark`, complete, close to Windows 11's own menus so Dexmenu does not look foreign at first.
- Themes on them made from LexPen's colours (`..\LexPen\src\defaults\themes`), in pairs of a light and a dark one:
  - Parchment: `light-parchment` and `dark-parchment`;
  - Sky and ocean: `light-sky` and `dark-ocean`;
  - Seafoam and forest: `light-seafoam` and `dark-forest`.
- Each changes the palette only, LexPen's app colours mapped onto it: `bg` the base colour and the menu's
  background, `bgSide` a card's, `bgBar` a divider's and a panel's, `fg` the text, `fgDim` the extra text, `border`, `accent`, `hover`, `active`
  for pressed, `select` for focused.
- Which theme is used: the global settings (plan 02 3.4) follow Windows' light or dark mode, or are fixed to light
  or to dark; one theme is chosen for light (`themeLight`) and one for dark (`themeDark`), so a pair as above follows
  Windows as one look.

### 3.4 The menu window and backgrounds

- **A background** (for the menu, a panel, a card): one of
  - `color`: one colour (a palette colour with its intensity, 3.2), with alpha;
  - `gradient`: two or more colours, an angle (linear) or a centre (radial): the shade;
  - `image`: a file, with `fit`, `opacity`, and an optional `tint` colour over it so text stays readable. `fit`:
    `stretch` (to the whole area), `fit` (whole image inside, its proportions kept), `center` (its own size, in the
    middle), `repeatX` (tiled across), `repeatY` (tiled down), `repeat` (tiled both ways). The same for the menu, a
    panel, a card and a divider;
  - layered: a colour under an image under a tint;
  - `blur` (a later step, Status): what is behind the menu, blurred, for the menu or per card (3.4 below).
- **Blur, a later step:** just before the menu shows, Dexmenu copies the screen area behind it, blurs the copy with
  its own code (Direct2D 1.0 has no blur), and uses it as a background image: for the whole menu, or per card, so
  blurred cards can float in space with clear gaps. Documented calls only, and it fits the layered window. It is a
  still picture: what moves behind the menu does not move in the blur. Its speed: [not yet checked]. Windows' own
  blur (DWM's Acrylic) is not used: it covers a normal window's whole rectangle and does not fit cards in space; the
  undocumented composition blur neither, and it can break with a Windows update.
- **No background:** `menu.background` can be `none`: only the cards, dividers and rows are drawn, with the
  theme's `gap` between them, the rest see-through (3.1). Cards are then always opaque: a card's background is drawn
  without its alpha, and a card without a background gets the theme's card background. The settings app says so when
  a theme or card asks for a see-through card on a menu without a background.
- **With a background:** the menu is the same layered window, its background drawn first. A card can then be
  transparent (`background: none`, or a colour with alpha), showing the menu's background through it.
- **The frame:** the menu's corners from the theme's `radius`, its border from the theme; drawn by Dexmenu, as the
  layered window gets no corners or shadow from DWM. A shadow, per card or for the menu, drawn by Dexmenu too:
  Direct2D 1.0 has no blur, so a soft shadow is built from layered translucent shapes or a prepared image; how
  convincing that looks: [not yet checked].
- **Placement:** as Windows' menu: at the mouse or at the point the program gives, flipped to the other side at a
  screen edge, on the monitor of that point.
- **Too tall for the screen:** the menu is as tall as the work area and scrolls: the mouse wheel, the keys, a thin
  scrollbar on hover.

### 3.5 Lines and cards

- **The width:** each level of the menu has a width (plan 02 3.4). The cards on a line share it, after the theme's
  `gap` between them, by their `weight` (equal by default).
- **Minimum width:** a card can have a `minWidth`. When the cards of a line do not fit side by side at their minimum
  widths, the level first grows: as wide as that line needs, up to the level's maximum width (plan 02 3.4) and never
  wider than the screen's work area. The whole level takes that width, every line in it. When the line still does not
  fit at the maximum, its last cards wrap onto a new line below it, in their order, and that new line shares the
  width as any other.
- **Heights:** a card's `height` is `auto` (from its content: the titles, the icon) or a fixed height in lines of
  text (`2`, `3`) or in units. The line is as tall as its tallest card. The others, by the line's `cardFit`, which a
  card can overrule: `stretch` (as tall as the line) or aligned at their own height, `top`, `center` or `bottom`.
- **A single card on a line** is drawn as a menu item: full width, no card border, the hover as a menu's, the icon
  left and the mark right. Several cards on a line are drawn as cards: their own background and border, the icon
  above or left of the titles depending on the card's shape (3.6).
- **Gaps:** between cards and between lines from the theme (`gap`), per element.

### 3.6 A card

- **Content:** an optional icon, the title, an optional extra text (smaller, from the theme's `extra`) above or below
  the title as the card says (`extraAt`: `above`, `below`), and a mark: the action mark or the submenu mark of the
  global settings (plan 02 3.4), in the theme's `mark` colour.
- **Arrangement:** a wide card (menu item, or wider than tall): icon left, the title and extra text beside it, mark
  at the right end. A tall or square card: icon at the top, the title and extra text under it, centred, mark in the
  corner.
- **Overflow:** a title that does not fit ends in an ellipsis; the full text as a tooltip.
- **Its own look:** a card in the layout (plan 02 3.5) can overrule the theme for itself: `background` (colour,
  gradient, image; `none` or alpha only on a menu with a background, 3.4), `foreground`, `border`, `radius`,
  `height`, `minWidth`, `weight`, `cardFit` (3.5). Per state where wanted
  (`hover` of its own).
- **Template cards:** items Dexmenu places in a submenu itself are drawn with a template card's look (plan 02 3.3):
  the layout's, or a card's own submenu template. A template has the same look settings as a card, no rules.
- **An action or a submenu:** the same card; the mark and the click differ (an item, or a card with a menu or an
  item with a Windows submenu).

### 3.7 States

- `hover` (the mouse over it), `pressed` (the button down), `focused` (the keyboard's: a ring, as Windows' focus
  rectangle), `disabled` (dimmed, no hover, no click), `checked` (Windows' checked items: a check mark where the
  icon would be, or before the title), `default` (Windows' default item: bold), `unavailable` (the preview only:
  diagonal stripes over the card, plan 02 3.8).
- A card can be in two at once (focused and hover); the theme's values combine in a fixed order: `normal`, then
  `checked` / `default`, then `hover`, `pressed`, `focused`, then `disabled` / `unavailable`.

### 3.8 The other elements

- **Icon row:** square cells of an icon each, the title as a tooltip; the same states as a card.
- **Most used row:** as an icon row, or as small cards with titles. No use counts on it, in the menu or the preview
  (plan 02 3.9: they are shown in the editor's cards view).
- **Divider:** between two lines of cards. Without a label: a thin line. With a label: the text aligned `left`,
  `middle` or `right`, the line on the free side(s). Its own `height` (the space it takes) and `background` (colour,
  gradient or image, 3.4) where the layout gives them; the label's colour and font from the theme's `divider`, or
  the divider's own, as a card's text can have its own.
- **Search box:** a text field at the top (or where the layout puts it), shown when typing starts if the layout has
  none (plan 02 3.6); matches marked in the titles.
- **`<<`:** the first line of a `replace` submenu, with the path of the levels above it.
- **Dexmenu's own cards** ("Edit menu...", "Windows' menu", plan 02 3.6, 3.11; later the command cards of plan 06):
  cards the layout places, with an icon of their own from the theme (a glyph each) where the layout gives none;
  until then they show no icon, as any card without one (plan 02 3.8).

### 3.9 Submenu panels

- **`next`:** a panel next to the card, its top level with the card's top, on the other side when there is no room;
  its own width (the level's), its own background from the theme's `panel`.
- **`under`:** a panel below the card, starting at the card's bottom edge, over the lines below it; the card it belongs to
  stays marked.
- **`replace`:** the menu's own window shows the submenu: `<<` at the top, the level's width; the window resizes from
  its top-left corner.
- **Opening on hover:** after Windows' own menu delay (the system setting), as Windows' menus; closing when the mouse
  goes to another card. On click only: as the global setting says.
- **Animation:** a global setting (plan 02 3.4), for a submenu opening and for a `replace` change: `none` (at once),
  `slide` (with a direction: from the left, right, top or bottom), `fade` (the new level fading in), `crossfade` (the
  old level fading out while the new one fades in); and the time it takes. Drawn by Dexmenu, frame by frame, into the
  layered window. Default: [not yet decided].

### 3.10 Marks of the preview

- **Unavailable:** diagonal stripes over an item that is not always there, or a card that would be empty (plan 02
  3.8), in the theme's `unavailable` colours.
- **New:** a badge on items seen for the first time.
- **Useless:** a red outline around a card that can never show anything (no rules, or an invalid rule; plan 02 3.5),
  in the editor and the preview only; the theme's `invalid` colour. Distinct from the stripes: a striped card is
  sometimes there, an outlined one never.

### 3.11 Tests

- The engine draws into an image in memory: for a fixed tree, layout and theme, the picture compared with an approved
  one (per light, dark, a few DPI scales); a change in drawing shows as a difference to look at.
- Lines and cards: widths from weights and minimum widths; a line that does not fit (the level grown up to its
  maximum, the screen's edge as a limit, then the last cards wrapped), heights, a line's cards stretched or aligned
  top, centre and bottom, a card overruling its line, a single card drawn as a menu item.
- Images: every `fit` (stretch, fit, center, repeatX, repeatY, repeat) on the menu, a card and a divider.
- Animation: each kind and direction, a time, `none` at once; a choice made during an animation still hands back the
  right id.
- Shipped themes: each pair, following Windows' mode and fixed to light and to dark.
- Every state of a card and their combinations; a card's own background (colour, gradient, image) and colours; the
  extra text above and below the title.
- Dividers: without a label, with a label left, middle and right; own height, background and label colour.
- A menu without a background: the gaps and corners see-through, a card asking for alpha drawn opaque and reported;
  with a background, a transparent card showing it.
- Colours: a palette colour at intensity 100, 0 (the base colour), between (the mix) and above 100 up to 200 (mixed
  with the inverted base colour: white at 200 on black, black on white); outside 0 - 200 reported; left out (100); a palette
  name alone; an unknown palette name reported, the base's value used.
- Themes: a theme on a base with only palette changes recolours every element using them; one changing only the
  base colour moves every colour below intensity 100; an unknown property or a
  bad colour reported, the base's value used.
- By hand: Explorer and the settings app's preview side by side, the same layout and theme, the same picture.

## 4. Open questions

None.

## 6. As built

### 6.1 Theme files

- The engine's colours today come from the theme: the menu's background, border and radius; a card's foreground, its
  disabled foreground, its extra colour (notes, shortcuts), its hover and unavailable backgrounds, its radius and its
  focused border (the editor's mark); a divider's line (`border`) and label (`foreground`). The built-in `light` and
  `dark` hold exactly the colours drawn before, so nothing changes until a theme is chosen.
- A state that does not give a property takes `normal`'s; a property the theme does not give takes the engine's own
  value. An unknown palette name or colour, or an intensity outside 0 - 200, is noted in the theme's problems and the
  default used; a theme that cannot be read is logged and the built-in one used.
- Backgrounds are colours only for now; gradients and images come with Menu window (3.4).
- Tested: unit tests for every colour form, the intensity on black and on white, a theme on a base (a palette change
  recolouring what uses it, the base's values kept, intensity and opacity, a state falling back to normal, an
  unknown name), and the theme the settings name read from the user's folder or falling back to the built-in. By
  hand: a "Dark ocean" theme in the editor's preview, and the main window's choice.

### 6.2 Shipped themes

- Built into the DLL, as `light` and `dark` are, so they work wherever it is installed; a file of the user's with the
  same name wins. Their palette: `basecolor` and `surface` LexPen's `bg`, `side` its `bgSide` (a card's
  background), `bar` its `bgBar`, `text` its `fg`, `dim` its `fgDim`, `border` and `line` its `border`, `accent`,
  `active` (a pressed card's background) and, for the light ones, `hover`.
- A card's own background is drawn only where a theme gives one; the built-in light and dark give none.
- Tested: each read without problems and with its cards' background; `dark-forest` seen in the editor's preview.

### 6.3 Gradients

- A background is a colour (any colour form, 3.2) or `{ "gradient": [ colours ], "angle": degrees }`: the colours
  spread evenly along a line through the box's middle at the angle (0 left to right, 90 top to bottom, the default),
  long enough to reach the corners. Drawn for the menu, a card and a hovered card; images (3.4) are still to come.
- Tested: a gradient's colours resolved through the palette and its angle; a colour background; none given. By
  hand: a menu from blue to purple in the editor's preview.

### 6.4 Lines and cards

- A card in the layout: `"weight"` (its share of the line's width, 1 when not set), `"minWidth"` (DIP), `"height"`
  (in lines of text; not set: its content's height, one line or a note's wrapped text) and `"cardFit"` (`stretch`,
  `top`, `center`, `bottom`); a line: `"cardFit"` for its cards, stretched when not set. A height in units is not
  made: lines of text only.
- The width: the widest line's need, each card at least its minimum width, between the level's minimum and maximum
  (plan 02 3.4). A line whose minimum widths do not fit within the maximum has its last cards wrapped onto a line of
  their own. The screen's work area is not a limit of its own here: the level's maximum is.
- Shared by weight; a card whose share is below its minimum gets its minimum and the others share the rest.
- Gaps: the theme's `card.normal.gap` between cards on a line and `line.normal.gap` between lines, none when not
  given (the built-in themes give none, so nothing moved).
- A single card on a line was already drawn as a menu item; several cards on a line drawn as cards of their own
  come with the Card part.
- In the editor: Weight, Min width, Height and "Fit in line" in the card panel (cards with rules or a menu, notes,
  Dexmenu's own items; not the remaining card, whose items each take a line). A line's own `cardFit` has no field;
  it is kept when written in the file.
- Tested: unit tests on the measured boxes (weights 1 : 3, a minimum width with the other card taking the rest, a
  line wrapped with the level grown, a height of two lines with a card centred and one stretched, a line's fit and a
  card overruling it); the editor's self-test.

### 6.5 The card

- Element: a card alone on its line is drawn with the theme's `item`, cards sharing a line with its `card`; `item`
  takes every value it does not give from `card`, so the built-in and shipped themes look as before until a theme
  sets `item` apart.
- A card's own look in the layout: `background` (a colour, a gradient as in the theme, or `none`), `foreground`,
  `border`, `borderWidth`, `radius`, and the same per state in `hover` and `pressed`; its colours use the theme's
  palette. The order: the card's own value for the state, the theme's for the state, the card's normal, the
  theme's normal; so a theme's hover still shows over a card's own background. On a card with rules or a menu, a
  note's size only, Dexmenu's own items; the remaining card's items keep the theme's look.
- States drawn: normal; hover and pressed over the normal background (only what the state itself gives; a pressed
  card without a pressed background as hovered); disabled (the theme's disabled foreground); a border where the
  theme or the card gives one. The mouse button down on a card: pressed until let go or moved off. Focused is not
  drawn apart from hover (the keys move the same selection the mouse does); checked and default as before (the
  check mark, bold).
- `extra` (a text) with `extraAt` (`below`, the default, or `above`): smaller, in the theme's `extra` colour; the
  title and it centred in the card together; such a card is one extra-text line higher.
- A tall or square card (as high as wide or higher): its icon at the top, the title and extra text under it, centred,
  a submenu's chevron in the top right corner; no access key underline or shortcut there.
- A title that does not fit ends in an ellipsis, as before; its full text as a tooltip is not made (the tooltip
  shows the item's hint).
- In the editor: "Extra text at", Background, Text colour, Border, Radius and Hover background in the card panel; a
  colour as `#rrggbb` or a palette name, an object (a gradient, an intensity) as JSON.
- Tested: unit tests (an item's value from the card's, a card's own look over the theme's in each state, a state's
  own background only, `none`, the extra text's line height); the editor's self-test; by hand in the editor's
  preview: tall cards with their icons on top, extra text below and above, a card with its own background, border
  and radius, a pressed card in `dark-forest`.

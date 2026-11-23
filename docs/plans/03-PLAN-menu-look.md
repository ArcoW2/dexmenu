# Plan 03: The menu's look: what the Delphi DLL draws, and themes made for it

Status: partly executed; see Status.

- 2026-11-21: draft.
- 2026-11-22: partly executed: theme files; the shipped themes; gradients.
- 2026-11-23: partly executed: lines and cards; the card.
- 2026-11-23: partly executed: the colour fields.
- 2026-11-23: partly executed: a title that wraps.
- 2026-11-23: partly executed: none; a note's style and font; the 3D border; the shadow.
- 2026-11-23: partly executed: a note's date and time.
- 2026-11-23: partly executed: the see-through menu; the menu's shadow.
- 2026-11-23: partly executed: a divider's own look.
- 2026-11-23: partly executed: the focus ring.

Plan 02 (`executed/02-PLAN-own-menu.md`) decides what goes where: lines of cards found by rules, submenus, the preview. This
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
| None | "none" for Background, Hover background and Border: nothing drawn (a framed card's border "none": no frame line, where not set gives the dividers' colour) | 3.6; 6.9 |
| Note style | a note's own style (background, text colour, border, radius, 3D border, shadow) and its font: the items' text, the smaller extra text, or its own (family, size, bold, italic) | 3.6; 6.10 |
| Note date and time | `{date}` and `{time}` in a note's text (Windows' short formats), or `{date:<picture>}` and `{time:<picture>}`; `{{` and `}}` a brace; filled when the menu opens | 3.6; 6.11 |
| 3D border | a card's border raised (outset) or sunk (inset) as Windows' classic buttons, lit from an angle, its width and light and dark edge colours; in the card panel's Style | 3.6; 6.10 |
| Shadow | a card's shadow in a colour at a distance away from the light, its edge blurred, under the card and inside the menu only; in the card panel's Style | 3.6; 6.10 |
| Menu window | at the mouse or the program's point, flipped at the work area's edges, on that point's monitor; as tall as the work area at most, then scrolling with the wheel; corners and border from the theme and the menu card | 3.4 |
| See-through menu | the menu card's background `none`: no background or border of the menu's own, only its cards, dividers and rows; each card, framed holder and note on an opaque base; the editor says so | 3.4; 6.12 |
| Menu shadow | the menu card's shadow around each level's window, in a window of its own behind it that takes no mouse; in the preview under each level | 3.4; 6.12 |
| Submenu panels | `next`, `under` and `replace` (with `<<` and the path); opening on hover after Windows' menu delay, or on click only as the settings say; per card or for the layout | 3.9 |
| Other elements | a divider with its label left, middle or right; the search box (plan 02 3.6); `<<`; the most used as cards with used rules (plan 09); an icon on top of a tall or square card (icon rows as rows of square cards, plan 11) | 3.8 |
| Divider look | a divider's own `height`, `background`, line colour (`border`, `none`: no line), label colour (`foreground`) and `font` (as a note's); the divider panel's fields | 3.8; 6.13 |
| Focus ring | the card the keys moved to drawn with a ring in the theme's focused colour, until the mouse moves | 3.7; 6.14 |
| States | hover, pressed, disabled, checked (a check mark), default (bold); unavailable stripes in the preview | 3.7; 3.10 |
| Colour fields | the card panel's colours (background, text colour, border, hover background) each a picker: a colour (the theme's own, as it is or adjusted; a colour; a palette colour), a gradient of two colours (the backgrounds), or JSON; an intensity, an opacity with an Overrule checkbox, both typed or slid; a swatch; written in the shortest form | 3.6; 6.6 |
| Lines and cards | a card's `weight`, `minWidth`, `height` (in lines), `wrap` (its title over more lines) and `cardFit`, a line's `cardFit`; the level grown for minimum widths up to its maximum, then the last cards wrapped; the theme's gaps between cards and lines; the card panel's size fields | 3.5; 6.4 |
| Theme files | `Dexmenu.Theme`: JSON with comments, `base` (chains merged), the palette with `basecolor`, colours as a literal, a palette name or `{ color, intensity, opacity }`; built-in `light` and `dark`; the user's themes folder, then the DLL's, then the built-in; read again when a file changes; chosen per light and dark in the main window (`themeLight`, `themeDark`); the menu and the preview draw their colours and radii from it | 3.2; 3.3; 6.1 |

### Not yet built

| Part | What | Waits for | Reference |
|---|---|---|---|
| Animation | none, slide (direction), fade, crossfade, with a time; for submenus and `replace` | -- | 3.9 |
| Scrollbar | a thin scrollbar on hover for a menu taller than the work area (it scrolls with the wheel already) | -- | 3.4 |
| Own cards' icons | an icon of their own for Dexmenu's own cards ("Edit menu...", "Windows' menu", command cards) where the layout gives none | -- | 3.8 |
| Preview marks | a badge on items seen for the first time; the red outline of a card that never shows, in the preview too (the editor's cards view has it) | -- | 3.10 |
| Image fill | an image as a third kind of the background fields' picker, beside a colour and a gradient; every `fit` | -- | 3.4; 3.6 |
| Blur | the screen behind the menu copied and blurred as a background, for the menu or per card; a later step | Image fill | 3.4 |
| Tests | the parts of 3.11 for what is not built yet (pictures compared with approved ones, images, animation, see-through) | -- | 3.11 |

Moved out: a note showing what a file holds, to plan 14.

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
- **A title that wraps:** with `"wrap": true` a card's title wraps over more lines at word breaks: within its
  `height` when one is set (the lines that fit, the last one cut with "..."), else the card as high as the lines it
  needs. Its width need is then its longest word, so it does not widen the menu. A tall card (its icon on top) wraps
  its title the same, under the icon. Not for buttons in a card with buttons.
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
- **Its colours in the editor:** each colour field of the card panel (Background, Text colour, Border, Hover
  background) is a colour picker with what a theme's colour has (3.2): the theme's own colour, a colour picked, or a
  colour of the theme's palette chosen by name; an intensity (0 - 200, 100 the colour itself) and an opacity
  (0 - 100) with an Overrule checkbox: not ticked, the colour's own opacity stays (the theme's, the palette
  colour's); ticked, the opacity set overrules it. What is chosen is written in its shortest form: nothing for the
  theme's colour as it is; `{ "intensity", "opacity" }` without `color` for the theme's colour adjusted (the DLL
  takes the theme's colour there and adjusts it, every colour of a gradient alike); `#rrggbb` or the palette name
  alone at intensity 100 without an overruled opacity; else `{ "color", "intensity", "opacity" }` with what is given.
  A field first says what it holds: a colour, a gradient (the backgrounds only, the colours the DLL draws as one), or
  other as JSON (a gradient of more colours, `none`); later an image for some. A gradient has its From and To on rows
  of their own, each a colour or a palette colour with its intensity and opacity as above, and its angle (90 when
  not given): `{ "gradient": [ from, to ], "angle" }`.
- **Template cards:** items Dexmenu places in a submenu itself are drawn with a template card's look (plan 02 3.3):
  the layout's, or a card's own submenu template. A template has the same look settings as a card, no rules.
- **An action or a submenu:** the same card; the mark and the click differ (an item, or a card with a menu or an
  item with a Windows submenu).

- **A note's style:** a note (plan 02 3.3) gets what a card has of its look: background, text colour (now always
  the dim colour), border, radius, and 3D border and shadow when they come; and its font: `"font": "text"` (the
  items' text, the default), `"extra"` (the smaller text of a card's extra text) or its own
  (`{ "family": "Segoe UI", "size": 11, "bold": true, "italic": false }`, each part optional, the items' font for
  what is not given). Plain text only: no markdown, so a note stays as fast and crisp as the rest of the menu. In the
  card panel a note gets the Style panel and a Font field beside its text; its style is copied and pasted as a
  card's.
- **A note's date and time:** a note's text may hold `{date}` and `{time}`: the date and the time the menu opens, in
  Windows' short date and time formats (the user's regional settings), or `{date:<picture>}` and `{time:<picture>}` in
  Windows' date and time pictures (`dddd d MMMM`, `HH:mm`). `{{` and `}}` are a brace; anything else in braces, or a
  brace that is not closed, shows as typed. The menu does not change while it is open.
- A note showing what a file holds is plan 14.
- **A 3D border:** besides a flat border, a card's border can look raised (`outset`) or sunk (`inset`), as
  Windows' classic buttons: a bevel of a width, its edges on the light side drawn in a light colour, those on the
  other side in a shadow colour, the light coming from an angle (degrees, 135 when not given: from the top left).
- **A shadow:** the card's shape in a colour, at a distance from it in the direction away from the light, under the
  card, its edge blurred by an intensity (0 a sharp edge; the higher, the softer and wider). Only on the menu's own
  background: it is cut off at the menu window's edge, never drawn on what is behind the menu.
- In the layout: `"border3d": { "style": "outset" | "inset" | "flat", "angle": 135, "width": 2, "light": <colour>,
  "shadow": <colour> }` and `"shadow": { "color": <colour>, "distance": 3, "angle": 135, "blur": 0 }`, each colour as
  any colour field (3.2). In the card panel's Style: a "3D border" part (style, angle, width, light and shadow
  colours) and a "Shadow" part (colour, distance, angle, blur); copied with the style.

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

### 6.6 Colour fields

- The DLL gives the palette of the theme the preview draws with (`DexmenuThemePalette`: `{ "<name>": "#rrggbbaa" }`,
  each palette colour resolved, `basecolor` among them); the settings app posts it to the editor with every reload,
  so a theme switched in the main window or the editor shows in the pickers.
- A colour field starts with its kind: a colour, a gradient (Background and Hover background only), other (JSON).
  A gradient of two colours reads as From and To (`fillState`, `fillValue`); one of more colours, or with the theme's
  adjusted colour as a stop (the DLL resolves a stop as a colour only), stays JSON. Its angle is a typed number.
- A picker per colour (the field's own, or From and To): a swatch (over a checkerboard, so the opacity shows; not for the theme's colour, which
  the editor does not know), a choice of the theme's, a colour (the web view's colour picker), each palette colour by
  name (its option tinted with its colour), or a gradient or other as JSON; for all but JSON an Intensity slider
  (0 - 200) and an Opacity slider (0 - 100) behind an Overrule checkbox, written when let go; beside each slider
  its exact value, which can be typed (a whole number, kept within the range). A palette name the
  theme lacks stays in the list. Switching between the theme's, a colour and a palette colour keeps the intensity and
  opacity.
- Read and written by the layout model (`colorState`, `colorValue`, `colorCss`): `#rgb` and `#rrggbbaa` read (the
  alpha as an overruled opacity); written in the shortest form of 3.6.
- The DLL (`TTheme.Color`, `TTheme.Background`): a card's own colour that is an object with an intensity or an
  opacity and no `color` or `gradient` takes the theme's own value there (without the card's look) and adjusts it;
  for a gradient each of its colours.
- Tested: the editor's self-test (reading, the theme's colour adjusted, an opacity written only when overruled, the
  shortest form, a gradient and `none` kept, the swatch's colour with an intensity below and above 100, the palette's
  alpha, an opacity); unit tests (the theme's colour, background and gradient adjusted by a card's own look); the
  palette export called for light and dark. The
  pickers themselves not yet looked at by hand.

### 6.7 A title that wraps

- `"wrap": true` (`TCard.Wrap`); in the card panel "Wrap" with the size fields. The title is laid out with word
  wrapping and word trimming ("..."); its lines centred in the card, from the top when more lines than fit. The
  extra text keeps its own line above or below the title's lines.
- The card's height without a `height`: one line's height plus the lines beyond the first; its need across: its
  longest word (with the icon slot and the mark).
- Tested: unit tests (a long title without wrap one line; with wrap the card higher; with a height two lines; a
  short title one line). Not yet looked at in the preview or a right-click.

### 6.8 A card's style copied; a card copied

- In the editor's cards view a card's right-click menu has Copy style and Paste style (also Ctrl+Shift+C and
  Ctrl+Shift+V; Ctrl+V of a copied style pastes it too). The style: `background`, `foreground`, `border`,
  `borderWidth`, `radius`, `hover`, `pressed`, `height`, `wrap`, `cardFit`, `extraAt`, `submenus`; not the name, texts,
  icon, rules or menu. Pasted, it replaces the card's: what the style does not set goes back to the theme's. It goes
  through the clipboard (`{ "dexmenu": "style", "item" }`), so it pastes in another layout's window too. Not on the
  remaining card.
- Tested: the editor's self-test (what the style holds, pasted with the card's own kept, not onto the remaining card);
  the menu rendered in the editor page.
- The same right-click menu copies the whole card (with its menu and rules) and pastes a copied card inside it as a
  duplicate: into its menu, or a card with rules becomes a card with a menu as when a card is dropped onto it; not
  inside a note, Dexmenu's own item or the remaining card (the item disabled then, as is Paste when the clipboard
  holds no card or style). A right-click outside a card pastes it at the top level: in the cards view's header at the
  top, in the gutter or between lines at that place, below the last line at the bottom. A duplicate gets new ids and
  its rules go to the end of the priority list. Tested in the editor's self-test (at the top, at a place, inside a
  card with a menu, not inside a note or the remaining card, every id once, the priorities 1..n).

### 6.9 None

- "none (not drawn)" is a kind of the Background, Hover background and Border fields, written `"none"`. The theme
  reads `"none"` as no colour (before: an unknown palette name); a framed card (plan 11) with border `"none"` draws no
  frame line, where a border not set still draws one in the dividers' colour. Tested: unit tests (a border not set
  told apart from none; none no colour) and the editor's self-test.

### 6.10 A note's style, the 3D border, the shadow

- A note reads its style as a card does (`ParseCardLook`) and its `font`; its text format is made once per font and
  kept (`NoteFormatOf`); a family that is not there falls back to the items' font. A note with a text colour of its
  own uses it, else the dim colour as before. In the editor a note's fields are Text, Text placed, Font (with family,
  size, bold, italic for its own), its size fields and the Style fields without the hover background.
- `DrawBorder` draws every card's and framed holder's border: the bevel when `border3d` says outset or inset (the
  box less the box inside it by the width, cut into four edges with 45 degree corners, each edge light, dark, or
  between the two when the light runs along it), else the flat border as before. Defaults: width 2, light from 135,
  light edges white at 90%, dark edges black at 35%.
- `DrawShadow` draws under a card, a framed holder and a styled note: the shape moved the distance away from the
  light, a blur as rings from blur/2 outside to blur/2 inside the shape (at most 16), each adding what is still
  missing so the colour ramps evenly to its own alpha. Cards are drawn inside the menu's clip, so a shadow never
  leaves the menu. Cards sit close together by default; a shadow needs a gap (a divider, a row's gap) to show.
- `border3d`, `shadow` and `font` are part of a card's style (Copy style / Paste style).
- Tested: unit tests (a note's font read; the 3D border and shadow kept in a card's look), the editor's self-test
  (the style takes them), the preview captured as a picture (outset, inset, rounded outset lit from above, sharp and
  blurred shadows, a note in its own font and colours), and the editor's fields in the headless harness.

### 6.11 A note's date and time

- `FillNote` (Dexmenu.Layout) fills a note's text: `GetDateFormatEx` and `GetTimeFormatEx` for the user's locale,
  `DATE_SHORTDATE` and `TIME_NOSECONDS` without a picture, the picture as given with one. A note view fills its text
  once, the first time it is asked for (the menu or the preview opening), and keeps it, so measuring and drawing see
  the same minute. The editor's note Text field has a hint and a tooltip listing the placeholders; the cards view
  shows the text as typed, the preview filled in.
- Tested: unit tests at a fixed moment (pictures for date, time and seconds; the short formats without braces left;
  `{{` and `}}`; an unknown placeholder and an unclosed brace as typed; a note without braces as it is), and the
  preview captured as a picture (the long date in the user's language, the time, the short date).

### 6.12 The see-through menu, the menu's shadow

- See-through: the menu has no background when its menu card's (or the theme's) background is `"none"` and no
  gradient; then the menu's fill and border are left out, and every card (items, submenus, Dexmenu's own, `<<`, the
  search box), framed holder and note gets an opaque base first, the theme's card background (else the menu's) with
  full alpha, its own background over it. Gaps between them show what is behind the menu. In the editor the menu
  card's Style says so when its background is none.
- The menu's shadow is the menu card's `shadow` (its Style), drawn as a card's (`DrawShadow`) around the level's
  rounded box, into a picture larger than the level by the shadow's distance and half its blur. At a right-click it is
  shown in a window of its own (`PresentShadow`): layered, transparent to the mouse, never active, owned by the level's
  window and placed just behind it; redrawn with the level, hidden while the level is hidden (a `replace` submenu over
  it). A see-through menu gets no window shadow (its cards have their own). In the preview it is painted under each
  level.
- Tested: the preview captured as a picture (a see-through menu with a card's shadow, a divider and a framed row; the
  menu's shadow in red to see it on the dark preview, soft to the lower right). The real menu window could not be run
  here: the test host goes through the shell, which loads the installed DLL; checked by hand after publishing.

### 6.13 A divider's own look

- A divider entry reads `height` (DIP), `background`, `border` (its line; `"none"`: no line), `foreground` (its label)
  and `font` (`TFontSpec`, shared with a note's font: `FontFormat` makes a format per font, wrapping for a note, one
  line for a label). Without its own height a divider with a label is as high as its font needs (at least the
  default). In the editor the divider panel has Height, Background, Line colour, Text colour and Font.
- Tested: a unit test (the look read; none when not given) and the preview captured as a picture (a tall divider
  with a background, a coloured line and an italic Georgia label; a label without a line; a plain line as before).

### 6.14 The focus ring; the shadow's blur

- A level's geometry has `KeyFocus`: set when the keys move the selection (`MoveSelection`, which also notes where the
  mouse is), cleared on every level when the mouse really moves (a mouse message at the same screen point keeps it).
  The selected card then gets a 2 DIP ring in the theme's `card.focused.border` inside its box. Tested: a unit test
  rendering a level with and without `KeyFocus` (the pixel on the ring differs).
- A shadow's blur is at most 16 DIP (one ring per DIP); in the editor Blur is a slider with its number, 0 to 16. The
  3D border's and the shadow's parts are drawn under them with a tree line, as a note's own font under Font.

### 6.15 The preview's outline of the selected card; sub-options as a tree

- The card selected in the editor is outlined in the preview in red (the theme's `card.marked.border`), 2.5 DIP
  outside each of its boxes on every side (5 wider and higher than the card), clear of the card's own border; drawn
  after every card and outside the cards' clip, so no card covers it. Checked in the preview captured as a picture.
- In the card panel every option with options of its own shows them under it with a tree line: Shows (per row, rows,
  the rest, templates picked), Rename (replace with), Extra text (placed), Hint regex (replace with), Font (family,
  size, bold, italic), 3D border, Shadow.

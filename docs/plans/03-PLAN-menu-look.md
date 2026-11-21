# Plan 03: The menu's look: what the Delphi DLL draws, and themes made for it

Status: not started; see Status.

- 2026-11-21: draft.

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
or image), border, corner radius, padding, gap and font. The layout positions cards on lines by the level's width,
the cards' minimum widths and weights, and their heights; a single card on a line is drawn as a menu item. A card can
overrule its background and colours in the layout. Settings pick a theme for light and one for dark.

## Status

### Built

| Part | What | Reference |
|---|---|---|

### Not yet built

| Part | What | Waits for | Reference |
|---|---|---|---|
| Engine | Direct2D and DirectWrite in the DLL: brushes, rounded rectangles, text, images, stripes; drawing into a window or an image | plan 01 Delphi DLL | 3.1 |
| Theme files | per element and state; base and differences; JSON with comments; light and dark roots | -- | 3.2; 3.3 |
| Shipped themes | light and dark, and a few on them | Theme files; Open question 3 | 3.3 |
| Menu window | popup, corners, shadow, border, background colour / gradient / image, placement, scrolling | Engine | 3.4 |
| Lines and cards | widths per level, minimum widths, weights, heights, gaps; a single card as a menu item | Engine | 3.5 |
| Card | icon, title, extra text above or below it, mark, own background and colours, every state | Lines and cards | 3.6; 3.7 |
| Dividers | a line between lines, with an optional label (left, middle, right), own height, background and colours | Engine | 3.8 |
| Other elements | icon row, search box, most used row, `<<` | Card | 3.8 |
| Submenu panels | next, under, replace: where they appear and how they look | Card; plan 02 Submenus | 3.9 |
| Blur | the screen behind the menu copied and blurred as a background, for the menu or per card; a later step, after the menu works | Menu window; Card | 3.4 |
| Preview marks | striped unavailable items, use counts, new | Card; plan 02 Preview | 3.10 |
| Tests | 3.11 | -- | 3.11 |

## 3. Details

### 3.1 The engine: what it can draw

Checked in the Delphi 10.4 on this machine: `Winapi.D2D1` (Direct2D 1.0 with DirectWrite), `Winapi.Wincodec` (WIC),
`Winapi.DwmApi`, `Winapi.UxTheme`. From them:

- **Shapes:** rectangles with rounded corners, filled and outlined, lines.
- **Brushes:** a solid colour with alpha; a linear or radial gradient between colours (the "shade"); a bitmap, drawn
  as fill, fit, centre or tiled.
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
    and its icons), `search`, `panel` (a submenu panel), `back` (the `<<` line), `scrollbar`, `badge` (counts,
    new).
  - States: `normal`, `hover`, `pressed`, `focused` (the keyboard's), `disabled`, `checked`, `default` (Windows'
    default item, bold there), `unavailable` (the preview's stripes). A state lists only what differs from `normal`.
  - Properties (what the user sets per theme: the line around a card, the roundness of its corners, its background,
    the menu's background, the space between cards and dividers): `background` (3.4; `none` for the menu: cards in
    space), `foreground` (the title, a divider's label), `extra` (the extra text's colour
    and font), `mark` (the action and submenu marks' colour), `border` (colour and width), `radius`, `padding`,
    `gap` (between cards on a line and
    between lines), `font` (family, size, weight), `iconSize`, `opacity`.
- **A palette:** named colours at the top of the theme (`accent`, `text`, `surface`, ...), used by name in the
  elements, so a theme on a base can change a few palette colours and recolour every element using them. This
  takes the place of LexPen's CSS variables.
- **Colours:** `#rgb`, `#rrggbb`, `#rrggbbaa`, `rgba(r, g, b, a)` as in LexPen's themes, or a palette name.
- **Following Windows:** `accent` can be `system` (Windows' accent colour); light or dark per Windows' mode, as the
  global settings say (plan 02 3.4: `themeLight`, `themeDark`).
- An example, in the shape it may take:

  ```json
  // Dark ocean: on Dark, bluer.
  { "name": "Dark ocean", "base": "dark",
    "palette": { "surface": "#161c27", "text": "#d8e0ee", "accent": "#6aa8ff" },
    "menu": { "normal": { "background": { "gradient": ["#161c27", "#1d2533"], "angle": 90 } } },
    "card": { "normal": { "radius": 6 },
              "hover": { "background": { "color": "rgba(106, 168, 255, .18)" } } }
  }
  ```

  (The values in the example show the shape only; the shipped values are [not yet decided].)

### 3.3 Shipped themes

- `light` and `dark`, complete, close to Windows 11's own menus so Dexmenu does not look foreign at first.
- A few on them that change the palette only. Whether every LexPen theme is carried over (as Foldex did), its app
  colours mapped onto the palette: Open question 3.

### 3.4 The menu window and backgrounds

- **A background** (for the menu, a panel, a card): one of
  - `color`: one colour, with alpha;
  - `gradient`: two or more colours, an angle (linear) or a centre (radial): the shade;
  - `image`: a file, with `fit` (`fill`, `fit`, `center`, `tile`), `opacity`, and an optional `tint` colour over it
    so text stays readable;
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
  text (`2`, `3`) or in units. The line is as tall as its tallest card; how the lower cards sit in it: Open question 1.
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
  gradient, image; `none` or alpha only on a menu with a background, 3.4), `foreground`, `border`, `radius`, `height`, `minWidth`, `weight`. Per state where wanted
  (`hover` of its own).
- **An action or a submenu:** the same card; the mark and the click differ (plan 02 3.3: one item found is an action,
  several a submenu).

### 3.7 States

- `hover` (the mouse over it), `pressed` (the button down), `focused` (the keyboard's: a ring, as Windows' focus
  rectangle), `disabled` (dimmed, no hover, no click), `checked` (Windows' checked items: a check mark where the
  icon would be, or before the title), `default` (Windows' default item: bold), `unavailable` (the preview only:
  diagonal stripes over the card, plan 02 3.8).
- A card can be in two at once (focused and hover); the theme's values combine in a fixed order: `normal`, then
  `checked` / `default`, then `hover`, `pressed`, `focused`, then `disabled` / `unavailable`.

### 3.8 The other elements

- **Icon row:** square cells of an icon each, the title as a tooltip; the same states as a card.
- **Most used row:** as an icon row, or as small cards with titles; the use count as a badge in the preview only.
- **Divider:** between two lines of cards. Without a label: a thin line. With a label: the text aligned `left`,
  `middle` or `right`, the line on the free side(s). Its own `height` (the space it takes) and `background` (colour,
  gradient or image, 3.4) where the layout gives them; the label's colour and font from the theme's `divider`, or
  the divider's own, as a card's text can have its own.
- **Search box:** a text field at the top (or where the layout puts it), shown when typing starts if the layout has
  none (plan 02 3.6); matches marked in the titles.
- **`<<`:** the first line of a `replace` submenu, with the path of the levels above it.
- **"Edit menu..." and "Windows' menu":** plain items at the end, as the layout and settings say (plan 02 3.6, 3.11).

### 3.9 Submenu panels

- **`next`:** a panel next to the card, its top level with the card's top, on the other side when there is no room;
  its own width (the level's), its own background from the theme's `panel`.
- **`under`:** a panel below the card, starting at the card's middle, over the lines below it; the card it belongs to
  stays marked.
- **`replace`:** the menu's own window shows the submenu: `<<` at the top, the level's width; the window resizes from
  its top-left corner.
- **Opening on hover:** after Windows' own menu delay (the system setting), as Windows' menus; closing when the mouse
  goes to another card. On click only: as the global setting says.
- **Animation:** Open question 2.

### 3.10 Marks of the preview

- **Unavailable:** diagonal stripes over an item that is not always there, or a card that would be empty (plan 02
  3.8), in the theme's `unavailable` colours.
- **Use counts:** a small badge with the count on each item (plan 02 3.9), when the settings app asks for it.
- **New:** a badge on items seen for the first time.
- **Useless:** a red outline around a card that can never show anything (no rules, or an invalid rule; plan 02 3.5),
  in the editor and the preview only; the theme's `invalid` colour. Distinct from the stripes: a striped card is
  sometimes there, an outlined one never.

### 3.11 Tests

- The engine draws into an image in memory: for a fixed tree, layout and theme, the picture compared with an approved
  one (per light, dark, a few DPI scales); a change in drawing shows as a difference to look at.
- Lines and cards: widths from weights and minimum widths; a line that does not fit (the level grown up to its
  maximum, the screen's edge as a limit, then the last cards wrapped), heights and
  how cards sit in a line, a single card drawn as a menu item.
- Every state of a card and their combinations; a card's own background (colour, gradient, image) and colours; the
  extra text above and below the title.
- Dividers: without a label, with a label left, middle and right; own height, background and label colour.
- A menu without a background: the gaps and corners see-through, a card asking for alpha drawn opaque and reported;
  with a background, a transparent card showing it.
- Themes: a theme on a base with only palette changes recolours every element using them; an unknown property or a
  bad colour reported, the base's value used.
- By hand: Explorer and the settings app's preview side by side, the same layout and theme, the same picture.

## 4. Open questions

1. **Cards of different heights on a line.** Stretch every card to the line's height, or keep each card's own height
   (aligned to the top)?
2. **Animation.** Submenus and the `replace` change: none (as Windows' classic menus), or a short slide or fade?
3. **LexPen's themes.** Carry every LexPen theme over (its app colours mapped onto the palette), as Foldex did, or ship
   only `light`, `dark` and a few of Dexmenu's own?

// The light / dark button at the top right of every window (docs/plans/05-PLAN-settings-windows.md 3.3): a moon while
// light (to go dark), a sun while dark (to go light). The app starts as Windows is set at that moment and turns every
// window (the page's colour scheme, the title bar, the preview) at once. Theme.show(current) draws the button.
"use strict";

const Theme = (() => {
  const ns = "http://www.w3.org/2000/svg";
  let button = null;

  function icon(dark) {
    const svg = document.createElementNS(ns, "svg");
    svg.setAttribute("viewBox", "0 0 16 16");
    svg.setAttribute("width", "16");
    svg.setAttribute("height", "16");
    svg.setAttribute("aria-hidden", "true");
    const add = (tag, attrs) => { const e = document.createElementNS(ns, tag); for (const [k, v] of Object.entries(attrs)) e.setAttribute(k, v); svg.append(e); };
    if (dark) {
      // a sun: a disc with rays
      add("circle", { cx: 8, cy: 8, r: 3.2, fill: "currentColor" });
      for (let i = 0; i < 8; i++) {
        const a = i * Math.PI / 4, c = Math.cos(a), s = Math.sin(a);
        add("line", { x1: 8 + c * 5, y1: 8 + s * 5, x2: 8 + c * 7, y2: 8 + s * 7, stroke: "currentColor", "stroke-width": 1.4, "stroke-linecap": "round" });
      }
    } else {
      // a moon: a crescent
      add("path", { d: "M10.5 2.2a6 6 0 1 0 3.3 9.6A5 5 0 0 1 10.5 2.2z", fill: "currentColor" });
    }
    return svg;
  }

  function show(current) {
    button = button || document.getElementById("themeSwitch");
    if (!button) return;
    const dark = current === "dark";
    button.replaceChildren(icon(dark));
    button.title = dark ? "Light" : "Dark";
    if (!button.dataset.wired) {
      button.dataset.wired = "1";
      button.addEventListener("click", () => chrome.webview.postMessage({ type: "theme" }));
    }
  }

  return { show };
})();

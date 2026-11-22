// The theme switch at the top right of every window (docs/plans/05-PLAN-settings-windows.md 3.3): Light, Dark, or as
// Windows' apps are. The app keeps the choice and applies it to every window (WebView2's colour scheme, which the
// pages' CSS follows with prefers-color-scheme; the title bar; the preview). Theme.show(current) marks the choice.
"use strict";

const Theme = (() => {
  const choices = [["windows", "As Windows"], ["light", "Light"], ["dark", "Dark"]];
  let box = null;

  function show(current) {
    box = box || document.getElementById("themeSwitch");
    if (!box) return;
    if (!box.childElementCount)
      for (const [value, label] of choices) {
        const b = document.createElement("button");
        b.textContent = label;
        b.dataset.theme = value;
        b.addEventListener("click", () => chrome.webview.postMessage({ type: "theme", theme: value }));
        box.append(b);
      }
    for (const b of box.children) b.classList.toggle("on", b.dataset.theme === current);
  }

  return { show };
})();

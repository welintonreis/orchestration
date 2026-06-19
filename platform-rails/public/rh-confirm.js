// Destroy Alpine component trees before Turbo swaps the body — prevents
// "perPage is not defined" and similar stale-scope errors on navigation.
// Turbo confirm setup lives in app/javascript/turbo_confirm.js (ES module).
document.addEventListener("turbo:before-render", function () {
  if (window.Alpine) window.Alpine.destroyTree(document.body);
});

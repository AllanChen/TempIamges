/* Runs before styles so the saved theme is applied before first paint. */
(function () {
  var preference;
  try { preference = localStorage.getItem('glance.theme'); } catch (_) {}
  var theme = preference === 'light' || preference === 'dark' ? preference :
    (window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark');
  document.documentElement.setAttribute('data-theme', theme);
  var meta = document.querySelector('meta[name="theme-color"]');
  if (meta) meta.content = theme === 'light' ? '#faf9f5' : '#151514';
})();

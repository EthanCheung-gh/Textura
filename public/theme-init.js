/* Apply the persisted theme before first paint. External file so production CSP
 * can keep script-src without 'unsafe-inline'. */
try {
  var storedTheme = localStorage.getItem('textura.theme');
  if (storedTheme === 'dark' || storedTheme === 'light') {
    document.documentElement.dataset.theme = storedTheme;
  }
} catch (error) {
  /* Private mode / unavailable localStorage: keep the default light theme. */
}

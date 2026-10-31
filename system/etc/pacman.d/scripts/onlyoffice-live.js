// Loaded by OnlyOffice's pages (see onlyoffice-theme-patch.sh): picks up a new matugen palette
// without a restart. Matugen's post_hook writes the runtime file, which calls __matugenTheme.
(function () {
    // Editors are file:// pages, but the start page is onlyoffice://plugin/ and can't load file://
    // URLs: it reaches the runtime file through a symlink next to this script
    const here = new URL(document.currentScript.src);
    const themeFile = here.protocol === "file:"
        ? "file:///run/user/@UID@/onlyoffice-matugen.js"
        : new URL("matugen-theme.js", here).href;
    let last = "";

    window.__matugenTheme = function (theme) {
        const body = document.body;
        const json = JSON.stringify(theme);
        if (!body || json === last || !body.classList.contains(theme.id)) return;
        last = json;

        let style = document.getElementById("matugen-live");
        if (!style) {
            style = document.createElement("style");
            style.id = "matugen-live";
            document.head.appendChild(style);
        }
        const vars = Object.entries(theme.colors).map(([name, value]) => `--${name}:${value}`);
        style.textContent = `:root body.${theme.id}{${vars.join(";")}}`;

        // The document canvas (rulers, scrollbars, page edge) draws from these, not from CSS
        const editor = window.Asc && window.Asc.editor;
        if (editor && editor.asc_setSkin)
            editor.asc_setSkin({ ...theme.colors, type: theme.type, name: theme.id });
    };

    // onlyoffice:// answers any URL with a query string with an empty file, so it can't cache-bust
    function pollStartPage() {
        const request = new XMLHttpRequest();
        request.open("GET", themeFile);
        request.onload = () => new Function(request.responseText)();
        request.send();
    }

    function pollEditor() {
        const script = document.createElement("script");
        script.src = `${themeFile}?${Date.now()}`;
        script.onload = script.onerror = () => script.remove();
        document.head.appendChild(script);
    }

    setInterval(here.protocol === "file:" ? pollEditor : pollStartPage, 2000);
})();

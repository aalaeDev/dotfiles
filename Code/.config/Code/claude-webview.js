// Claude Code's webview in Code OSS: groups the chat under my main steps. claude-code-patch.sh appends
// this to the extension's index.js. Chat rows are flat siblings, and a mod only draws one row at a time,
// so only the page can indent and collapse a run of them. It writes data attributes, which React leaves
// alone, and claude-webview.css does the rest. Skins draws the step rows this looks for.
(() => {
    const STORE = "dot-steps-closed";
    let closed = new Set();
    try {
        closed = new Set(JSON.parse(localStorage.getItem(STORE) ?? "[]"));
    } catch {}

    const mark = (row, name, value) => {
        const current = row.getAttribute(name);
        if (value === null ? current !== null : current !== value) {
            if (value === null) row.removeAttribute(name);
            else row.setAttribute(name, value);
        }
    };

    const apply = () => {
        let step = null;
        for (const row of document.querySelectorAll('[data-transcript-message]')) {
            const text = (row.querySelector('[data-engine-site="ToolUse"]')?.textContent ?? "").trim();
            let role = null;
            if (row.getAttribute("data-testid") !== "assistant-message") step = null;
            else if (/^Step \d+\/\d+/.test(text)) {
                step = row.getAttribute("data-bookmark-uuid");
                role = "head";
            } else if (text.startsWith("Steps done")) {
                step = null;
                role = "end";
            } else if (step !== null) role = "body";
            mark(row, "data-dot-step", role);
            mark(row, "data-dot-closed", step !== null && closed.has(step) && role !== "end" ? "" : null);
        }
    };

    let queued = false;
    const schedule = () => {
        if (queued) return;
        queued = true;
        requestAnimationFrame(() => {
            queued = false;
            apply();
        });
    };

    document.addEventListener("click", event => {
        const head = event.target.closest?.('[data-dot-step="head"]');
        if (!head || event.target.closest("button, a")) return;
        const id = head.getAttribute("data-bookmark-uuid");
        if (!closed.delete(id)) closed.add(id);
        try {
            localStorage.setItem(STORE, JSON.stringify([...closed].slice(-200)));
        } catch {}
        apply();
    });

    new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true, characterData: true });
    schedule();
})();

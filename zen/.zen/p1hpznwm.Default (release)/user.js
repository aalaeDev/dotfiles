// Memory: Zen is the biggest RAM user, so let it give tabs back.
// Applied at every Zen start; changing these in about:config is overridden on restart.

// Unload background tabs when the system is low on memory (off by default)
user_pref("browser.tabs.unloadOnLowMemory", true);

// Unload tabs left idle this long; they reload when clicked
user_pref("zen.tab-unloader.timeout-minutes", 15);

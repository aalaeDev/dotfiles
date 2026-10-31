#!/bin/sh
# OnlyOffice's editors look up local themes as a map, but the app passes an array, so they
# fall back to the stock dark colors. Their theme style also loses to :root .theme-type-dark,
# and the start page treats every local theme as light. Also adds the live palette reloader.
# Safe to run again: the patterns no longer match once patched.
app="${1:-/opt/onlyoffice/desktopeditors}"
here="${0%/*}"

# Whoever has the theme installed owns the runtime folder matugen's post_hook writes to
uid=$(stat -c %u /home/*/.local/share/onlyoffice/desktopeditors/uithemes/matugen.json 2> /dev/null | head -n 1)
uid="${uid:-1000}"
sed "s/@UID@/$uid/" "$here/onlyoffice-live.js" > "$app/matugen-live.js"
chmod 644 "$app/matugen-live.js"
ln -sfn "/run/user/$uid/onlyoffice-matugen.js" "$app/matugen-theme.js"
tag="<script src=\"file://$app/matugen-live.js\"></script>"

# The start page isn't a file:// page: it needs the relative path (and replaces the old absolute tag)
sed -i \
    -e 's/xi\[t\]?xi\[t\]\.type:"light"/xi[t]?xi[t].type:(window.RendererProcessVariable?.localthemes||[]).find(x=>x?.id==t)?.type||"light"/' \
    -e "s#<script src=\"file://[^\"]*matugen-live\.js\"></script>#<script src=\"matugen-live.js\"></script>#" \
    "$app/index.html"
grep -q 'matugen-live' "$app/index.html" || sed -i '0,/<\/head>/s#</head>#<script src="matugen-live.js"></script></head>#' "$app/index.html"
echo "   $app/index.html"

find "$app/editors/web-apps/apps" -name 'index*.html' -exec grep -l 'map_themes' {} + | while IFS= read -r page; do
    sed -i \
        -e 's/if(map_themes&&map_themes\[theme\.id\]){window\.uitheme\.colors=map_themes\[theme\.id\]\.colors}/{const t=[].concat(map_themes||[]).find(x=>x\&\&x.id==theme.id);if(t)window.uitheme.colors=t.colors}/' \
        -e 's/inject_style_tag("\."+objtheme\.id/inject_style_tag(":root body."+objtheme.id/' \
        "$page"
    grep -q 'matugen-live' "$page" || sed -i "0,/<\/head>/s#</head>#$tag</head>#" "$page"
    echo "   $page"
done

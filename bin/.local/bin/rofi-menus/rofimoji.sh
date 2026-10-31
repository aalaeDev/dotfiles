# Copy here rather than with --action copy: rofimoji would copy nothing over the clipboard when toggle.sh closes rofi
emoji=$(rofimoji --selector-args="-theme ~/.config/rofi/emoji.rasi -kb-row-left Left -kb-row-right Right -kb-move-char-back Control+b -kb-move-char-forward Control+f" --hidden-descriptions --action print --max-recent 0)
[ -n "$emoji" ] && printf '%s' "$emoji" | wl-copy

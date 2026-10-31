#!/usr/bin/env bash

# Screenshots: every capture is saved, copied, then offered in a notification with actions.
#
#   screenshot.sh region|output|window    Capture an area, the active screen or a window
#   screenshot.sh pretty                  Capture an area and frame it for sharing
#   screenshot.sh text                    Copy the text of an area (OCR)
#   screenshot.sh gif                     Start recording an area to a GIF, or stop recording
#   screenshot.sh edit <file>             Annotate a screenshot, keeping the original
#   screenshot.sh upscale <file>          Make a 2x copy, for apps that would stretch it blurry

# --- Configuration ---
SCREENSHOTS_DIR="${SCREENSHOTS_DIR:-$HOME/Pictures/Screenshots}"
SAVE_PATH="$SCREENSHOTS_DIR/$(date +%Y-%m)"
FILE_NAME="$(date +%Y-%m-%d_%H%M%S)"
COLORS="$HOME/.config/rofi/colors.rasi"
SELF="$(realpath "$0")"
BIN="$(dirname "$SELF")"
OVERLAY="$HOME/.local/bin/screenshot-overlay.py"
NOTIFY_TIMEOUT=8000
OPAQUE_SETTLE=0.1
FRAME_PADDING=64
FRAME_RADIUS=14
GIF_FPS=15
GIF_MAX_WIDTH=960

# --- Helpers ---
color() {
    sed -n "s/^ *$1: *\(#[0-9a-fA-F]*\);.*/\1/p" "$COLORS"
}

# Translucent windows show the blurred wallpaper behind their text: not in screenshots
set_opaque() {
    local commands
    commands=$(hyprctl clients -j | jq -r --arg value "$1" '.[] | (["force_rgbx", "opaque"][]) as $prop
        | "dispatch hl.dsp.window.set_prop({window=\"address:\(.address)\", prop=\"\($prop)\", value=\"\($value)\"});"')
    hyprctl --batch "$commands" > /dev/null
}

# Hyprshot returns while it is still saving: it runs this script on the file once it's done
capture() {
    mkdir -p "$SAVE_PATH"
    set_opaque 1
    sleep "$OPAQUE_SETTLE"
    hyprshot "$@" -s -o "$SAVE_PATH" -f "$FILE_NAME.png" -- "$SELF"
    sleep "$OPAQUE_SETTLE"
    set_opaque unset
}

edit() {
    if ! command -v satty > /dev/null; then
        notify-send -a Screenshot "Can't edit the screenshot" "satty isn't installed"
        return 1
    fi
    satty --filename "$1" --output-filename "${1%.*}-edited.png" --copy-command wl-copy --early-exit
}

upscale() {
    local output="${1%.*}-2x.png"
    magick "$1" -filter Lanczos -resize 200% -unsharp 0x0.8+0.6+0 "$output" || return 1
    wl-copy --type image/png < "$output"
    offer "$output" "2x copy saved"
}

# Wait for the notification, it reports the button that was clicked
offer() {
    local file="$1" title="$2" actions=(-A open=Open -A delete=Delete)
    [[ "$file" == *.png ]] && actions=(-A edit=Edit -A upscale=2× "${actions[@]}")

    case "$(notify-send -a Screenshot -i "$file" -t "$NOTIFY_TIMEOUT" "${actions[@]}" --wait "$title" "${file##*/}")" in
        edit)    edit "$file" ;;
        upscale) upscale "$file" ;;
        open)    xdg-open "$file" ;;
        delete)  gio trash "$file" ;;
    esac
}

# Rounded corners and a shadow, on a background following the theme
frame() {
    local file="$1" width height
    read -r width height < <(magick identify -format '%w %h' "$file")

    magick -size "$((width + FRAME_PADDING * 2))x$((height + FRAME_PADDING * 2))" \
        "gradient:$(color selected)-$(color tertiary)" \
        \( "$file" -alpha set \
            \( -size "${width}x${height}" xc:none -fill white \
                -draw "roundrectangle 0,0,$((width - 1)),$((height - 1)),$FRAME_RADIUS,$FRAME_RADIUS" \) \
            -compose DstIn -composite -compose Over \
            \( +clone -background black -shadow 50x18+0+10 \) +swap \
            -background none -layers merge +repage \) \
        -gravity center -composite -depth 8 "$file"
    wl-copy --type image/png < "$file"
}

# Called by hyprshot on each saved capture
finish() {
    local file="$1"
    "$BIN/sound.sh" screenshot &
    [[ -n "$SCREENSHOT_FRAME" ]] && frame "$file"
    # Lossless: only the file gets smaller. Nothing to wait for, the clipboard already has the image
    command -v oxipng > /dev/null && oxipng --quiet --opt 2 --strip safe "$file" &
    offer "$file" "Screenshot saved"
}

# Upscaled because tesseract reads screen-sized text poorly. Reads with every language installed.
read_text() {
    local image text languages
    if ! command -v tesseract > /dev/null; then
        notify-send -a Screenshot "Can't read text" "tesseract isn't installed"
        return 1
    fi
    image=$(mktemp --suffix=.png)
    trap 'rm -f "$image"' RETURN
    # Through cat, to wait for the capture hyprshot leaves running behind it
    hyprshot -m region -z -s --raw | cat > "$image"
    [[ -s "$image" ]] || return 0

    languages=$(tesseract --list-langs 2> /dev/null | tail -n +2 | grep -vx osd | paste -sd +)
    text=$(magick "$image" -resize 200% png:- | tesseract - - -l "$languages" 2> /dev/null)
    text=$(sed -e 's/[[:space:]]*$//' <<< "$text")
    if [[ -z "$text" ]]; then
        notify-send -a Screenshot "No text found"
        return 0
    fi
    printf '%s' "$text" | wl-copy
    notify-send -a Screenshot "Text copied" "$(head -c 200 <<< "$text")"
}

record_gif() {
    local geometry position size width height video overlay file="$SAVE_PATH/$FILE_NAME.gif"
    if pkill -INT -x wf-recorder; then
        "$BIN/sound.sh" record-stop &
        return 0
    fi
    if ! command -v wf-recorder > /dev/null; then
        notify-send -a Screenshot "Can't record" "wf-recorder isn't installed"
        return 1
    fi
    geometry=$(slurp -d) || return 0

    # The video encoder only takes even sizes
    read -r position size <<< "$geometry"
    width=$(( ${size%x*} / 2 * 2 ))
    height=$(( ${size#*x} / 2 * 2 ))

    video=$(mktemp --suffix=.mp4)
    trap 'rm -f "$video"' RETURN
    "$BIN/sound.sh" record-start &
    notify-send -a Screenshot -t 3000 "Recording GIF" "Press Super+Shift+Print to stop"
    # Python loads Wayland first otherwise, and the overlay ends up a regular window
    LD_PRELOAD=libgtk4-layer-shell.so "$OVERLAY" "$position ${width}x${height}" &> /dev/null &
    overlay=$!
    wf-recorder -y -g "$position ${width}x${height}" -f "$video" &> /dev/null
    kill "$overlay" 2> /dev/null

    mkdir -p "$SAVE_PATH"
    ffmpeg -y -loglevel error -i "$video" -filter_complex \
        "fps=$GIF_FPS,scale='min($GIF_MAX_WIDTH,iw)':-2:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a" \
        "$file" || { notify-send -a Screenshot "Can't save the GIF"; return 1; }
    wl-copy --type image/gif < "$file"
    offer "$file" "GIF saved"
}

# --- Main ---
case "$1" in
    region) capture -m region -z ;;
    # Plain "-m output" waits for a click to pick a monitor
    output) capture -m output -m active ;;
    window) capture -m window -z ;;
    pretty) SCREENSHOT_FRAME=1 capture -m region -z ;;
    text)   read_text ;;
    gif)    record_gif ;;
    edit)   edit "$2" ;;
    upscale) upscale "$2" ;;
    /*)     finish "$1" ;;
    *)
        echo "Usage: $0 region|output|window|pretty|text|gif|edit <file>|upscale <file>" >&2
        exit 1
        ;;
esac

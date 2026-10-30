#!/usr/bin/env bash

# Nemo's "Convert To..." action: images, video, audio and PDF pages. The menu lists what
# the selection can become. Copies land beside the originals; nothing is replaced.
#
#   file-convert.sh [--to FORMAT] FILE...

set -uo pipefail

# --- Configuration ---
APP_NAME="Convert"
ICON="applications-graphics"
IMAGE_FORMATS=(png jpg webp avif heic jxl gif bmp tiff ico pdf)
VIDEO_FORMATS=(mp4 mkv webm mov gif mp3)
AUDIO_FORMATS=(mp3 flac opus ogg m4a wav)
PDF_FORMATS=(png jpg)
MENU_THEME='window { width: 420px; } listview { lines: 8; fixed-height: true; }'

# --- Helpers ---
notify() {
    notify-send -a "$APP_NAME" -i "$ICON" "$@"
}

kind_of() {
    local mime
    mime=$(file -b --mime-type -- "$1")
    case "$mime" in
        application/pdf) echo pdf ;;
        image/*) echo image ;;
        video/*) echo video ;;
        audio/*) echo audio ;;
        *) echo other ;;
    esac
}

# First free path for $1 + $2 (name, extension): "name (2).ext" when "name.ext" is taken.
unique_path() {
    local path="$1$2" n=2
    while [[ -e $path ]]; do
        path="$1 ($n)$2"
        n=$((n + 1))
    done
    echo "$path"
}

convert_image() {
    local args=()
    case "$format" in
        jpg | bmp) args=(-background white -alpha remove -alpha off) ;;
        ico) args=(-background none -resize '256x256>' -define icon:auto-resize=256,128,64,48,32,16) ;;
    esac
    case "$format" in
        gif | webp | pdf | tiff) magick "$1" "${args[@]}" "$2" ;;
        *) magick "$1[0]" "${args[@]}" "$2" ;; # First frame of an animation, not one file per frame
    esac
}

convert_video() {
    local args=()
    case "$format" in
        mp4 | mov) args=(-c:v libx264 -crf 20 -preset medium -pix_fmt yuv420p -c:a aac -b:a 192k) ;;
        mkv) args=(-c:v libx264 -crf 20 -preset medium -c:a aac -b:a 192k) ;;
        webm) args=(-c:v libvpx-vp9 -crf 32 -b:v 0 -row-mt 1 -c:a libopus -b:a 128k) ;;
        gif) args=(-an -vf 'fps=15,scale=720:-2:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse') ;;
        mp3) args=(-vn -c:a libmp3lame -q:a 2) ;;
    esac
    ffmpeg -nostdin -loglevel error -n -i "$1" "${args[@]}" "$2"
}

convert_audio() {
    local args=(-vn)
    case "$format" in
        mp3) args+=(-c:a libmp3lame -q:a 2) ;;
        opus | ogg) args+=(-c:a libopus -b:a 160k) ;;
        m4a) args+=(-c:a aac -b:a 192k) ;;
    esac
    ffmpeg -nostdin -loglevel error -n -i "$1" "${args[@]}" "$2"
}

# PDF pages become "name-1.png", "name-2.png"... in a folder of their own
convert_pdf() {
    local flag=-png
    [[ $format == jpg ]] && flag=-jpeg
    mkdir -p "$2" && pdftoppm "$flag" -r 150 "$1" "$2/$(basename "$2")"
}

# --- Actions ---
format=""
if [[ ${1:-} == --to ]]; then
    format=$2
    shift 2
fi
[[ $# -gt 0 ]] || exit 1

kind=$(kind_of "$1")
for file in "$@"; do
    if [[ $(kind_of "$file") != "$kind" ]]; then
        notify -u normal "Mixed selection" "Select only images, only video, only audio or only PDFs."
        exit 1
    fi
done

case "$kind" in
    image) formats=("${IMAGE_FORMATS[@]}") ;;
    video) formats=("${VIDEO_FORMATS[@]}") ;;
    audio) formats=("${AUDIO_FORMATS[@]}") ;;
    pdf) formats=("${PDF_FORMATS[@]}") ;;
    *)
        notify -u normal "Can't convert this" "$(basename "$1") isn't an image, video, audio file or PDF."
        exit 1
        ;;
esac

if [[ -z $format ]]; then
    format=$(printf '%s\n' "${formats[@]}" | rofi -dmenu -i -p "" -theme-str "$MENU_THEME entry { placeholder: \"Convert $# file(s) to...\"; }") || exit 0
    [[ -n $format ]] || exit 0
fi

# Video can take minutes; say something started
[[ $kind == video ]] && notify "Converting" "$# file(s) to $format"

done=0
failed=()
for file in "$@"; do
    stem=${file%.*}
    if [[ $kind == pdf ]]; then
        output=$(unique_path "$stem-$format" "")
    else
        output=$(unique_path "$stem" ".$format")
    fi
    if "convert_$kind" "$file" "$output" 2> /dev/null; then
        done=$((done + 1))
    else
        rm -rf "$output"
        failed+=("$(basename "$file")")
    fi
done

if [[ ${#failed[@]} -gt 0 ]]; then
    notify -u critical "Converted $done of $#" "Failed: ${failed[*]}"
    exit 1
fi
notify "Converted" "$done file(s) to $format"

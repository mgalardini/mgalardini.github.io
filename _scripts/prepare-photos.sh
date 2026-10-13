#!/usr/bin/env bash
#
# Prepare photos for the website: resize originals to web versions plus
# gallery thumbnails, removing all metadata (EXIF, GPS location, XMP, IPTC,
# colour profiles, comments).
#
# Usage: _scripts/prepare-photos.sh IN_DIR OUT_DIR
#
#   IN_DIR   folder with the original .jpg/.jpeg files (not searched recursively)
#   OUT_DIR  where the results go, e.g. static/img/photography/<post>
#            OUT_DIR/<name>.jpg         1600px on the long side, quality 85
#            OUT_DIR/thumbs/<name>.jpg  400px on the long side, quality 80
#
# Originals are never modified. Existing files in OUT_DIR with the same name
# are overwritten. Metadata is removed twice (ImageMagick, then exiftool), and
# every output file is checked with exiftool afterwards: the script fails if
# anything besides the basic JPEG/JFIF header is left.
#
# Requires ImageMagick (6 or 7) and exiftool.

set -euo pipefail

WEB_SIZE=1600
WEB_QUALITY=85
THUMB_SIZE=400
THUMB_QUALITY=80
DENSITY=150
SRGB_PROFILE=/usr/share/color/icc/colord/sRGB.icc

usage() {
    echo "Usage: $0 IN_DIR OUT_DIR" >&2
    exit 1
}

[ $# -eq 2 ] || usage
in_dir=$1
out_dir=$2

[ -d "$in_dir" ] || { echo "Error: input folder '$in_dir' does not exist" >&2; exit 1; }

# ImageMagick 7 uses `magick`, ImageMagick 6 uses `convert`/`identify`
if command -v magick >/dev/null 2>&1; then
    im_convert=(magick)
elif command -v convert >/dev/null 2>&1; then
    im_convert=(convert)
else
    echo "Error: ImageMagick is not installed" >&2
    exit 1
fi

command -v exiftool >/dev/null 2>&1 || { echo "Error: exiftool is not installed" >&2; exit 1; }

mkdir -p "$out_dir/thumbs"

# Refuse to write into the input folder, so originals can't be overwritten
if [ "$(cd "$in_dir" && pwd -P)" = "$(cd "$out_dir" && pwd -P)" ]; then
    echo "Error: IN_DIR and OUT_DIR must be different folders" >&2
    exit 1
fi

# Removes any metadata ImageMagick left behind, keeping only the JFIF header
# (which holds the dpi)
strip_metadata() {
    exiftool -q -q -overwrite_original -all= --jfif:all "$1"
}

# Fails if an image carries anything besides basic file information and the
# JFIF header, or if exiftool reports a problem (e.g. data appended after the
# image, as in motion photos)
check_clean() {
    local file=$1 leftovers warnings
    leftovers=$(exiftool -a -G0 -s -e "$file" | grep -vE '^\[(ExifTool|System|File|JFIF)\]' || true)
    warnings=$(exiftool -q -q -s3 -Warning "$file")
    if [ -n "$leftovers$warnings" ]; then
        echo "Error: metadata left in $file:" >&2
        echo "$leftovers$warnings" >&2
        exit 1
    fi
}

shopt -s nullglob nocaseglob
files=("$in_dir"/*.jpg "$in_dir"/*.jpeg)
shopt -u nocaseglob

[ ${#files[@]} -gt 0 ] || { echo "Error: no .jpg/.jpeg files in '$in_dir'" >&2; exit 1; }

for src in "${files[@]}"; do
    name=$(basename "$src")
    name="${name%.*}.jpg"

    # Photos with a colour profile other than sRGB (e.g. Display P3) are
    # converted to sRGB first, so colours don't shift when the profile is
    # stripped. sRGB photos (all Pixel photos so far) need no conversion.
    colour=()
    profile=$(exiftool -q -q -s3 -ICC_Profile:ProfileDescription "$src")
    if [ -n "$profile" ] && [[ "$profile" != sRGB* ]]; then
        [ -f "$SRGB_PROFILE" ] || { echo "Error: $name has a '$profile' colour profile, but $SRGB_PROFILE is missing" >&2; exit 1; }
        echo "$name: converting colours from '$profile' to sRGB"
        colour=(-profile "$SRGB_PROFILE")
    fi

    # -auto-orient applies the EXIF rotation before -strip removes it
    "${im_convert[@]}" "$src" -auto-orient ${colour[@]+"${colour[@]}"} \
        -resize "${WEB_SIZE}x${WEB_SIZE}>" -strip \
        -density "$DENSITY" -units PixelsPerInch \
        -quality "$WEB_QUALITY" -sampling-factor 4:2:0 -interlace JPEG \
        "$out_dir/$name"

    "${im_convert[@]}" "$src" -auto-orient ${colour[@]+"${colour[@]}"} \
        -thumbnail "${THUMB_SIZE}x${THUMB_SIZE}>" -strip \
        -density "$DENSITY" -units PixelsPerInch \
        -quality "$THUMB_QUALITY" \
        "$out_dir/thumbs/$name"

    strip_metadata "$out_dir/$name"
    strip_metadata "$out_dir/thumbs/$name"
    check_clean "$out_dir/$name"
    check_clean "$out_dir/thumbs/$name"

    echo "$name: $(du -h "$out_dir/$name" | cut -f1), thumbnail $(du -h "$out_dir/thumbs/$name" | cut -f1)"
done

echo "Done: ${#files[@]} photos written to $out_dir (metadata check passed)"

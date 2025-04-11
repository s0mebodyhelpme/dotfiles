#!/bin/bash

WALLPAPER_DIR="$HOME/Pictures/wallpapers"
INDEX_FILE="$HOME/.wallpaper_index"

if [ ! -f "$INDEX_FILE" ]; then
  echo 0 > "$INDEX_FILE"
fi

# Index wallpapers
mapfile -t WALLPAPERS < <(find "$WALLPAPER_DIR" -type f \( -iname '*.mp4' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.bmp' -o -iname '*.gif' \))
TOTAL_WALLPAPERS=${#WALLPAPERS[@]}

# Terminate any running swww processes
# killall swww

# Read the current index from the index file
CURRENT_INDEX=$(cat "$INDEX_FILE")

# Adjust the index based on the user input
case "$1" in
  next)
    CURRENT_INDEX=$(( (CURRENT_INDEX + 1) % TOTAL_WALLPAPERS ))
    ;;
  prev)
    CURRENT_INDEX=$(( (CURRENT_INDEX - 1 + TOTAL_WALLPAPERS) % TOTAL_WALLPAPERS ))
    ;;
  random)
    CURRENT_INDEX=$(( RANDOM % TOTAL_WALLPAPERS ))
    ;;
  set)
    CURRENT_WALLPAPER="${WALLPAPERS[$CURRENT_INDEX]}"
    swww img "$CURRENT_WALLPAPER" --transition-bezier .43,1.19,1,.4 --transition-type "grow" --transition-duration 0.4 --transition-fps 60 --invert-y --transition-pos "$(hyprctl cursorpos | grep -E '^[0-9]' || echo "0,0")" &
    exit 0
    ;;
  *)
    echo "Usage: $0 {next|prev|random|set}"
    exit 1
    ;;
esac

# Save the new index
echo "$CURRENT_INDEX" > "$INDEX_FILE"

# Get the new current wallpaper
CURRENT_WALLPAPER="${WALLPAPERS[$CURRENT_INDEX]}"

# Set the new wallpaper
swww img "$CURRENT_WALLPAPER" --transition-bezier .43,1.19,1,.4 --transition-type "grow" --transition-duration 0.4 --transition-fps 60 --invert-y --transition-pos "$(hyprctl cursorpos | grep -E '^[0-9]' || echo "0,0")" &

# Wait for a short period to ensure swww has set the wallpaper
sleep 0.1

# Send notification with the filename

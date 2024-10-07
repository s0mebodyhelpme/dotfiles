#!/bin/bash

WALLPAPER_DIR="$HOME/Pictures/wallpapers"
INDEX_FILE="$HOME/.wallpaper_index"

if [ ! -f "$INDEX_FILE" ]; then
  echo 0 > "$INDEX_FILE"
fi

# Index wallpapers
mapfile -t WALLPAPERS < <(find "$WALLPAPER_DIR" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.bmp' -o -iname '*.gif' \))
TOTAL_WALLPAPERS=${#WALLPAPERS[@]}

# Terminate any running swaybg processes
killall swaybg

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
    swaybg -i "$CURRENT_WALLPAPER" -m fill &
    notify-send "Wallpaper changed" "$(basename "$CURRENT_WALLPAPER")"
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
swaybg -i "$CURRENT_WALLPAPER" -m fill &

# Wait for a short period to ensure swaybg has set the wallpaper
sleep 0.1

# Send notification with the filename
notify-send "Wallpaper changed" "$(basename "$CURRENT_WALLPAPER")"

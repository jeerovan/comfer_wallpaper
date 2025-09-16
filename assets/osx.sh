#!/bin/bash

# --- Configuration ---
TARGET_USER=$(whoami) # current logged-in user
API_URL="https://comfer.jeerovan.com/api?view=landscape&name=jeerovan&hour=$(date +%H)" # change to your API URL

WALLPAPER_DIR="/Users/$TARGET_USER/Pictures/Wallpapers"
mkdir -p "$WALLPAPER_DIR"

# Fetch JSON response from API
API_RESPONSE=$(curl -s "$API_URL")

# Extract imageUrl from JSON using /usr/bin/plutil (macOS built-in tool for JSON)
IMAGE_URL=$(echo "$API_RESPONSE" | /usr/bin/plutil -extract imageUrl raw -o - -)

# Validate IMAGE_URL
if [[ -z "$IMAGE_URL" || "$IMAGE_URL" == "null" ]]; then
  echo "Failed to fetch imageUrl from API response."
  exit 1
fi

# Download image (use timestamp for filename)
IMAGE_NAME=$(date +%s).jpg
IMAGE_PATH="$WALLPAPER_DIR/$IMAGE_NAME"
curl -s -L "$IMAGE_URL" -o "$IMAGE_PATH"

# Set desktop wallpaper using AppleScript (for the current user)
osascript -e "tell application \"System Events\" to set picture of every desktop to \"$IMAGE_PATH\""

echo "Wallpaper set to $IMAGE_PATH"
exit 0

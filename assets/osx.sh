#!/bin/zsh

TARGET_USER=$(whoami)
WALLPAPER_DIR="/Users/$TARGET_USER/Downloads"
FILENAME_FILE="$WALLPAPER_DIR/wallpaper_file_name.txt"

if [[ ! -f "$FILENAME_FILE" ]]; then
  echo "Wallpaper filename file does not exist: $FILENAME_FILE"
  exit 1
fi

IMAGE_NAME=$(cat "$FILENAME_FILE")
IMAGE_PATH="$WALLPAPER_DIR/$IMAGE_NAME"

if [[ ! -f "$IMAGE_PATH" ]]; then
  echo "Wallpaper image file does not exist: $IMAGE_PATH"
  exit 2
fi

osascript -e "tell application \"System Events\" to set picture of every desktop to \"$IMAGE_PATH\""
if [[ $? -ne 0 ]]; then
  echo "Failed to update wallpaper using osascript."
  exit 3
fi

echo "Wallpaper set successfully: $IMAGE_PATH"
exit 0

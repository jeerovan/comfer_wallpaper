export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

TARGET_USER=$(whoami)
API_URL="https://comfer.jeerovan.com/api?view=landscape&name=$TARGET_USER&hour=$(date +%H)"
WALLPAPER_DIR="/Users/$TARGET_USER/Pictures/Wallpapers"
mkdir -p "$WALLPAPER_DIR"

API_RESPONSE=$(curl -s "$API_URL")
IMAGE_URL=$(echo "$API_RESPONSE" | /usr/bin/plutil -extract imageUrl raw -o - -)
if [[ -z "$IMAGE_URL" || "$IMAGE_URL" == "null" ]]; then
  echo "Failed to fetch imageUrl from API."
  exit 1
fi

IMAGE_NAME=$(date +%s).jpg
IMAGE_PATH="$WALLPAPER_DIR/$IMAGE_NAME"
curl -s -L "$IMAGE_URL" -o "$IMAGE_PATH"
if [[ ! -f "$IMAGE_PATH" || ! -s "$IMAGE_PATH" ]]; then
  echo "Failed to download image: $IMAGE_URL"
  exit 2
fi

osascript -e "tell application \"System Events\" to set picture of every desktop to \"$IMAGE_PATH\""
if [[ $? -ne 0 ]]; then
  echo "Failed to update wallpaper using osascript."
  exit 3
fi

echo "Wallpaper set successfully: $IMAGE_PATH"
exit 0

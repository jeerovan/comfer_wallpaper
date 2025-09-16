#!/bin/bash

# --- Configuration ---
# Set the username of the user whose wallpaper will be changed.
TARGET_USER=`whoami`

# Set the URL for your wallpaper API endpoint.
API_URL="https://comfer.jeerovan.com/api?view=landscape"

# Directory to store wallpapers
WALLPAPER_DIR="/home/$TARGET_USER/Pictures/Wallpapers"
mkdir -p "$WALLPAPER_DIR"

# --- API and Wallpaper Logic ---
# Fetch JSON response from your wallpaper API.
API_RESPONSE=$(curl -s "${API_URL}&name=${TARGET_USER}&hour=$(date +%H)")

# Use jq to parse the JSON and extract the 'imageUrl'.
IMAGE_URL=$(echo "$API_RESPONSE" | jq -r '.imageUrl')

# FIX 1: Use a single '=' for POSIX shell compatibility to prevent 'unexpected operator' error.
if [ -z "$IMAGE_URL" ] || [ "$IMAGE_URL" = "null" ]; then
    echo "Failed to fetch imageUrl from API response."
    echo "Response was: $API_RESPONSE"
    exit 1
fi

# Download the image using wget.
IMAGE_NAME=$(date +%s).jpg
IMAGE_PATH="$WALLPAPER_DIR/$IMAGE_NAME"
wget -O "$IMAGE_PATH" "$IMAGE_URL"

# --- Set the Wallpaper for GNOME ---
# FIX 2: Pass the user's D-Bus session address directly into the sudo command's environment.
# This ensures gsettings can connect to the user's graphical session.
USER_ID=$(id -u "$TARGET_USER")
DBUS_ADDRESS="unix:path=/run/user/$USER_ID/bus"

sudo -u "$TARGET_USER" DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDRESS" gsettings set org.gnome.desktop.background picture-uri "file://$IMAGE_PATH"
sudo -u "$TARGET_USER" DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDRESS" gsettings set org.gnome.desktop.background picture-uri-dark "file://$IMAGE_PATH"

echo "Wallpaper set to $IMAGE_PATH"
exit 0


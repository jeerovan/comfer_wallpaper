#!/bin/bash

# --- Configuration ---
# Set the username of the user.
TARGET_USER=$(whoami)

# Directory where the Flutter app saves wallpapers and the text file.
# Your Flutter code uses getDownloadsDirectory(), which on Debian is typically the user's Downloads folder.
WALLPAPER_DIR="/home/$TARGET_USER/Downloads"

# Path to the file containing the current wallpaper's name.
WALLPAPER_NAME_FILE="$WALLPAPER_DIR/wallpaper_file_name.txt"

# --- Read Wallpaper Name and Set Wallpaper ---

# 1. Check if the wallpaper name file exists.
if [ ! -f "$WALLPAPER_NAME_FILE" ]; then
    echo "Error: Wallpaper name file not found at $WALLPAPER_NAME_FILE"
    echo "Please ensure the Flutter app has run at least once."
    exit 1
fi

# 2. Read the image name from the file.
IMAGE_NAME=$(cat "$WALLPAPER_NAME_FILE")

# 3. Check if the image name is empty.
if [ -z "$IMAGE_NAME" ]; then
    echo "Error: wallpaper_file_name.txt is empty."
    exit 1
fi

# 4. Construct the full path to the image.
IMAGE_PATH="$WALLPAPER_DIR/$IMAGE_NAME"

# 5. Check if the actual image file exists before trying to set it.
if [ ! -f "$IMAGE_PATH" ]; then
    echo "Error: Wallpaper image not found at $IMAGE_PATH"
    exit 1
fi

echo "Setting wallpaper to: $IMAGE_PATH"

# --- Set the Wallpaper for GNOME ---
# This ensures gsettings can connect to the user's graphical session.
USER_ID=$(id -u "$TARGET_USER")
DBUS_ADDRESS="unix:path=/run/user/$USER_ID/bus"

sudo -u "$TARGET_USER" DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDRESS" gsettings set org.gnome.desktop.background picture-uri "file://$IMAGE_PATH"
sudo -u "$TARGET_USER" DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDRESS" gsettings set org.gnome.desktop.background picture-uri-dark "file://$IMAGE_PATH"

echo "Wallpaper set to $IMAGE_PATH"
exit 0


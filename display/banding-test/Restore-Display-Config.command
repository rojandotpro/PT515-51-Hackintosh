#!/bin/zsh
set -e
sudo diskutil mount disk0s1
sudo cp '/Volumes/Multimedia/Hackintosh/display-banding-test-20261010/config-before.plist' '/Volumes/EFI/EFI/OC/config.plist'
plutil -lint '/Volumes/EFI/EFI/OC/config.plist'
echo 'Original display config restored. Restart when ready.'
read 'reply?Press Return to close.'

#!/bin/zsh
# Tap the Simulator at a point given in NATIVE screenshot pixels.
#   tapnative.sh <native_x> <native_y>
# Auto-maps native px -> screen points from the CURRENT Simulator window geometry
# (re-fetched every call, since the window moves on reboot / `open -a Simulator`).
#
# Device constants below are for iPhone 17 Pro (402x874 pt, @3x -> 1206x2622 px).
# Override for another device:  DEV_W=<ptW> DEV_H=<ptH> SCALE=<n> tapnative.sh x y
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
HERE="${0:A:h}"
nx=$1; ny=$2
: ${DEV_W:=402}; : ${DEV_H:=874}; : ${SCALE:=3}
geo=$(osascript -e 'tell application "System Events" to tell process "Simulator" to get {position, size} of (first window whose name contains "iPhone")' 2>/dev/null)
eval $(echo "$geo" | awk -F', *' -v nx=$nx -v ny=$ny -v dw=$DEV_W -v dh=$DEV_H -v sc=$SCALE \
  '{wx=$1;wy=$2;ww=$3;wh=$4; z=(wh-28)/dh; ox=wx+(ww-dw*z)/2; oy=wy+28; printf "sx=%d sy=%d\n", ox+(nx/sc)*z, oy+(ny/sc)*z}')
xcrun swift "$HERE/simclick.swift" "$sx" "$sy" >/dev/null 2>&1
echo "tapped native($nx,$ny) -> screen($sx,$sy)"

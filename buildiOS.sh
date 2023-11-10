#!/bin/sh

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# Build
xcodebuild clean archive -project Bloo.xcodeproj -scheme "Bloo" -destination generic/platform=iOS -archivePath ~/Desktop/bloo.xcarchive

if [ $? -eq 0 ]
then
echo
else
echo "!!! Archiving failed, stopping script"
exit 1
fi

# Upload to App Store
xcodebuild -exportArchive -archivePath ~/Desktop/bloo.xcarchive -exportPath ~/Desktop/BlooExport -exportOptionsPlist exportiOS.plist

if [ $? -eq 0 ]
then
echo
else
echo "!!! Exporting failed, stopping script"
exit 1
fi

# Add to Xcode organizer
open ~/Desktop/bloo.xcarchive

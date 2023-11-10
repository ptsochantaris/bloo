#!/bin/sh

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# Clean
xcodebuild clean archive -project Bloo.xcodeproj -scheme "Bloo" -destination "generic/platform=OS X" -archivePath ~/Desktop/macbloo.xcarchive

if [ $? -eq 0 ]
then
echo
else
echo "!!! Archiving failed, stopping script"
exit 1
fi

# Upload to App Store
xcodebuild -exportArchive -archivePath ~/Desktop/macbloo.xcarchive -exportPath ~/Desktop/MacBlooExport -exportOptionsPlist exportMac.plist

if [ $? -eq 0 ]
then
echo
else
echo "!!! Exporting failed, stopping script"
exit 1
fi

# Add to Xcode organizer
open ~/Desktop/macbloo.xcarchive

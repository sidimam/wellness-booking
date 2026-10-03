#!/bin/zsh
# Archive, export e upload su TestFlight/App Store Connect (stesso flusso di Unraid Drive).
# Prerequisiti: Xcode con l'account del team X5SR67A8AL, chiave ASC in ~/.appstoreconnect/private_keys/AuthKey_Z9NY29WQ4M.p8,
# issuer in ~/.appstoreconnect/private_keys/asc_issuer.txt, record dell'app creato su App Store Connect
# (bundle id com.sdimambro.wellness-booking: la prima volta va creato dal sito o da Xcode Organizer).
set -o pipefail
cd "$(dirname "$0")/.."
ISSUER="${ASC_ISSUER:-$(cat ~/.appstoreconnect/private_keys/asc_issuer.txt 2>/dev/null)}"
[ -n "$ISSUER" ] || { echo "ASC_ISSUER mancante"; exit 1 }
DD_ROOT="${DD_ROOT:-$HOME/Library/Caches/WellnessBooking-build}"; mkdir -p "$DD_ROOT"
xcodegen generate >/dev/null
xattr -cr WellnessBooking Watch Widget Shared Icons SupportFiles project.yml WellnessBooking.xcodeproj 2>/dev/null
echo "=== archive iOS"
rm -rf "$DD_ROOT/WellnessBooking-iOS.xcarchive" "$DD_ROOT/export-iOS"
xcodebuild archive -project WellnessBooking.xcodeproj -scheme WellnessBooking -destination "generic/platform=iOS" \
  -archivePath "$DD_ROOT/WellnessBooking-iOS.xcarchive" -derivedDataPath "$DD_ROOT/dd-iOS" -allowProvisioningUpdates \
  2>&1 | tee "$DD_ROOT/archive-iOS.log" | grep -E "error:|detritus|ARCHIVE"
[ -d "$DD_ROOT/WellnessBooking-iOS.xcarchive" ] || { echo "archive fallito (log: $DD_ROOT/archive-iOS.log)"; exit 1 }
xattr -cr "$DD_ROOT/WellnessBooking-iOS.xcarchive" 2>/dev/null
echo "=== export + upload"
xcodebuild -exportArchive -archivePath "$DD_ROOT/WellnessBooking-iOS.xcarchive" -exportOptionsPlist ExportOptions.plist \
  -exportPath "$DD_ROOT/export-iOS" -allowProvisioningUpdates \
  -authenticationKeyPath ~/.appstoreconnect/private_keys/AuthKey_Z9NY29WQ4M.p8 -authenticationKeyID Z9NY29WQ4M -authenticationKeyIssuerID "$ISSUER" \
  2>&1 | tee "$DD_ROOT/export-iOS.log" | grep -E "error|EXPORT|Upload"
echo "=== RELEASE DONE (controlla TestFlight su App Store Connect)"

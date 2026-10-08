#!/bin/zsh
# Archive, export e upload su TestFlight/App Store Connect (stesso flusso di Unraid Drive).
# Firma: il certificato "Apple Distribution: SIMONE DI MAMBRO (X5SR67A8AL)" è nel Portachiavi locale, quindi
# export e upload funzionano con la CHIAVE API di App Store Connect (kit: apple/AuthKey_Z9NY29WQ4M.p8 + asc_issuer.txt)
# senza dipendere dalla sessione dell'account Apple in Xcode (che scade: "App Store Connect access … is required").
# Se la chiave non c'è si torna alla sessione Xcode (-allowProvisioningUpdates). Record ASC: id 6818849644.
set -o pipefail
cd "$(dirname "$0")/.."
DD_ROOT="${DD_ROOT:-$HOME/Library/Caches/WellnessBooking-build}"; mkdir -p "$DD_ROOT"
KIT="${KIT:-/Volumes/LocalData/Claude/WellnessBooking/WellnessBooking-RecoveryKit/apple}"
AUTH=()
if [ -f "$KIT/AuthKey_Z9NY29WQ4M.p8" ] && [ -f "$KIT/asc_issuer.txt" ]; then
  AUTH=(-authenticationKeyPath "$KIT/AuthKey_Z9NY29WQ4M.p8" -authenticationKeyID Z9NY29WQ4M -authenticationKeyIssuerID "$(cat "$KIT/asc_issuer.txt")")
  echo "=== autenticazione: chiave API App Store Connect"
else
  echo "=== autenticazione: sessione account Xcode (chiave API non trovata in $KIT)"
fi
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
  -exportPath "$DD_ROOT/export-iOS" -allowProvisioningUpdates "${AUTH[@]}" \
  2>&1 | tee "$DD_ROOT/export-iOS.log" | grep -E "error|EXPORT|Upload succeeded|required"
echo "=== RELEASE DONE (controlla TestFlight su App Store Connect)"

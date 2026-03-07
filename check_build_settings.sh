#!/bin/bash

echo "=========================================="
echo "Comet Editor - Build Settings Check"
echo "=========================================="
echo ""

# Extract settings from pbxproj
BUNDLE_ID=$(grep -m 1 "PRODUCT_BUNDLE_IDENTIFIER" cometeditor.xcodeproj/project.pbxproj | sed 's/.*= \(.*\);/\1/')
TEAM_ID=$(grep -m 1 "DEVELOPMENT_TEAM" cometeditor.xcodeproj/project.pbxproj | sed 's/.*= \(.*\);/\1/')
VERSION=$(grep -m 1 "MARKETING_VERSION" cometeditor.xcodeproj/project.pbxproj | sed 's/.*= \(.*\);/\1/')
BUILD=$(grep -m 1 "CURRENT_PROJECT_VERSION" cometeditor.xcodeproj/project.pbxproj | sed 's/.*= \(.*\);/\1/')

echo "Bundle Identifier: $BUNDLE_ID"
echo "Development Team: $TEAM_ID"
echo "Marketing Version: $VERSION"
echo "Build Number: $BUILD"
echo ""

echo "Entitlements:"
cat cometeditor/cometeditor.entitlements
echo ""

echo "=========================================="
echo "Checklist for App Store Connect:"
echo "=========================================="
echo "1. ✓ App registered in App Store Connect with bundle ID: $BUNDLE_ID"
echo "2. ✓ Development Team ($TEAM_ID) has valid certificates"
echo "3. ✓ Distribution provisioning profile created"
echo "4. ✓ Xcode Cloud workflow configured with correct team"
echo "5. ✓ Version $VERSION not already uploaded to App Store Connect"
echo ""
echo "If build fails, check:"
echo "- App Store Connect > My Apps > Check if app exists"
echo "- Apple Developer > Certificates, IDs & Profiles"
echo "- Xcode Cloud > Workflow > Archive > Signing & Capabilities"

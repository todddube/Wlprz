# Wlprz for macOS
#
# The Xcode project is GENERATED from project.yml. Never hand-edit the
# .xcodeproj — regenerate it.

PROJECT := Wlprz.xcodeproj
SCHEME  := Wlprz
# DerivedData lives outside the repo: ~/Documents is iCloud-synced, and the
# FinderInfo xattrs it stamps make codesign fail with "resource fork ... not allowed".
DERIVED := $(HOME)/Library/Developer/Xcode/DerivedData/Wlprz-build
APP     := $(DERIVED)/Build/Products/Debug/Wlprz.app

.PHONY: all generate build test run icon release clean distclean

all: build

# iCloud can leave stale conflict copies ("Wlprz 2.xcodeproj") when XcodeGen
# rewrites the project mid-sync; they are always safe to delete.
generate:
	@rm -rf "Wlprz [0-9]*.xcodeproj" "project [0-9]*.yml"
	xcodegen generate --spec project.yml

build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-derivedDataPath $(DERIVED) build

test: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-derivedDataPath $(DERIVED) test

run: build
	@pkill -x Wlprz || true
	open $(APP)

icon:
	swift Scripts/make-appicon.swift Wlprz/Resources/Assets.xcassets/AppIcon.appiconset

release: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-derivedDataPath $(DERIVED) archive -archivePath build/Wlprz.xcarchive

clean:
	rm -rf build $(DERIVED)

distclean: clean
	rm -rf $(PROJECT)

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
# Versioning: the version is MARKETING_VERSION in project.yml (MAJOR.MINOR.PATCH); the
# build number is the commit count of HEAD. It grows with each commit on main, but a
# rebase/squash or a shallow clone lowers it, so releases refuse a dirty tree.
VERSION := $(shell sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' project.yml)
BUILD   := $(shell git rev-list --count HEAD 2>/dev/null || echo 1)
XCFLAGS := CURRENT_PROJECT_VERSION=$(BUILD)

.PHONY: all generate build test run icon release clean distclean version set-version

all: build

# iCloud can leave stale conflict copies ("Wlprz 2.xcodeproj") when XcodeGen
# rewrites the project mid-sync; they are always safe to delete.
generate:
	@rm -rf "Wlprz [0-9]*.xcodeproj" "project [0-9]*.yml"
	xcodegen generate --spec project.yml

build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-derivedDataPath $(DERIVED) $(XCFLAGS) build

test: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-derivedDataPath $(DERIVED) $(XCFLAGS) test

run: build
	@pkill -x Wlprz || true
	open $(APP)

icon:
	swift Scripts/make-appicon.swift Wlprz/Resources/Assets.xcassets/AppIcon.appiconset

release: generate
	@git diff --quiet HEAD || (echo "release: commit your changes first (build number = HEAD commit count)" && exit 1)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-derivedDataPath $(DERIVED) $(XCFLAGS) archive -archivePath build/Wlprz.xcarchive

version:
	@echo "Wlprz $(VERSION) ($(BUILD))"

# make set-version V=0.5.1  (semantic version: MAJOR.MINOR.PATCH)
set-version:
	@echo "$(V)" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$' || \
		(echo "usage: make set-version V=MAJOR.MINOR.PATCH, e.g. V=0.5.1" && exit 1)
	sed -i '' 's/^\( *MARKETING_VERSION: *\)".*"/\1"$(V)"/' project.yml
	@grep -q 'MARKETING_VERSION: "$(V)"' project.yml || (echo "set-version: project.yml not updated" && exit 1)
	@$(MAKE) --no-print-directory version

clean:
	rm -rf build $(DERIVED)

distclean: clean
	rm -rf $(PROJECT)

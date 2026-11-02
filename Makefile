.PHONY: build app run dev test bench clean icon dist

build:
	swift build

# Release app bundle at build/FileMaster.app
app:
	scripts/bundle-app.sh release

# Debug app bundle, (re)launched via LaunchServices
run:
	scripts/bundle-app.sh debug
	@pkill -x FileMaster; while pgrep -x FileMaster >/dev/null; do sleep 0.1; done
	open -n build/FileMaster.app

# Debug app bundle run in the foreground so logs/crashes show in the terminal
dev:
	scripts/bundle-app.sh debug
	build/FileMaster.app/Contents/MacOS/FileMaster $(DIR)

test:
	swift test

# make bench DIR=/path/to/dir
bench:
	swift run -c release fm-bench $(DIR)

clean:
	rm -rf .build build dist

# Signed DMG in dist/ (Developer ID + notarization when available, see docs/DISTRIBUTION.md)
dist:
	scripts/package.sh

# Re-render Resources/AppIcon.icns from scripts/make-icon.swift
icon:
	swift scripts/make-icon.swift

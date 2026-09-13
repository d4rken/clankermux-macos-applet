APP_NAME := Clankermux Usage
EXECUTABLE := ClankermuxUsage
BUILD_DIR := build
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS := $(APP_BUNDLE)/Contents
INSTALL_DIR := $(HOME)/Applications

.PHONY: check test app install clean

check:
	swift build

test:
	swift test

app:
	swift build -c release
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources"
	cp ".build/release/$(EXECUTABLE)" "$(CONTENTS)/MacOS/$(EXECUTABLE)"
	cp Resources/Info.plist "$(CONTENTS)/Info.plist"
	cp Resources/ProviderMarks-ATTRIBUTION.md "$(CONTENTS)/Resources/ProviderMarks-ATTRIBUTION.md"
	codesign --force --sign - "$(APP_BUNDLE)"
	@echo "Built $(APP_BUNDLE)"

install: app
	mkdir -p "$(INSTALL_DIR)"
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	cp -R "$(APP_BUNDLE)" "$(INSTALL_DIR)/"
	@echo "Installed to $(INSTALL_DIR)/$(APP_NAME).app"

clean:
	rm -rf "$(BUILD_DIR)" .build

include make/pocketbook.mk

# Keep hard-float packages distinct from the legacy PocketBook build. Besides
# making the architecture visible to users, release assets must have unique
# names because both variants are published together.
PB_PACKAGE = koreader-pocketbookhf$(KODEDUG_SUFFIX)-$(VERSION).zip
PB_PACKAGE_OTA = koreader-pocketbookhf$(KODEDUG_SUFFIX)-$(VERSION).tar.xz
PB_PACKAGE_OLD_OTA = koreader-pocketbookhf$(KODEDUG_SUFFIX)-$(VERSION).targz

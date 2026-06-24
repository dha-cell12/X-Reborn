ARCHS = armv7 armv7s arm64 arm64e
TARGET := iphone:clang:latest:10.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = InstanceXPrefs

InstanceXPrefs_FILES = InstanceXPrefs.mm
InstanceXPrefs_FRAMEWORKS = UIKit
InstanceXPrefs_INSTALL_PATH = /Library/PreferenceBundles
InstanceXPrefs_CFLAGS = -fobjc-arc
InstanceXPrefs_LDFLAGS = -Wl,-undefined,dynamic_lookup

include $(THEOS_MAKE_PATH)/bundle.mk

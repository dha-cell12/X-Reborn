ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = InstanceXPrefs

InstanceXPrefs_FILES = InstanceXPrefs.mm
InstanceXPrefs_FRAMEWORKS = UIKit Preferences
InstanceXPrefs_PRIVATE_FRAMEWORKS = Preferences
InstanceXPrefs_INSTALL_PATH = /Library/PreferenceBundles
InstanceXPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk

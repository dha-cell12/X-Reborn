TARGET := iphone:clang:latest:10.0
INSTALL_TARGET_PROCESSES = SpringBoard
ARCHS = armv7 armv7s arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = InstanceX

InstanceX_FILES = tweak.xm
InstanceX_FILES += SBMenuHooks.xm
InstanceX_FILES += ContainerManager.mm
InstanceX_FILES += InstanceLayout.mm
InstanceX_FILES += InstanceManager.mm
InstanceX_FILES += InstanceModel.mm

InstanceX_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
InstanceX_CCFLAGS = -std=c++11

InstanceX_FRAMEWORKS = UIKit Foundation CoreGraphics

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += ContainerShim
SUBPROJECTS += Prefs
include $(THEOS_MAKE_PATH)/aggregate.mk

after-clean::
	rm -rf packages/*

ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:10.0

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = instancex_container_shim

instancex_container_shim_FILES = ContainerShim.m KeychainShim.m
instancex_container_shim_INSTALL_PATH = /usr/lib
instancex_container_shim_FRAMEWORKS = Foundation Security
instancex_container_shim_LDFLAGS = -Wl,-not_for_dyld_shared_cache

include $(THEOS_MAKE_PATH)/library.mk

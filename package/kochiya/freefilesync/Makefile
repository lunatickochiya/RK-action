#
# FreeFileSync headless CLI for OpenWrt
#
# Upstream FreeFileSync is a wxWidgets/GTK GUI application.  OpenWrt has no
# GTK3/X11 stack, so this package builds the FreeFileSync synchronization
# engine together with a small console frontend.  It runs the same .ffs_batch
# jobs as the GUI's command line mode, without requiring a display.
#
# Copyright (C) 2026 lunatickochiya
#
# This is free software, licensed under the GNU General Public License v3.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=freefilesync
PKG_VERSION:=14.13
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/hkneptune/FreeFileSync.git
PKG_SOURCE_VERSION:=211948600a8d4127f33eb3c05c522ad69b985694
PKG_SOURCE_DATE:=2026-10-28
PKG_MIRROR_HASH:=skip

PKG_LICENSE:=GPL-3.0-only
PKG_LICENSE_FILES:=License.txt
PKG_MAINTAINER:=lunatickochiya

PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk

define Package/freefilesync
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=FreeFileSync headless batch runner
  URL:=https://github.com/hkneptune/FreeFileSync
  DEPENDS:= \
	+libstdcpp +libpthread \
	+libcurl +libssh2 +libopenssl +libidn2 \
	+glib2 +zlib +ca-bundle
endef

define Package/freefilesync/description
  Headless command-line runner for FreeFileSync .ffs_batch jobs.

  FreeFileSync itself is a wxWidgets/GTK GUI application, which cannot run on
  a normal OpenWrt router.  This package builds the upstream synchronization
  engine (comparison, mirror/update/two-way sync, versioning, native/FTP/SFTP/
  Google Drive backends) with a console status handler, so scheduled backup
  jobs can be run from cron without X11.

  The binary intentionally has no GUI.  Enable a job with e.g.:
    freefilesync -c /etc/freefilesync/jobs/backup.ffs_batch
endef

FFS_CXXFLAGS := \
	-std=gnu++23 -DNDEBUG -pthread -fPIC \
	-ffunction-sections -fdata-sections \
	-I$(PKG_BUILD_DIR) \
	-I$(PKG_BUILD_DIR)/zenXml \
	-I$(PKG_BUILD_DIR)/FreeFileSync/Source \
	-I$(PKG_BUILD_DIR)/headless/shim \
	-I$(PKG_BUILD_DIR)/headless \
	-I$(STAGING_DIR)/usr/include \
	-I$(STAGING_DIR)/usr/include/glib-2.0 \
	-I$(STAGING_DIR)/usr/lib/glib-2.0/include \
	-include zen/i18n.h \
	-DWXINTL_NO_GETTEXT_MACRO

FFS_LDFLAGS := -Wl,--gc-sections -Wl,--as-needed

FFS_LIBS := \
	-lcurl -lssh2 -lssl -lcrypto -lidn2 \
	-lgio-2.0 -lgobject-2.0 -lglib-2.0 -lz -pthread

define Build/Prepare
	$(call Build/Prepare/Default)
	$(INSTALL_DIR) $(PKG_BUILD_DIR)/headless/shim/wx+
	$(CP) $(CURDIR)/src/*.cpp $(CURDIR)/src/*.h $(PKG_BUILD_DIR)/headless/
	$(CP) $(CURDIR)/src/shim/wx+/image_holder.h $(PKG_BUILD_DIR)/headless/shim/wx+/
endef

define Build/Compile
	$(MAKE) -C $(CURDIR)/src -f Makefile.headless \
		$(PKG_JOBS) \
		BUILD_DIR="$(PKG_BUILD_DIR)" \
		OUT_DIR="$(PKG_BUILD_DIR)/freefilesync-build" \
		CXX="$(TARGET_CXX)" \
		CXXFLAGS="$(TARGET_CXXFLAGS) $(TARGET_CPPFLAGS) $(FFS_CXXFLAGS)" \
		LDFLAGS="$(TARGET_LDFLAGS) $(FFS_LDFLAGS)" \
		LIBS="$(FFS_LIBS)"
endef

define Package/freefilesync/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/freefilesync-build/freefilesync $(1)/usr/bin/freefilesync
	$(LN) freefilesync $(1)/usr/bin/FreeFileSync

	$(INSTALL_DIR) $(1)/etc/freefilesync/jobs
	$(INSTALL_DIR) $(1)/usr/share/doc/freefilesync
	$(INSTALL_DATA) $(CURDIR)/README.md $(1)/usr/share/doc/freefilesync/README.md

	$(INSTALL_DIR) $(1)/usr/share/licenses/freefilesync
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/License.txt $(1)/usr/share/licenses/freefilesync/License.txt
endef

$(eval $(call BuildPackage,freefilesync))

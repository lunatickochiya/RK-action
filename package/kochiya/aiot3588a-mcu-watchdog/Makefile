# SPDX-License-Identifier: GPL-2.0-only

include $(TOPDIR)/rules.mk

PKG_NAME:=aiot3588a-mcu-watchdog
PKG_RELEASE:=2
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/aiot3588a-mcu-watchdog
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=AIOT-3588A MCU watchdog feeder
  DEPENDS:=@TARGET_rockchip +i2c-tools
  PKGARCH:=all
endef

define Package/aiot3588a-mcu-watchdog/description
 Feed the AIOT-3588A MCU watchdog to prevent periodic resets.
endef

define Build/Compile
endef

define Package/aiot3588a-mcu-watchdog/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/etc/init.d
	$(INSTALL_BIN) ./files/aiot3588a-mcu-watchdog $(1)/usr/sbin/
	$(INSTALL_BIN) ./files/aiot3588a-mcu-watchdog.init $(1)/etc/init.d/aiot3588a-mcu-watchdog
endef

$(eval $(call BuildPackage,aiot3588a-mcu-watchdog))

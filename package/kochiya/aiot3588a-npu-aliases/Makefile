# SPDX-License-Identifier: GPL-2.0-only

include $(TOPDIR)/rules.mk

PKG_NAME:=aiot3588a-npu-aliases
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/aiot3588a-npu-aliases
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=AIOT-3588A NPU device node aliases (card0/renderD129)
  DEPENDS:=@TARGET_rockchip
  PKGARCH:=all
endef

define Package/aiot3588a-npu-aliases/description
 Create /dev/dri/card0 and /dev/dri/renderD129 alias device nodes for the
 RKNPU render node. The vendor driver only exposes renderD128, while
 librknnrt's container check and device discovery expect card0/renderD129.
endef

define Build/Compile
endef

define Package/aiot3588a-npu-aliases/install
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/aiot3588a-npu-aliases.init $(1)/etc/init.d/aiot3588a-npu-aliases
endef

$(eval $(call BuildPackage,aiot3588a-npu-aliases))

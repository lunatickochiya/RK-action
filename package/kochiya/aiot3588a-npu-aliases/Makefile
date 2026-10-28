# SPDX-License-Identifier: GPL-2.0-only

include $(TOPDIR)/rules.mk

PKG_NAME:=aiot3588a-npu-aliases
PKG_RELEASE:=2
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/aiot3588a-npu-aliases
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=AIOT-3588A NPU render node discovery
  DEPENDS:=@TARGET_rockchip
  PKGARCH:=all
endef

define Package/aiot3588a-npu-aliases/description
 Create /dev/rknpu pointing at the RKNPU DRM render node.  The vendor
 driver registers a render-only DRM device whose minor depends on probe
 order relative to panthor, so fixed card0/renderD129 aliases are not
 safe and can shadow the real GPU render node.
endef

define Build/Compile
endef

define Package/aiot3588a-npu-aliases/install
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/aiot3588a-npu-aliases.init $(1)/etc/init.d/aiot3588a-npu-aliases
endef

$(eval $(call BuildPackage,aiot3588a-npu-aliases))

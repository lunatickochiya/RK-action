include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-modechange
PKG_VERSION:=3.0
PKG_RELEASE:=3
PKG_LICENSE:=GPL-3.0
PKG_MAINTAINER:=LunaticUrey <lunaticurey@gmail.com>

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
	CATEGORY:=LuCI
	SUBMENU:=3. Applications
	PKGARCH:=all
	TITLE:=LuCI app for switching Ethernet ports between LAN and WAN
	DEPENDS:=+luci-compat
endef

define Package/$(PKG_NAME)/description
	A LuCI app to move a physical Ethernet port between LAN (br-lan)
	and WAN. Works with the modern netifd "device"/bridge-ports syntax
	used by OpenWrt 21.02 and later.
endef

define Package/$(PKG_NAME)/conffiles
/etc/config/modechange
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
[ -n "$$IPKG_INSTROOT" ] || {
	/etc/init.d/rpcd reload 2>/dev/null
	rm -f /etc/modechange /usr/sbin/modechange
	rm -rf /tmp/luci*
	rm -f /tmp/modechange.pending /tmp/modechange.err /tmp/modechange.log
}
exit 0
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./files/usr/sbin/network-port-modechange $(1)/usr/sbin/network-port-modechange
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DATA) ./files/modechange $(1)/etc/config/modechange
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DATA) ./files/usr/lib/lua/luci/controller/modechange.lua \
		$(1)/usr/lib/lua/luci/controller/modechange.lua
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi
	$(INSTALL_DATA) ./files/usr/lib/lua/luci/model/cbi/modechange.lua \
		$(1)/usr/lib/lua/luci/model/cbi/modechange.lua
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./files/usr/share/rpcd/acl.d/luci-app-modechange.json \
		$(1)/usr/share/rpcd/acl.d/luci-app-modechange.json
endef

$(eval $(call BuildPackage,$(PKG_NAME)))

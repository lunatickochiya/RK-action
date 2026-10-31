#
# LuCI support for FreeFileSync headless jobs
#
# This is free software, licensed under the Apache License, Version 2.0.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-freefilesync
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=lunatickochiya

LUCI_TITLE:=LuCI support for FreeFileSync headless jobs
LUCI_DESCRIPTION:=Manage .ffs_batch jobs, schedules and run logs for the FreeFileSync headless CLI.
LUCI_DEPENDS:=+freefilesync +luci-compat
LUCI_PKGARCH:=all

define Package/$(PKG_NAME)/conffiles
/etc/config/freefilesync
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	/etc/init.d/freefilesync enable
	/etc/init.d/freefilesync reload
	rm -f /tmp/luci-indexcache.*
	rm -rf /tmp/luci-modulecache/
	/etc/init.d/rpcd reload 2>/dev/null
}
exit 0
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature

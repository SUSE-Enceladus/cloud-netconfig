.PHONY: common help install-azure install-ec2
PREFIX?=/usr
SYSCONFDIR?=/etc
UDEVRULESDIR?=$(PREFIX)/lib/udev/rules.d
NETCONFDIR?=$(SYSCONFDIR)/netconfig.d
SCRIPTDIR?=$(SYSCONFDIR)/sysconfig/network/scripts
UNITDIR?=$(PREFIX)/lib/systemd/system
DEFAULTDIR?=$(SYSCONFDIR)/default
DESTDIR?=
DEST_NETCONFDIR=$(DESTDIR)$(NETCONFDIR)
DEST_UDEVRULESDIR=$(DESTDIR)$(UDEVRULESDIR)
DEST_SCRIPTDIR=$(DESTDIR)$(SCRIPTDIR)
DEST_UNITDIR=$(DESTDIR)$(UNITDIR)
DEST_DEFAULTDIR=$(DESTDIR)$(DEFAULTDIR)


verSrc = $(shell cat VERSION)
verSpec = $(shell rpm -q --specfile --qf '%{VERSION}' cloud-netconfig.spec 2>/dev/null)

ifneq "$(verSrc)" "$(verSpec)"
$(error "Version mismatch source and spec, aborting")
endif

help:
	@echo "Type 'make install-ec2' for installation on EC2"
	@echo "Type 'make install-azure' for installation on Azure"
	@echo "Use var DESTDIR for installing into a different root."

common:
	mkdir -p $(DEST_NETCONFDIR)
	mkdir -p $(DEST_UDEVRULESDIR)
	mkdir -p $(DEST_SCRIPTDIR)
	mkdir -p $(DEST_UNITDIR)
	mkdir -p $(DEST_DEFAULTDIR)
	install -m 755 common/cloud-netconfig $(DEST_NETCONFDIR)
	install -m 755 common/cloud-netconfig-cleanup $(DEST_SCRIPTDIR)
	install -m 644 common/cloud-netconfig-default $(DEST_DEFAULTDIR)/cloud-netconfig
	install -m 755 common/cloud-netconfig-hotplug $(DEST_SCRIPTDIR)
	install -m 644 systemd/cloud-netconfig.service $(DEST_UNITDIR)
	install -m 644 systemd/cloud-netconfig.timer $(DEST_UNITDIR)

install-azure: common
	install -m 644 azure/61-cloud-netconfig-hotplug.rules $(DEST_UDEVRULESDIR)
	install -m 755 azure/functions.cloud-netconfig $(DEST_SCRIPTDIR)

install-ec2: common
	install -m 644 common/75-cloud-persistent-net-generator.rules $(DEST_UDEVRULESDIR)
	install -m 644 ec2/51-cloud-netconfig-hotplug.rules $(DEST_UDEVRULESDIR)
	install -m 755 ec2/functions.cloud-netconfig $(DEST_SCRIPTDIR)

install-gce: common
  install -m 644 common/75-cloud-persistent-net-generator.rules $(DEST_UDEVRULESDIR)
  install -m 644 gce/51-cloud-netconfig-hotplug.rules $(DEST_UDEVRULESDIR)
  install -m 755 gce/functions.cloud-netconfig $(DEST_SCRIPTDIR)

tarball:
	@test -n "$(verSrc)"
	@ln -s . cloud-netconfig-$(verSrc)
	@touch cloud-netconfig-$(verSrc).tar.bz2
	@tar chjf cloud-netconfig-$(verSrc).tar.bz2 \
		--warning=no-file-changed \
		--exclude cloud-netconfig-$(verSrc)/cloud-netconfig-$(verSrc) \
		--exclude cloud-netconfig-$(verSrc)/cloud-netconfig-$(verSrc).tar.bz2 \
		--exclude .git \
		cloud-netconfig-$(verSrc)
	@rm -f cloud-netconfig-$(verSrc)
	@ls -l cloud-netconfig-$(verSrc).tar.bz2

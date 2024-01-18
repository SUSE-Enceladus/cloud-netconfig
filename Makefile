.PHONY: common help install-azure install-ec2
PREFIX?=/usr
SYSCONFDIR?=/etc
DISTCONFDIR?=/usr/etc
LIBEXECDIR?=/usr/libexec
UDEVRULESDIR?=$(PREFIX)/lib/udev/rules.d
SCRIPTDIR?=$(LIBEXECDIR)/cloud-netconfig
UNITDIR?=$(PREFIX)/lib/systemd/system
DEFAULTDIR?=$(DISTCONFDIR)/default
NETCONFIGDIR?=$(SYSCONFDIR)/netconfig.d
NMDISPATCHDIR?=/usr/lib/NetworkManager/dispatcher.d
DESTDIR?=
DEST_UDEVRULESDIR=$(DESTDIR)$(UDEVRULESDIR)
DEST_SCRIPTDIR=$(DESTDIR)$(SCRIPTDIR)
DEST_UNITDIR=$(DESTDIR)$(UNITDIR)
DEST_DEFAULTDIR=$(DESTDIR)$(DEFAULTDIR)
DEST_NETCONFIGDIR=$(DESTDIR)$(NETCONFIGDIR)
DEST_NMDISPATCHDIR=$(DESTDIR)$(NMDISPATCHDIR)
NM_DISPATCH_SCRIPT=90-cloud-netconfig


verSrc = $(shell cat VERSION)
verSpec = $(shell sed -n -r -e '/^Version:/ s/(Version: *)([^ ]+)/\2/p' cloud-netconfig.spec)

ifneq "$(verSrc)" "$(verSpec)"
$(error "Version mismatch source and spec, aborting")
endif

help:
	@echo "Type 'make install-ec2' for installation on EC2"
	@echo "Type 'make install-azure' for installation on Azure"
	@echo "Type 'make install-gce' for installation on GCE"
	@echo "Use var DESTDIR for installing into a different root."

common:
	mkdir -p $(DESTDIR)$(UDEVRULESDIR)
	mkdir -p $(DESTDIR)$(SCRIPTDIR)
	mkdir -p $(DESTDIR)$(UNITDIR)
	mkdir -p $(DESTDIR)$(DEFAULTDIR)
	install -m 755 common/cloud-netconfig $(DESTDIR)$(SCRIPTDIR)
	install -m 755 common/cloud-netconfig-cleanup $(DESTDIR)$(SCRIPTDIR)
	install -m 644 common/cloud-netconfig-default $(DESTDIR)$(DEFAULTDIR)/cloud-netconfig
	install -m 755 common/cloud-netconfig-hotplug $(DESTDIR)$(SCRIPTDIR)
	install -m 644 systemd/cloud-netconfig.service $(DESTDIR)$(UNITDIR)
	install -m 644 systemd/cloud-netconfig.timer $(DESTDIR)$(UNITDIR)
	sed -i -r -e "s;SCRIPTDIR=.*;SCRIPTDIR=${SCRIPTDIR};g" $(DESTDIR)$(SCRIPTDIR)/cloud-netconfig
	sed -i -r -e "s;SCRIPTDIR=.*;SCRIPTDIR=${SCRIPTDIR};g" $(DESTDIR)$(SCRIPTDIR)/cloud-netconfig-hotplug
	sed -i -r -e "s;DISTCONFDIR=.*;DISTCONFDIR=${DISTCONFDIR};g" $(DESTDIR)$(SCRIPTDIR)/cloud-netconfig-hotplug
	sed -i -r -e "s;%SCRIPTDIR%;${SCRIPTDIR};g" $(DESTDIR)$(UNITDIR)/cloud-netconfig.service

install-azure: common
	install -m 644 azure/61-cloud-netconfig-hotplug.rules $(DESTDIR)$(UDEVRULESDIR)
	install -m 755 azure/functions.cloud-netconfig $(DESTDIR)$(SCRIPTDIR)
	install -m 755 azure/cleanup-stale-ifcfg $(DESTDIR)$(SCRIPTDIR)
	sed -i -e "s;%SCRIPTDIR%;${SCRIPTDIR};g" $(DESTDIR)$(UDEVRULESDIR)/*hotplug.rules

install-ec2: common
	install -m 644 common/75-cloud-persistent-net-generator.rules $(DESTDIR)$(UDEVRULESDIR)
	install -m 644 ec2/51-cloud-netconfig-hotplug.rules $(DESTDIR)$(UDEVRULESDIR)
	install -m 755 ec2/functions.cloud-netconfig $(DESTDIR)$(SCRIPTDIR)
	sed -i -e "s;%SCRIPTDIR%;${SCRIPTDIR};g" $(DESTDIR)$(UDEVRULESDIR)/*hotplug.rules

install-gce: common
	install -m 644 common/75-cloud-persistent-net-generator.rules $(DESTDIR)$(UDEVRULESDIR)
	install -m 644 gce/51-cloud-netconfig-hotplug.rules $(DESTDIR)$(UDEVRULESDIR)
	install -m 755 gce/functions.cloud-netconfig $(DESTDIR)$(SCRIPTDIR)
	sed -i -e "s;%SCRIPTDIR%;${SCRIPTDIR};g" $(DESTDIR)$(UDEVRULESDIR)/*hotplug.rules

install-netconfig-wrapper:
	mkdir -p $(DESTDIR)$(NETCONFIGDIR)
	install -m 755 common/cloud-netconfig-wrapper $(DESTDIR)$(NETCONFIGDIR)/cloud-netconfig
	sed -i -r -e "s;SCRIPTDIR=.*;SCRIPTDIR=${SCRIPTDIR};g" $(DESTDIR)$(NETCONFIGDIR)/cloud-netconfig

install-nm-dispatcher:
	mkdir -p $(DESTDIR)$(NMDISPATCHDIR)
	install -m 755 common/cloud-netconfig-nm $(DESTDIR)$(NMDISPATCHDIR)/$(NM_DISPATCH_SCRIPT)
	sed -i -r -e "s;SCRIPTDIR=.*;SCRIPTDIR=${SCRIPTDIR};g" $(DESTDIR)$(NMDISPATCHDIR)/$(NM_DISPATCH_SCRIPT)

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

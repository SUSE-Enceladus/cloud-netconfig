cloud-netconfig
===============

**cloud-netconfig** is a collection of scripts for automatically configuring
network interfaces in cloud frameworks. Currently supported are Amazon EC2,
Microsoft Azure, and Google Compute Engine. It requires netconfig (package
**sysconfig-netconfig** on openSUSE and SUSE Linux Enterprise distributions).

### Installation

If you are installing from source, run as root `make install-ec2`, `make
install-azure`, or `make install-gce` depending on your platform. Then reload
the udev rules by running `udevadm control -R`. Afterwards add
**cloud-netconfig** to the variable **NETCONFIG__MODULES__ORDER** in
`/etc/sysconfig/network/config` and restart networking (`systemctl restart
wicked.service` on SUSE Linux Enterprise Server or openSUSE distributions). On
EC2 and Azure you may want to enable the systemd timer too (see below for
details on its purpose). To do that, run `systemctl enable --now
cloud-netconfig.timer`.

### Mode of Operation

**cloud-netconfig** handles three different tasks:

- Set up unconfigured interfaces

For any network interface that does not have an associated configuration file
in `/etc/sysconfig/network`, a DHCP based configuration will be generated and
`ifup` will be called, which triggers interface configuration through `wicked`.

- Apply secondary IPv4 addresses

For all interfaces managed by **cloud-netconfig**, it will look up secondary
IPv4 addresses from the framework's metadata server and configure them on the
interface. This does not apply to Google Compute Engine, as secondary IPv4
addresses are not assigned directly through the framework.

- Create routing policies

In case the system has more than one network interface, **cloud-netconfig**
sets up routing in a way that packets are routed through the interface
associated with the source address of the packet. To do that, it creates a
separate routing table for each interface with a default route according to the
interface configration. It also creates a routing policy to use that table for
packets using any of the interface's source addresses. This ensures that
packets are routed via the correct interface.

Note: DHCP servers of cloud frameworks (this applies to Microsoft Azure at the
time of writing) may not include a gateway address in DHCP leases for secondary
IPv4 addresses. This is presumably to avoid default routes to clash. To enable
full connectivity in this case, **cloud-netconfig** assumes the gateway host to
be the first host of the sub-network assigned to the interface.

Interface configurations will be checked periodically on each DHCP lease
renewal and additionally, if the systemd timer is enabled (default on Amazon
EC2 and Microsoft Azure SUSE Linux Enterprise Server images), every 60 seconds.
**cloud-netconfig** detects changes in the metadata configuration and updates
interface configurations and routing policies accordingly. This means that IP
addresses that were removed from the virtual interface configuration will be
removed from the interface, but only addresses that were automatically added by
**cloud-netconfig** will be removed. Addresses added manually by the
administrator or by another tool (e.g. high-availability software) will not be
touched.

### Configuration

**cloud-netconfig** does not require any configuration, but it should be noted
that it will not overwrite existing interface configurations. This allows to
use specific interface configurations. **cloud-netconfig** will still set up
secondary IP addresses and routing policies. If you do not want that, set the
variable **CLOUD__NETCONFIG__MANAGE** to **no** in the `ifcfg` file in
`/etc/sysconfig/network` to disable it for the associated interface. You can
also change the default value of **CLOUD__NETCONFIG__MANAGE** in
`/etc/default/cloud-netconfig`. The default applies to newly created `ifcfg`
files, not for existing ones.

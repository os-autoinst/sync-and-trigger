# openSUSE openQA setup

## SSH access

ssh access is possible via `ariel.dmz-prg2.suse.org`. See the following snippet for your
`~/.ssh/config` file:

```
Host ariel
  HostName ariel.dmz-prg2.suse.org

Host *.opensuse.org
  ProxyJump ariel
```

There is no direct root access. You need a local user with public key authentication.

## Network Diagram
![network diagram](openqa-opensuse.png)

* the VM hosting openqa.opensuse.org is called 'ariel.opensuse.org'
* access to the internet is though the bridge 'private'
* external access from the internet goes through hydra
* logins via ssh from the suse internal network go through proxy.opensuse.org
* ariel runs dnsmasq to provide DHCP and DNS to the workers
* ariel runs ntpd to provide NTP to the workers
* there is a vsftpd running to provide capability to install over ftp

## Reaching via ssh/vnc

* it's not possible to log in to workers directly. You need to log
  in to ariel first.
* to reach VNC on the workers, e.g. to debug stuff in interactive
  mode, use ssh port forwarding, e.g.
    ssh openqa.opensuse.org -L 5991:manyboxes:5991

## Adding Workers

Prepare ariel's dnsmasq:
* /etc/hosts for the the new IP
* /etc/dnsmasq.d/openqa.conf for the MAC address

restart dnsmasq and set the new worker to DHCP

## Further reading

[innerweb wiki](https://wiki.microfocus.net/index.php/OpenQA)

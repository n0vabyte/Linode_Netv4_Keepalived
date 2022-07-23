# Linode Netv4 and Keepalived

In light of the new changes coming up with Netv4 any customer that is using IP sharing and leveraging keepalived will experience issues during failover. The purpose of this content is to help customers keep their keepalived health check compatible with the Linode's network upgrade to Netv4.

In general, customers can use the following guide if they want to configure IP failover using lelastic:

- [Configuring Failover on a Compute Instance](https://www.linode.com/docs/guides/ip-failover/#install-and-configure-lelastic)

The guide above is good if customers want IP failover when the instance becomes unreachable. **However**, client's that leverage keepalived, rely on health checks dictated by keepalived's `vrrp_script` definition. Keeplived's functionality doesn't stop working, just the method in which failover's happen are not supported anymore. This means that keepalived can still be used to configure interfaces when health checks fail as seen in a packet capture:
```
root@haproxy1:~# tcpdump host 192.168.143.241
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on eth0, link-type EN10MB (Ethernet), snapshot length 262144 bytes
15:39:23.443944 IP haproxy1.localhost > haproxy2.localhost: VRRPv2, Advertisement, vrid 51, prio 50, authtype simple, intvl 1s, length 20
15:39:24.444137 IP haproxy1.localhost > haproxy2.localhost: VRRPv2, Advertisement, vrid 51, prio 50, authtype simple, intvl 1s, length 20
15:39:25.444359 IP haproxy1.localhost > haproxy2.localhost: VRRPv2, Advertisement, vrid 51, prio 50, authtype simple, intvl 1s, length 20
15:39:26.444566 IP haproxy1.localhost > haproxy2.localhost: VRRPv2, Advertisement, vrid 51, prio 50, authtype simple, intvl 1s, length 20
```

# Configuring keepalived and lelastic

The steps outlined in this sections assumes that the customer already configured keepalived and [IP sharing](https://www.linode.com/docs/guides/managing-ip-addresses/#configuring-ip-sharing) between 2 Linodes. If the keepalived configuration is using `enable_script_security` (recommended) you will need make modifications to the sudoers file. You can read more [here](https://github.com/n0vabyte/Linode_Netv4_Keepalived/blob/main/keepalived_script_security.md). During failover testing, we will use the following designations:

- haproxy1, 192.168.143.227
- haproxy2, 192.168.143.241
- haproxy3 (observer), 192.168.209.244
- floating IP, 192.168.223.158

All actions are going to be done on haproxy1 and haproxy2. The 3rd haproxy node is going to be used an an observer to validate functionality and failover. 

## Step 1 - Install and configure lelastic

1. Installing lelastic is pretty straight forward. You can follow the steps outlined here or reference this guide for assistance:

- https://www.linode.com/docs/guides/ip-failover/#install-and-configure-lelastic

Install lelastic on both Linodes:

```
version=$(curl -sIL "https://github.com/linode/lelastic/releases/latest"  | grep "location:" | awk -F "/" {'print $NF'})
curl -LO https://github.com/linode/lelastic/releases/download/$version/lelastic.gz
gunzip lelastic.gz
chmod 755 lelastic
sudo mv lelastic /usr/local/bin/
```

We want to make sure that we are pulling from latest. If the above fails or changes in the future, please refer to the Linode guide for reference.

2. Next, create the service file for lelastic on both Linodes:
```
vim /etc/systemd/system/lelastic.service
```

3. Paste the contents of the service file and write and quit:
```
[Unit]
Description= Lelastic
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/lelastic -dcid 6 -primary -allifs
ExecReload=/bin/kill -s HUP $MAINPID

[Install]
WantedBy=multi-user.target
```

*note*: Make sure that you use the the correct `-dcid` value. This configuration is for the Newark DC which is number 6. Update that value to the DC that you are in. We can use the following info to ge the value belongs to each DC:

| ID    | Data Center   |
| :---  | :----         |
| 4     | Atlanta (Georgia, USA) |
| 2     | Dallas (Texas, USA) |
| 10    | Frankfurt (Germany) |
| 3     | Fremont (California, USA) |
| 7     | London (United Kingdom) |
| 14    | Mumbai (India) |
| 6     | Newark (New Jersey, USA) |
| 9     | Singapore |
| 16    | Sydney (Australia) |
| 11    | Tokyo (Japan)|
| 15    | Toronto (Canada) |

*NOTE:* Please make sure that the datacenter you are going to use is [supported](https://www.linode.com/docs/guides/ip-failover/#ip-sharing-availability).

4. Start the service on both Linodes
```
sudo systemctl daemon-reload
sudo systemctl start lelastic
sudo systemctl enable lelastic
```

## Step 2 - Update Keepalived

In order to get this working you will need to make changes to keepalived's `notify_master`, `notify_backup`, `notify_fault` [definitions](https://keepalived.readthedocs.io/en/latest/configuration_synopsis.html#vrrp-instance-definitions-synopsis). We are leveraging a single bash script that will log the transition and run additional commands on the node that is becoming master/primary.

1. Create notify.sh script in the keepalved directory
```
vim /etc/keepalived/notify.sh
```

2. Paste the contents of the notify.sh script
```
#!/bin/bash

keepalived_log='/tmp/keepalived.state'
function check_state {
        local state=$1
        cat << EOF >> $keepalived_log
===================================
Date:  $(date +'%d-%b-%Y %H:%M:%S')
[INFO] Now $state

EOF
        if [[ "$state" == "Master" ]]; then
                sudo systemctl restart lelastic
        else
                sudo systemctl stop lelastic
        fi
}

function main {
        local state=$1
        case $state in
        Master)
                check_state Master;;
        Backup)
                check_state Backup;;
        Fault)
                check_state Fault;;
        *)
                echo "[ERR] Provided arguement is invalid"
        esac
}
main $1
```

*note*: You can either adopt this method or incorporate into what you're already doing for state transitions. An example keepalived.conf is made available under files/keepalived.conf in case you need a reference.

## Step 3 - Test Failover

At this time we have 2 instances with keepalived and lelastic configured. In overview, we'll start lelastic on both Linodes and then restart keepalived. When the services are running, we'll trigger our health check and observe failover.

1. Start lelastic on both Linodes
```
systemctl restart lelastic
```

2. Restart keepalived and check who's the master/primary
```
systemctl restart keepalived
```

- haproxy1:
```
root@haproxy1:/etc/keepalived# cat /tmp/keepalived.state

===================================
Date:  29-Apr-2022 16:54:26
[INFO] Now Master
```

- haproxy2:
```
root@haproxy1:/etc/keepalived# cat /tmp/keepalived.state

===================================
Date:  29-Apr-2022 16:54:25
[INFO] Now Backup
```

In this case we will use haproxy1 to trigger the failover as it's the primary.

## Trigger failover

To test a controlled failover, we are calling a failover.sh script in the `vrrp_script` definition. The failover.sh looks for a trigger file and if it's there, failover happens. 
```
#!/bin/bash

trigger='/etc/keepalived/trigger.file'
if [ -f $trigger ]; then
	exit 1
else
	exit 0
fi
```


1. In preparation for failover, let's start pinging the shared IP from haproxy3
```
root@haproxy3:~# ping 192.168.223.158
PING 192.168.223.158 (192.168.223.158) 56(84) bytes of data.
64 bytes from 192.168.223.158: icmp_seq=1 ttl=61 time=0.327 ms
64 bytes from 192.168.223.158: icmp_seq=2 ttl=61 time=0.362 ms
(....)
```

2. On haproxy1 (Master), we'll create the the trigger file
```
root@haproxy1:/etc/keepalived# touch /etc/keepalived/trigger.file
```
 Let's give this about 10 seconds and we can see that our check script is failing:

```
root@haproxy1:/etc/keepalived# service keepalived status
● keepalived.service - Keepalive Daemon (LVS and VRRP)
     Loaded: loaded (/lib/systemd/system/keepalived.service; disabled; vendor preset: enabled)
(...)
May 02 16:57:39 haproxy1.localhost Keepalived_vrrp[11149]: Script `chk_haproxy` now returning 1
```

At some point you will notice a small blip in the pings from haproxy3, but pings should continue eventually resume:
```
64 bytes from 192.168.223.158: icmp_seq=72 ttl=61 time=0.351 ms
64 bytes from 192.168.223.158: icmp_seq=73 ttl=61 time=0.352 ms
64 bytes from 192.168.223.158: icmp_seq=74 ttl=61 time=0.333 ms
64 bytes from 192.168.223.158: icmp_seq=75 ttl=61 time=0.275 ms
^C
--- 192.168.223.158 ping statistics ---
75 packets transmitted, 69 received, 8% packet loss, time 75764ms
rtt min/avg/max/mdev = 0.275/0.382/0.486/0.047 ms
```

Let's check the keepalived log from haproxy1:
```
root@haproxy1:/etc/keepalived# cat /tmp/keepalived.state

===================================
Date:  29-Apr-2022 16:54:26
[INFO] Now Master

===================================
Date:  02-May-2022 16:58:24
[INFO] Now Fault
```

We can see that it is now in a fault state. Great! This is expected!

3. Check the status of haproxy2

You will see that keepalived has transitioned the floating IP to the secondary node. Let's check the keepalived status and our IP allotement:
```
root@haproxy2:/etc/keepalived# cat /tmp/keepalived.state

===================================
Date:  29-Apr-2022 16:54:25
[INFO] Now Backup

===================================
Date:  02-May-2022 16:58:26
[INFO] Now Master

root@haproxy2:~# ip a |grep inet
    inet x.x.x.x/24 brd 45.33.69.255 scope global eth0
    inet 192.168.143.241/17 scope global eth0:1
    inet 192.168.223.158/32 scope global eth0
    inet6 0000:0000::0000:0000:0000:0000/64 scope global dynamic mngtmpaddr
    inet6 0000::0000:0000:0000:0000/64 scope link
```

We can see that the log file was updated and haproxy2 is now the primary and the floating IP is indeed assigned. At this point you can go ahead and remove the trigger file from haproxy1 and it should go into a backup state.

# Disclaimer

Do not run this blindly on a production environment. Changes should be tested/planned on a staging environment before implementation.

# Security Advisory

In order for IP failover to occure in an unattended manner the notify.sh script needs to be able to restart the lelastic service. For this to happen, we are granting the keepalived_script user passwordless sudo access to systemctl to restart/stop the service.  Be advised that compromise of the keepalived_script user *may* result in priviledge escalation. 

- https://gtfobins.github.io/gtfobins/systemctl/

Upon testing -- the method denoted in GTFOBINS did not successuflly grant priviledge elevation in this scenario. However, you accept and understand that the steps provided in this procedure are provided as-is and does not guarantee a future-bulletproof configuration. 

As an administrator you accept the potential risks of using a passwordless sudo to systemctl otherwise it's the user's responsibility to employ their own solution to accomplish the same results.
# Configure keepalived with enable_script_security

In attempt to make the keepalived more secure and abide by the Principle of Least Priviledge, we will add a global option to enforce enable_script_security. Keepalived can certainly run as root, it doesn't mean that it needs to. 

To compliment the walkthrough that you are reading, we will assume that you have already installed keepalived on the system. The following is also useful if perhaps you want to update your configuration to be more secure.

# Step 1 - Add the user

By default, all scripts will be executed by the `keepalived_script` user. Let's go ahead and add that:
```
useradd -r -s /sbin/nologin -M keepalived_script
```

# Step 2 - Add to sudoers

In our procedure, our notify script needs the ability to restart/stop the lelastic service. To guarantee that our failover procedure runs unattended, we allow the user keepalived_script to be able to restart/stop the lelastic service. 

```
keepalived_script ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl restart lelastic, /usr/bin/systemctl stop lelastic
```

*Note*: Please check out [security advisory](https://github.com/n0vabyte/Linode_Netv4_Keepalived#security-advisory)

# Step 3 - Update Permissions

The last thing that we want to do is update permissions so that the keepalived user can rwx any of the files in it's config directory.

```
chown -R keepalived_script:keepalived_script /etc/keepalived
```

Having done this you should be able to use the `files/keepalived.conf` file while using enable_script_security. As always, make sure that these things are tested out first in a staging environment before implementation to avoid impacting a production system.
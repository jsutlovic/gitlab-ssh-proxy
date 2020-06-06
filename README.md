# gitlab-ssh-proxy

One if the issue with running a GitLab instance in a container is to expose the GitLab SSH in the host machine without conflicting with the existing SSH port (22) on the host. There are several alternatives online (see References below) but I believe there must be a more elegant way. Something that avoids:
- Hardcoding the UID and GID of any account in the host machine
- Running additional services/daemon in the host machine
- Duplicating GitLab's `authorized_keys` files in the host machine
- Using `iptables`

## Background

Here is how I run my GitLab container. I am using `podman` on Fedora, but it shouldn't make much different if you're using Docker.

```
podman run --detach
    --hostname gitlab
    --publish 8443:443 --publish 8080:80 --publish 2222:22
    --name gitlab
    --volume /srv/gitlab/config:/etc/gitlab:Z
    --volume /srv/gitlab/logs:/var/log/gitlab:Z
    --volume /srv/gitlab/data:/var/opt/gitlab:Z
    --volume /srv/gitlab/ssh:/gitlab-data/ssh:Z
    gitlab/gitlab-ce:latest
```

As you can see GitLab SSH service is mapped to port 2222 in the host machine. What we want to do is for a user to access the GitLab repo without using a non-standard port on the host machine. While at the same time keep the standard SSH access in the host machine for other non-git related access.

## Installation

Build and install the package

```
sudo ./setup.sh install
```

This will do the following things:
1. Copy [`gitlab-keys-check`](gitlab-keys-check) to `/usr/local/lib`
1. Copy [`gitlab-shell-proxy`](gitlab-shell-proxy) to `/usr/local/lib`
1. Install an [SE Linux Policy Module](gitlab-ssh-proxy.te) to allow the scripts executed from the SSH server to establish an SSH connection

### Host Setup

Create the `git` user on the host

```bash
sudo useradd -m git
```

Create a new SSH key-pair

```bash
sudo su - git -c "ssh-keygen -t ed25519"
```

This will generate two files:
 - `/home/git/.ssh/id_ed25519` &mdash; Private Key
 - `/home/git/.ssh/id_ed25519.pub` &mdash; Public Key

Then modify `/etc/ssh/sshd_config` on the and add the following lines. The key ingredient here is the usage of [`AuthorizedKeysCommand`](https://manpages.debian.org/unstable/openssh-server/sshd_config.5.en.html#AuthorizedKeysCommand).

```
Match User git
    PasswordAuthentication no
    AuthorizedKeysCommand /usr/local/bin/gitlab-keys-check git %u %k
    AuthorizedKeysCommandUser git
```

Reload the SSH Server

```bash
sudo systemctl reload sshd
```

## Container Setup

Copy the public key into `/gitlab-data/ssh/` inside the container. In my setup this directory mounted from `/srv/gitlab/ssh` in the host. Therefore we simply copy the file there.

```bash
sudo cp /home/git/.ssh/id_ed25519.pub /srv/gitlab/ssh/authorized_keys
```

Finally, fix the permission/ownership of the file to ensure that is only readable by the `git` user within the container.

```bash
podman exec -it gitlab /bin/sh -c \
    "chmod 600 /gitlab-data/ssh/authorized_keys; chown git:git /gitlab-data/ssh/authorized_keys"
```

## References

- https://blog.xiaket.org/2017/exposing.ssh.port.in.dockerized.gitlab-ce.html
- https://github.com/sameersbn/docker-gitlab/issues/1517#issuecomment-368265170
- https://forge.monarch-pass.net/monarch-pass/gitlab-ssh-proxy
- https://manpages.debian.org/unstable/openssh-server/sshd_config.5.en.html
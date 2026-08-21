# Base image: Rocky 8 + systemd + PSMDB 7.0 + ttyd + candidate user.
# Each level image overlays its own setup.sh and check.sh on top of this.
FROM rockylinux:8

ENV LANG=C.UTF-8
ENV container=docker

# ---- packages: systemd, PSMDB 7.0, util-linux (script), sudo, basics ----
RUN dnf install -y https://repo.percona.com/yum/percona-release-latest.noarch.rpm && \
    percona-release setup psmdb-70 && \
    dnf install -y --setopt=install_weak_deps=False \
        systemd ca-certificates wget curl procps-ng less vim-minimal nmap-ncat jq \
        util-linux sudo \
        percona-server-mongodb \
        percona-server-mongodb-shell \
        percona-server-mongodb-tools && \
    dnf clean all && rm -rf /var/cache/dnf

# ---- trim systemd units we don't need for a single-purpose container ----
RUN cd /lib/systemd/system/sysinit.target.wants/ && \
    ls | grep -v -E 'systemd-tmpfiles-setup' | xargs rm -f && \
    rm -f /lib/systemd/system/multi-user.target.wants/* \
          /etc/systemd/system/*.wants/* \
          /lib/systemd/system/local-fs.target.wants/* \
          /lib/systemd/system/sockets.target.wants/*udev* \
          /lib/systemd/system/sockets.target.wants/*initctl* \
          /lib/systemd/system/basic.target.wants/* \
          /lib/systemd/system/anaconda.target.wants/*

# ---- ttyd ----
RUN ARCH=$(uname -m) && \
    case "$ARCH" in \
        x86_64) T=x86_64 ;; \
        aarch64) T=aarch64 ;; \
        *) echo "unsupported arch $ARCH" >&2; exit 1 ;; \
    esac && \
    wget -q -O /usr/local/bin/ttyd \
        "https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.${T}" && \
    chmod +x /usr/local/bin/ttyd

# ---- candidate user + passwordless sudo (DBA-on-host pattern) ----
RUN useradd -m -s /bin/bash candidate && \
    echo "candidate ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/candidate && \
    chmod 440 /etc/sudoers.d/candidate

# ---- /etc/mongod.conf override (binds 0.0.0.0 for multi-node) ----
COPY mongod.conf /etc/mongod.conf
RUN chown root:root /etc/mongod.conf && chmod 644 /etc/mongod.conf && \
    mkdir -p /var/lib/mongo /var/log/mongo && \
    chown -R mongod:mongod /var/lib/mongo /var/log/mongo

# ---- default no-op hooks; locked down so candidates can't read them ----
RUN printf '#!/bin/sh\nexit 0\n' > /opt/setup.sh && \
    printf '#!/bin/sh\necho "no check defined"; exit 1\n' > /usr/local/bin/check.sh && \
    chown root:root /opt/setup.sh /usr/local/bin/check.sh && \
    chmod 700 /opt/setup.sh /usr/local/bin/check.sh

# ---- friendly shell + session recorder ----
RUN { \
      echo "export PS1='\\[\\033[01;32m\\]candidate@\\h\\[\\033[00m\\]:\\[\\033[01;34m\\]\\w\\[\\033[00m\\]\\$ '"; \
      echo 'echo "You are on $(hostname). mongod via: sudo systemctl status mongod"'; \
      echo 'echo "Paste/copy are disabled. Type commands yourself."'; \
    } >> /home/candidate/.bashrc && \
    chown candidate:candidate /home/candidate/.bashrc

RUN { \
      echo '#!/bin/bash'; \
      echo 'HISTDIR="/var/log/history/level-${LEVEL:-0}"'; \
      echo 'mkdir -p "$HISTDIR" 2>/dev/null || true'; \
      echo 'SESSION="$HISTDIR/${HOSTNAME:-node}.typescript"'; \
      echo 'printf "\n--- shell opened %s ---\n" "$(date -u +%FT%TZ)" >> "$SESSION"'; \
      echo 'exec script -a -q -f -c "su -l candidate" "$SESSION"'; \
    } > /usr/local/bin/candidate-shell && \
    chown root:root /usr/local/bin/candidate-shell && \
    chmod 755 /usr/local/bin/candidate-shell

# ---- interview-setup script + systemd units ----
COPY interview-setup.sh /usr/local/sbin/interview-setup
COPY rs-bootstrap /usr/local/sbin/rs-bootstrap
RUN chown root:root /usr/local/sbin/interview-setup /usr/local/sbin/rs-bootstrap && \
    chmod 700 /usr/local/sbin/interview-setup /usr/local/sbin/rs-bootstrap

COPY interview-setup.service /etc/systemd/system/interview-setup.service
COPY ttyd.service /etc/systemd/system/ttyd.service
RUN systemctl enable mongod.service interview-setup.service ttyd.service

EXPOSE 7681

VOLUME [ "/sys/fs/cgroup" ]
STOPSIGNAL SIGRTMIN+3
ENTRYPOINT [ "/sbin/init" ]

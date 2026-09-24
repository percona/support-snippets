FROM mysqlinterview/exercise-base

# Q3 has the candidate install Percona Server on a "freshly provisioned"
# node3. The skill being tested is knowing to install the server and enable
# the service — not waiting on a mirror. Left to real repos, refreshing
# Rocky's AppStream metadata alone took over four minutes on a slow mirror,
# and mirror speed varies per candidate, which makes the exam unfair as well
# as slow.
#
# So: stage the RPMs in a local file:// repo, give it priority over the
# remote one, and pre-warm the dnf metadata cache with metadata_expire
# disabled so dnf never goes back to the network. `dnf install
# percona-server-server` then behaves exactly as a candidate expects but
# resolves offline in seconds.
#
# `dnf download` lives in dnf-plugins-core — without it the command does not
# exist. The `test` lines at the end are deliberate build-time assertions:
# an earlier version of this used a trailing `|| true`, which binds to the
# whole && chain and silently masked exactly that missing-plugin failure.
RUN dnf install -y --setopt=install_weak_deps=False dnf-plugins-core createrepo_c && \
    mkdir -p /opt/local-percona && \
    dnf download --destdir=/opt/local-percona \
        percona-server-server percona-server-client && \
    createrepo_c /opt/local-percona && \
    printf '[local-percona]\nname=Percona packages (staged locally)\nbaseurl=file:///opt/local-percona\nenabled=1\ngpgcheck=0\npriority=1\n' \
        > /etc/yum.repos.d/local-percona.repo && \
    echo 'metadata_expire=-1' >> /etc/dnf/dnf.conf && \
    dnf makecache && \
    test -s /opt/local-percona/repodata/repomd.xml && \
    ls /opt/local-percona/percona-server-server-*.rpm >/dev/null && \
    ls /opt/local-percona/percona-server-client-*.rpm >/dev/null

COPY setup.sh /opt/setup.sh
RUN chown root:root /opt/setup.sh && chmod 700 /opt/setup.sh

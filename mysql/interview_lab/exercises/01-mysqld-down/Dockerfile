FROM mysqlinterview/exercise-base
COPY setup.sh /opt/setup.sh
COPY webapp.sh /usr/local/sbin/webapp
COPY webapp.service /etc/systemd/system/webapp.service
RUN chown root:root /opt/setup.sh /usr/local/sbin/webapp \
                    /etc/systemd/system/webapp.service && \
    chmod 700 /opt/setup.sh && \
    chmod 700 /usr/local/sbin/webapp && \
    chmod 644 /etc/systemd/system/webapp.service

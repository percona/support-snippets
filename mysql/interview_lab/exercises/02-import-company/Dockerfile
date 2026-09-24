FROM mysqlinterview/exercise-base
COPY setup.sh /opt/setup.sh
COPY employees-db.tar.gz /opt/employees-db.tar.gz
RUN chown root:root /opt/setup.sh /opt/employees-db.tar.gz && \
    chmod 700 /opt/setup.sh && \
    chmod 644 /opt/employees-db.tar.gz

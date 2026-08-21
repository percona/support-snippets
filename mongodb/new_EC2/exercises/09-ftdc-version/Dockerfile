FROM interview/exercise-base
COPY setup.sh /opt/setup.sh
COPY check.sh /usr/local/bin/check.sh
COPY customer-metrics.bson /opt/customer-metrics.bson
RUN chown root:root /opt/setup.sh /usr/local/bin/check.sh /opt/customer-metrics.bson && \
    chmod 700 /opt/setup.sh /usr/local/bin/check.sh && \
    chmod 644 /opt/customer-metrics.bson

FROM interview/exercise-base
COPY setup.sh /opt/setup.sh
COPY check.sh /usr/local/bin/check.sh
COPY company.json.tar.gz /opt/company.json.tar.gz
RUN chown root:root /opt/setup.sh /usr/local/bin/check.sh /opt/company.json.tar.gz && \
    chmod 700 /opt/setup.sh /usr/local/bin/check.sh && \
    chmod 644 /opt/company.json.tar.gz

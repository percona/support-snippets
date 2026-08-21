# Per-question overlay: inherits PSMDB + ttyd + candidate user from the base image.
# Copy this directory to exercises/NN-your-name/ and customise setup.sh / check.sh / README.md.
FROM interview/exercise-base
COPY setup.sh /opt/setup.sh
COPY check.sh /usr/local/bin/check.sh
RUN chown root:root /opt/setup.sh /usr/local/bin/check.sh && \
    chmod 700 /opt/setup.sh /usr/local/bin/check.sh

# Per-question overlay: inherits PS 8.0 + ttyd + candidate user from the base.
# Copy this directory to exercises/NN-your-name/ and customise setup.sh,
# check.sh and README.md.
#
# NOTE: check.sh is intentionally NOT copied into the image. The controller
# injects it at check time and deletes it afterwards, so a candidate with
# sudo cannot read the grading logic.
FROM mysqlinterview/exercise-base
COPY setup.sh /opt/setup.sh
RUN chown root:root /opt/setup.sh && chmod 700 /opt/setup.sh

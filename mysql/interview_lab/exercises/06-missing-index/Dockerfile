FROM mysqlinterview/exercise-base
COPY setup.sh /opt/setup.sh
# The default 20-page sample makes this query's plan flip between an ordered
# ref scan and range + filesort from one ANALYZE TABLE to the next, even on
# the correct index. 256 pages holds it steady (titles is ~930 pages).
RUN chown root:root /opt/setup.sh && chmod 700 /opt/setup.sh && \
    printf '[mysqld]\ninnodb_stats_persistent_sample_pages = 256\n' > /etc/my.cnf.d/60-stats.cnf && \
    chmod 644 /etc/my.cnf.d/60-stats.cnf

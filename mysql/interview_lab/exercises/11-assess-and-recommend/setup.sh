#!/bin/bash
# Seed a server that is genuinely, checkably misconfigured, so the written
# answer can be measured against ground truth instead of judged as prose. The
# planted state is a set of undersized memory and I/O settings against the real
# dataset, a slow log turned on with a low threshold, and a workload driven
# through it that exercises those weaknesses — including a query whose shape
# cannot use an index. The specifics are deliberately kept out of this file's
# comments: the question is read by a human, and this script is treated as
# readable, so it must not double as an answer key.
set -e

systemctl stop mysqld 2>/dev/null || true

cat > /etc/my.cnf.d/60-workload.cnf <<'CNF'
[mysqld]
innodb_buffer_pool_size = 32M
max_connections         = 40
innodb_io_capacity      = 100
table_open_cache        = 64
tmp_table_size          = 4M
max_heap_table_size     = 4M
slow_query_log          = ON
slow_query_log_file     = /var/log/mysql/slow.log
long_query_time         = 0.3
CNF
chmod 644 /etc/my.cnf.d/60-workload.cnf
touch /var/log/mysql/slow.log
chown mysql:mysql /var/log/mysql/slow.log

systemctl start mysqld
for _ in $(seq 1 120); do
    mysqladmin --protocol=socket ping >/dev/null 2>&1 && break
    sleep 1
done

# Populate the slow log with a workload worth finding. Launched with
# `nohup bash -c` so the exec drops the file descriptor this setup script is
# read from; a plain backgrounded subshell would keep it open and let this
# (soon-to-be-deleted) script be recovered from /proc/<pid>/fd while it runs.
workload=$(cat <<'WORKLOAD'
for _ in 1 2 3; do
    mysql -uroot employees -e "
      SELECT * FROM employees
       WHERE birth_date BETWEEN '1959-04-01' AND '1959-04-30'
          OR last_name IN ('Collete','Emmart','Coorg');" >/dev/null 2>&1
    mysql -uroot employees -e "
      SELECT * FROM employees
       WHERE emp_no IN (SELECT emp_no FROM dept_emp WHERE dept_no='d002');" >/dev/null 2>&1
    mysql -uroot employees -e "
      SELECT d.dept_name, e.emp_no, e.first_name, e.last_name, s.salary
        FROM departments d
        JOIN dept_emp de ON d.dept_no = de.dept_no
        JOIN employees e ON de.emp_no = e.emp_no
        JOIN salaries  s ON e.emp_no  = s.emp_no
       WHERE s.to_date > NOW()
       ORDER BY s.salary DESC LIMIT 20;" >/dev/null 2>&1
done
WORKLOAD
)
nohup bash -c "$workload" >/dev/null 2>&1 &

install -m 644 -o candidate -g candidate /dev/null /home/candidate/report.md 2>/dev/null || true

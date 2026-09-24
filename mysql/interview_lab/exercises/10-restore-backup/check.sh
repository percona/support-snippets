#!/bin/bash
# Pass when the employees data is fully back — not just one table. A count on a
# single table is not enough: a candidate who restores one table (via
# transportable tablespace, say) and stops would satisfy it while five tables
# are still missing. Mirror Q2 and assert every core table's row count plus a
# couple of known values, so a partial or synthetic restore cannot pass.
# Method-agnostic: any route that brings the real data back counts, and a
# legitimate full restore satisfies all of it.
set -e

result=$(mysql -uroot -N -B 2>/dev/null <<'SQL' || true
SELECT IF(
      (SELECT COUNT(*) FROM employees.employees)  >= 290000
  AND (SELECT COUNT(*) FROM employees.titles)     >= 430000
  AND (SELECT COUNT(*) FROM employees.dept_emp)   >= 320000
  AND (SELECT COUNT(*) FROM employees.salaries)   >= 2800000
  AND (SELECT dept_name FROM employees.departments WHERE dept_no='d005') = 'Development'
  AND (SELECT last_name FROM employees.employees WHERE emp_no=10001) = 'Facello',
  'PASS', 'FAIL');
SQL
)

case "$result" in
    *PASS*) exit 0 ;;
    *)
        echo "Not solved: the employees database is not fully restored."
        echo "Need: employees, titles, dept_emp and salaries all back at their real row"
        echo "counts, with the departments and a known employee row intact — not just one table."
        exit 1
        ;;
esac

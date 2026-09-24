#!/bin/bash
# Pass when the employees database is present with its real row counts. Row
# counts alone would accept a table of synthetic rows, so a couple of known
# values (a departments row and a known employee) are asserted too; a genuine
# import of the customer's dump carries all of it.
set -e

result=$(mysql -uroot -N -B 2>/dev/null <<'SQL' || true
SELECT IF(
      (SELECT COUNT(*) FROM employees.employees) >= 290000
  AND (SELECT COUNT(*) FROM employees.titles)    >= 430000
  AND (SELECT COUNT(*) FROM employees.dept_emp)  >= 320000
  AND (SELECT dept_name FROM employees.departments WHERE dept_no='d005') = 'Development'
  AND (SELECT last_name FROM employees.employees WHERE emp_no=10001) = 'Facello',
  'PASS', 'FAIL');
SQL
)

case "$result" in
    *PASS*) exit 0 ;;
    *)
        echo "Not solved: the employees database is not loaded with the customer's data."
        exit 1
        ;;
esac

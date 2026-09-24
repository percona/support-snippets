# Question 5 — A table has stopped working

The application team reports that one part of their reporting has broken.
Every query that touches `employees.titles` fails immediately, while the
rest of the database behaves normally:

```
mysql> SELECT COUNT(*) FROM employees.titles;
ERROR 1814 (HY000): ...
```

The storage team says they recovered a file belonging to that table from a
snapshot and left it for you at:

```
/opt/recovered/titles.ibd
```

Get the table working again, with all of its rows.

> There is no dump to fall back on for this one — the recovered file is
> what you have.

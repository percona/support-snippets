# Question 9 — Write the query

A customer has asked us to pull a list out of their HR database for an
audit. They want:

> everyone whose job title includes **"Engineer"** — any kind of engineer —
> in department **d005**, whose last name is **'Trumbly'**, oldest first by
> date of birth.

Write the query that answers this and save it to:

```
/home/candidate/answer.sql
```

The file is run against the `employees` database, so unqualified table
names are fine. **Return `emp_no` as the first column** — the rest of the
output is up to you.

> The customer's wording leaves one thing open, and the schema makes it
> matter: `dept_emp` and `titles` keep history — one row per assignment,
> with `to_date = '9999-01-01'` marking the current one. The customer did
> not say whether they want the people **currently** in d005 holding an
> Engineer title, or everyone who has **ever** been in d005 and ever held
> one. Either reading is accepted, as long as you apply the same reading to
> both the department and the title. State which one you chose in a SQL
> comment at the top of the file, the way you would tell the customer.

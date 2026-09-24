# Question 1 — The application cannot connect

The application team is paging. Every connection attempt is failing:

```
ERROR 2003 (HY000): Can't connect to MySQL server on '127.0.0.1:3306'
```

Two things to do:

1. **Get the application connecting again.**

2. The same team says that just before the outage they were getting
   `Too many connections` errors, and they want to know how bad it is.
   Once the server is reachable, find **how many connections the
   application account `appuser` is holding open**, and write just that
   number (digits only) to `/home/candidate/answer.txt`.

> Give the application a few seconds to reconnect before you count. Your
> own shell sessions connect as `candidate`, so they are not part of the
> number being asked for.

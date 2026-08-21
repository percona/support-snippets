# Question 1 — mongod is down

The application team is paging — they cannot connect to MongoDB:

```
MongoNetworkError: connect ECONNREFUSED 127.0.0.1:27017
```

Two things to do:

1. **Bring mongod back up** so the application can connect again.
2. The app team also suspects they're nearing a connection limit. Once
   mongod is up, find **how many client connections are currently open**
   on this server and write just that number (digits only) to
   `/home/candidate/answer.txt`.

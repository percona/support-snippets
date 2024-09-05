# Log Analysis Aggregations

## Objective

This initiative aims to store a collection of aggregation pipelines that output useful information from raw MongoDB JSON logs, such as the number of connections opened per remote IP and the latest client drivers that created connections to the database.

## Setup

Create a standalone MongoDB instance using any tool that you prefer (mlaunch, docker, anydbver...) or the raw mongod binary and import the logs to it using mongoimport

### Log cleanup

Make sure that only the JSON entries are in the log. When the logs are taken from containers, they are usually prefixed with lines like this:
```
Aug 05 07:50:54 <hostname> mongo[5806]: {"t":{"$date":"2024-08-05T07:50:54.145+00:00"},"s":"I",  "c":"COMMAND",(...)
```

Use the sed command below to remove this prefix. Adapt the container name and the number of characters inside the bracket:
```
sed -E 's/^.*mongo\[[0-9]{4}\]: //' mongod.log > mongod.NOPREFIX.log
```

Also, sometimes we receive logs with a first line informing its time interval:
```
-- Logs begin at Mon 2024-06-03 13:25:18 UTC, end at Tue 2024-08-06 19:50:54 UTC. --
```
Use the sed below to remove it:
```
sed '1d' mongod.NOPREFIX.log > mongod.CLEAN.log
```

### Importing the data

Use mongoimport to import the data to the standalone instance. The example below imports it to the namespace `percona.log`
```
mongoimport --uri "mongodb://<user>:<pwd>@localhost:27017/percona?authSource=admin" --collection log mongod.CLEAN.log
```

After this step, the data should be available in the namespace to run the aggregations.


### mongosh config and indexes

Increase the number of items displayed per cursor iteration:
```
config.set("displayBatchSize", 100)
```

Create the indexes that you think that might be necessary for the aggregations:
```
db.getSiblingDB('percona').getCollection('log').createIndex({id:1, t:1});
db.getSiblingDB('percona').getCollection('log').createIndex({t:1, id:1});
```

## About the aggregations

Most of the aggregations listed here were created to gather specific data in specific contexts. The dates used for filtering will need to be edited or removed for most cases, and any fields and stages can be customized at will.

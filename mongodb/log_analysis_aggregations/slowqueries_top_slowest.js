db.getSiblingDB('percona').getCollection('log').aggregate([
  {
    "$match": {
      "id": 51803,
    }
  },
  {
    "$sort": {
      "attr.durationMillis": -1,
    }
  },
  {
    "$limit": 500
  },
  {
    "$group": {
      "_id": {
        "ns": "$attr.ns",
        "queryHash": "$attr.queryHash",
        "planCacheKey": "$attr.planCacheKey",
        "planSummary": "$attr.planSummary",
      },
      "count": { "$sum": 1 },
      "latest": { // to find in the logs
        "$top": { output: [ "$t" ], sortBy: { "t": -1 }}
      },
      "slowest": {
        "$top": { output: [ "$attr.durationMillis" ], sortBy: { "attr.durationMillis": -1 }}
      },
    }
  },
  {
    "$sort": {
      "slowest": -1
    }
  },
  {
    "$limit": 10
  }
])

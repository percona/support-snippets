db.getSiblingDB('percona').getCollection('log').aggregate([
  {
    "$match": {
      "id": 51800,
      "t": {
        "$gte": ISODate("2024-08-05T00:00:00Z"),
        "$lt": ISODate("2024-08-06T00:00:00Z"),
      },
    }
  },
  {
    "$group": {
      "_id": {
        "driver": "$attr.doc.driver",
        "app": "$attr.doc.application"
      },
      "count": {
        "$sum": 1
      },
      "latest": {
        "$top": { output: [ "$t" ], sortBy: { "t": -1 }}
      },
    }
  },
]);

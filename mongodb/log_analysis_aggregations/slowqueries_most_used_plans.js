db.getSiblingDB('percona').getCollection('log').aggregate([
  {
    "$match": {
      "id": 51803,
      "t": {
        "$gte": ISODate("2023-09-30T00:00:00Z"),
        "$lt": ISODate("2023-11-02T00:00:00Z"),
      }
    }
  },
  {
    "$group": {
      "_id": {
        "planSummary": "$attr.planSummary",
        "ns": "$attr.ns"
      },
      "count": { "$sum": 1 }
    }
  },
  {
    "$project": {
      "_id": 0,
      "ns": "$_id.ns",
      "planSummary": "$_id.planSummary",
      "count": 1
    }
  },
  {
    "$sort": { "count": -1 }
  },
  {
    "$limit": 10
  }
]);

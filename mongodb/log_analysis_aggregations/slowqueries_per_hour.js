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
        "day": {
          "$dateToString": {
            "format": "%Y-%m-%d",
            "date": "$t"
          }
        },
        "hour": {
          "$dateToString": {
            "format": "%H:00",
            "date": "$t"
          }
        }
      },
      "count": {
        "$sum": 1
      }
    }
  },
  {
    "$project": {
      "_id": 0,
      "date": "$_id.day",
      "hour": "$_id.hour",
      "count": 1
    }
  },
  {
    "$sort": {
      "date": 1,
      "hour": 1
    }
  }
]);

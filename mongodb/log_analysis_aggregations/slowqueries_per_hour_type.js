db.getSiblingDB('percona').getCollection('log').aggregate([
  {
    "$match": {
      "id": 51803,
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
        },
        "type": "$attr.type"
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
      "type": "$_id.type",
      "count": 1
    }
  },
  {
    "$sort": {
      "date": 1,
      "hour": 1,
      "type": 1
    }
  }
]);

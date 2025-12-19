db.getSiblingDB('percona').getCollection('log').aggregate([
  {
    "$match": {
      "id": 22943,
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
        "hour_minute": {
          "$dateToString": {
            "format": "%H:%M",
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
      "hour_minute": "$_id.hour_minute",
      "count": 1
    }
  },
  {
    "$sort": {
      "date": 1,
      "hour_minute": 1
    }
  }
]);

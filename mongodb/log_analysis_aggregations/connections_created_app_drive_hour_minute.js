db.getSiblingDB('percona').getCollection('log').aggregate([
  {
    "$match": {
      "id": 51800,
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
        },
        "app": "$attr.doc.application",
        "driver": "$attr.doc.driver"
      },
      "count": {
        "$sum": 1
      },
    }
  },
  {
    "$sort": {
      "_id.day": 1,
      "_id.hour_minute": 1,
      "_id.app": 1,
      "_id.driver": 1
    }
  }
]);

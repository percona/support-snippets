db.getSiblingDB('percona').getCollection('log').aggregate([
  {
    "$match": {
      "id": 22944,
    }
  },
  {
    $project:{
      _id: 0,
      "t": 1,
      "attr.remote": {
        $arrayElemAt: [ { $split: [ "$attr.remote", ':'] } , 0 ]
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
        },
        "ip_remote": "$attr.remote"
      },
      "count": {
        "$sum": 1
      },
    }
  },
  {
    "$project": {
      "_id": 0,
      "date": "$_id.day",
      "hour": "$_id.hour",
      "ip_remote": "$_id.ip_remote",
      "count": 1
    }
  },
  {
    "$sort": {
      "date": 1,
      "hour": 1,
      "ip_remote": 1
    }
  }
]);

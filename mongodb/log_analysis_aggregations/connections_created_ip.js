db.getSiblingDB('percona').getCollection('log').aggregate([
  {
    "$match": {
      "id": 22943,
      "t": {
        "$gte": ISODate("2024-08-05T00:00:00Z"),
        "$lt": ISODate("2024-08-06T00:00:00Z"),
      },
    }
  },
  {
    $project:{
      _id: 0,
      "attr.remote": {
        $arrayElemAt: [ { $split: [ "$attr.remote", ':'] } , 0 ]
      }
    }
  },
  {
    "$group": {
      "_id": {
        "ip_remote": "$attr.remote"
      },
      "count": {
        "$sum": 1
      },
    }
  },
  { $sort: { "count": -1 }}
]);

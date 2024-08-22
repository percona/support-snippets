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
      "id": 1,
      "attr.connectionCount": 1
    }
  },
  {
    "$group": {
      "_id": {
        "id": "$id",
      },
      "max_conns": {
        $top: { output: [ "$attr.connectionCount" ], sortBy: { "attr.connectionCount": -1 }}
      },
    }
  },
  {
    $project:{
      "_id": 0,
      "max_conns": 1
    }
  },
]);

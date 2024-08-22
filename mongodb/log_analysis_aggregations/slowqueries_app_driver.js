db.getSiblingDB('percona').getCollection('log').aggregate([
  {
    "$match": {
      "id": 51803,
      "t": {
        "$gte": ISODate("2024-08-05T00:00:00Z"),
        "$lt": ISODate("2024-08-06T00:00:00Z"),
      },
    }
  },
  {
    $project:{
      "_id":0,
      "t": 1,
      "client_data": { "$objectToArray": "$attr.command" }
    }
  },
  {"$unwind": "$client_data" },
  {"$project":{
    "t": 1,
    "app": "$client_data.v.application",
    "driver": "$client_data.v.driver",
    "is_client": { $eq: [ "$client_data.k", {"$literal": "$client"}]}
  }},
  {
    "$match": { "is_client": true,}
  },
  {
    "$group": {
      "_id": {
        "app": "$app",
        "driver": "$driver"
      },
      "count": {
        "$sum": 1
      },
      "latest": {
        "$top": { output: [ "$t" ], sortBy: { "t": -1 }}
      },
    }
  },
  { $sort: { "count": -1 }}
]);

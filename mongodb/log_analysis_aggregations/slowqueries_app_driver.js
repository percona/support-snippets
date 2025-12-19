db.getSiblingDB('percona').getCollection('log').aggregate([
  {
    "$match": {
      "id": 51803,
    }
  },
  {
    $project:{
      "_id":0,
      "t": 1,
      "client_data": { "$objectToArray": "$attr.command" },
      "is_system": { $or:[
        { $regexMatch: { input: "$attr.ns", regex: /^admin/ }},
        { $regexMatch: { input: "$attr.ns", regex: /^config/ }},
        { $regexMatch: { input: "$attr.ns", regex: /^local/ }}
      ]},
    }
  },
  {
    $match: { "is_system": false  }
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

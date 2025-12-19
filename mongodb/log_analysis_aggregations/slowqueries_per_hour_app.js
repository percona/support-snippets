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
    "is_client": { $eq: [ "$client_data.k", {"$literal": "$client"}]}
  }},
  {
    "$match": { "is_client": true,}
  },
  {
    "$group": {
      "_id": {
        "app": "$app",
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
      },
    }
  },
  {
    "$project": {
      "_id": 0,
      "app": "$_id.app",
      "date": "$_id.day",
      "hour": "$_id.hour",
      "count": 1
    }
  },
  {
    "$sort": {
      "date": 1,
      "hour": 1,
      "app": 1
    }
  }
]);

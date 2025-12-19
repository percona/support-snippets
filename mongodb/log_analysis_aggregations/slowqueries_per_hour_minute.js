db.getSiblingDB('percona').getCollection('log').aggregate([
  {
    "$match": {
      "id": 51803,
      // $or: [ { "attr.storage.data.bytesRead": { $gt: 0 }}, { "attr.storage.data.bytesWritten": { $gt: 0 }} ]
      }
  },
  {
    $project:{
      _id: 0,
      "t": 1,
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

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
      _id: 0,
      "attr.ns": 1,
      "attr.type": 1,
      "attr.planCacheKey": 1,
      "attr.planSummary": 1,
      "attr.storage.data": 1,
      "attr.durationMillis": 1,
      "is_system": { $or: [
        { $regexMatch: { input: "$attr.ns", regex: /^admin/ }},
        { $regexMatch: { input: "$attr.ns", regex: /^config/ }},
        { $regexMatch: { input: "$attr.ns", regex: /^local/ }}
      ]},
      "io_usage": { $or: [
        { $gt: [ "attr.storage.data.bytesRead", 0 ]},
        { $gt: [ "attr.storage.data.bytesWritten", 0 ]}
      ]}
    }
  },
  {
    "$match": { "is_system": false, "io_usage": true }
  },
  {
    $project:{
      "attr.ns": 1,
      "attr.type": 1,
      "attr.planCacheKey": 1,
      "attr.planSummary": 1,
      "attr.storage.data": 1,
      "attr.durationMillis": 1,
    }
  },
  {
    "$sort": {
      "attr.storage.data.bytesRead": -1,
      "attr.storage.data.bytesWritten": -1,
    }
  },
]);

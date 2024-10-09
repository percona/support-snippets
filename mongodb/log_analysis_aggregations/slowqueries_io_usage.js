db.getSiblingDB('percona').getCollection('log').aggregate([
  {
    "$match": {
      "id": 51803,
      $or: [
        { $expr: { $gt: [ "attr.storage.data.bytesRead", 0 ]}},
        { $expr: { $gt: [ "attr.storage.data.bytesWritten", 0 ]}}
      ]
    }
  },
  {
    $project:{
      _id: 0,
      "is_system": { $or: [
        { $regexMatch: { input: "$attr.ns", regex: /^admin/ }},
        { $regexMatch: { input: "$attr.ns", regex: /^config/ }},
        { $regexMatch: { input: "$attr.ns", regex: /^local/ }}
      ]}
    }
  },
  {
    "$match": { "is_system": false }
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

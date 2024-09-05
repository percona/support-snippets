db.getSiblingDB('percona').getCollection('log').aggregate([
  {
    "$match": {
      "id": 51803,
      "t": {
        "$gte": ISODate("2023-09-30T00:00:00Z"),
        "$lt": ISODate("2023-11-02T00:00:00Z"),
      },
      "attr.ns": { $exists: true }
    }
  },
  {
    $project:{
      _id: 0,
      t: 1,
      attr: 1,
      is_system: { $or:[
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
    "$group": {
      "_id": {
        "ns": "$attr.ns",
        "type": "$attr.type"
      },
      "count":  { "$sum": 1 },
      "avg_ms": { "$avg": "$attr.durationMillis" },
      "sum_ms": { "$sum": "$attr.durationMillis" },
      "top_ms": {
        "$top": { output: [ "$attr.durationMillis" ], sortBy: { "attr.durationMillis": -1 }}
      },
    }
  },
  {
    "$project": {
      "_id": 0,
      "ns": "$_id.ns",
      "type": "$_id.type",
      "count": 1,
      "avg_ms": { $trunc: [ "$avg_ms", 1 ] },
      "sum_ms": 1,
      "top_ms": 1
    }
  },
  {
    "$sort": {
      "ns": 1,
      "type": 1
    }
  },
]);

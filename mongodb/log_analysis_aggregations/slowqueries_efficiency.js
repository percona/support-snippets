db.getSiblingDB('percona').getCollection('log').aggregate([
  {
    "$match": {
      "id": 51803,
      "attr.nreturned": { $gt: 0 },
      "attr.keysExamined": { $gt: 0 },
      "attr.docsExamined": { $gt: 0 },
      "attr.durationMillis": { "$gte": 100 },
      "t": {
        "$gte": ISODate("2024-08-05T00:00:00Z"),
        "$lt": ISODate("2024-08-06T00:00:00Z"),
      }
    }
  },
  {
    $project:{
      _id: 0,
      "attr.ns": 1,
      "attr.type": 1,
      "attr.planCacheKey": 1,
      "attr.planSummary": 1,
      "attr.keysExamined": 1,
      "attr.docsExamined": 1,
      "attr.nreturned": 1,
      "attr.reslen": 1,
      "attr.durationMillis": 1,
      "efficiency_keys": { $divide: [ "$attr.nreturned", "$attr.keysExamined" ]},
      "efficiency_docs": { $divide: [ "$attr.nreturned", "$attr.docsExamined" ]},
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
    $project:{
      "attr.ns": 1,
      "attr.type": 1,
      "attr.planCacheKey": 1,
      "attr.planSummary": 1,
      "attr.keysExamined": 1,
      "attr.docsExamined": 1,
      "attr.nreturned": 1,
      "attr.reslen": 1,
      "attr.durationMillis": 1,
      "efficiency_keys": { $trunc: [ "$efficiency_keys", 5 ] },
      "efficiency_docs": { $trunc: [ "$efficiency_docs", 5 ] },
    }
  },
  {
    "$sort": {
      "efficiency_docs": 1,
      "attr.docsExamined": -1
    }
  },
]);

db.getSiblingDB('percona').getCollection('log').aggregate([
  {
    "$match": {
      "id": 51800,
    }
  },
  {
    "$group": {
      "_id": {
        "remote_ip": {$arrayElemAt: [ { $split: [ "$attr.remote", ':'] } , 0 ]},
        "driver": "$attr.doc.driver",
        "app": "$attr.doc.application"
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

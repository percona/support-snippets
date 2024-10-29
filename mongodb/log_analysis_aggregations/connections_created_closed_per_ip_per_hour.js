db.getSiblingDB('percona').getCollection('log').aggregate([
  {
    "$match": {
      "id": {$in: [ 22944, 22943 ]}
    }
  },
  {
    $project:{
      _id: 0,
      "t": 1,
      "attr.remote": {
        $arrayElemAt: [ { $split: [ "$attr.remote", ':'] } , 0 ]
      },
      "cnt_opened": { $cond: { if: { $eq: [ "$id", 22943 ] }, then: 1, else: 0 }},
      "cnt_closed": { $cond: { if: { $eq: [ "$id", 22944 ] }, then: 1, else: 0 }}
    }
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
        "hour": {
          "$dateToString": {
            "format": "%H:00",
            "date": "$t"
          }
        },
        "ip_remote": "$attr.remote"
      },
      "count_opened": {
        "$sum": "$cnt_opened"
      },
      "count_closed": {
        "$sum": "$cnt_closed"
      },
    }
  },
  { 
    "$project": {
      "_id": 0,
      "date": "$_id.day",
      "hour": "$_id.hour",
      "ip_remote": "$_id.ip_remote",
      "count_opened": 1,
      "count_closed": 1
    }
  },
  {
    "$sort": {
      "date": 1,
      "hour": 1,
      "ip_remote": 1
    }
  }
]);

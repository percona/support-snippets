db.getSiblingDB('percona').getCollection('log').aggregate([
  {
    $match: {
      "id": 22943,
    }
  },
  {
    $group: {
      "_id": {
        "id": "$id",
      },
      "ls_max_conns": {
        $top: { output: [ "$attr.connectionCount" ], sortBy: { "attr.connectionCount": -1 }}
      },
    }
  },
  {
    $project:{
      "_id": 0,
      "max_conns": { $first: "$ls_max_conns" }
    }
  },
  {
    $lookup:{
      from: "log",
      let: { lkp_max_conns: "$max_conns"},
      pipeline: [
        { $match:
          { $expr:
            { $and:
              [
                { $eq: ["$id", 22943] },
                { $eq: ["$attr.connectionCount", "$$lkp_max_conns"]}
              ]
            }
          }
        },
        { $project:{"_id": 0, "t": 1} }
      ],
      as: "max_conns_time"
    }
  }
]);

db.getSiblingDB('percona').getCollection('log').aggregate([
  {
    "$match": {
      "id": 51803,
    }
  },
  {
    $project:{
      _id: 0,
      "t": 1,
      "attr": 1,
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
        "hour": {
          "$dateToString": {
            "format": "%H:00",
            "date": "$t"
          }
        },
        "command_type": {
          $switch: {
            branches: [
              { case: { $gt: ["$attr.command.aggregate", null ]}, then: "aggregate" },
              { case: { $gt: ["$attr.command.find", null ]}, then: "find" },
              { case: { $gt: ["$attr.command.getMore", null ]}, then: "getMore" },
              { case: { $gt: ["$attr.command.update", null ]}, then: "update" },
              { case: { $gt: ["$attr.command.insert", null ]}, then: "insert" },
              { case: { $gt: ["$attr.command.delete", null ]}, then: "delete" },
              { case: { $gt: ["$attr.command.abortTransaction", null ]}, then: "abortTransaction" },
              { case: { $gt: ["$attr.command.commitTransaction", null ]}, then: "commitTransaction" },
              { case: { $gt: ["$attr.command.startTransaction", null ]}, then: "startTransaction" },
              { case: { $gt: ["$attr.command.withTransaction", null ]}, then: "withTransaction" },

            ],
            default: "Unset"
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
      "hour": "$_id.hour",
      "type": "$_id.command_type",
      "count": 1
    }
  },
  {
    "$sort": {
      "date": 1,
      "hour": 1,
      "command_type": 1
    }
  }
]);

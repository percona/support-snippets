db.getSiblingDB('percona').getCollection('log').aggregate([
  {
    $match: {
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
          default: "unspecified"
        }
      }
    }
  },
  {
    $match: { "is_system": false }
  },
  {
    $group:{
      "_id": {
        "ns": "$attr.ns",
        "command_type": "$command_type",
        "planCacheKey": "$attr.planCacheKey",
        "planSummary": "$attr.planSummary",
      },
      // event relevance
      "count": { "$sum": 1 },
      // last time it happened. Might have been too long ago
      "last_time": { "$top": { output: [ "$t" ], sortBy: { "t": -1 }}},
      // averaged metrics
      "avg_keysExamined": { "$avg": "$attr.keysExamined" },
      "avg_docsExamined": { "$avg": "$attr.docsExamined" },
      "avg_nreturned": { "$avg": "$attr.nreturned" },
      "avg_reslen": { "$avg": "$attr.reslen" },
      "avg_durationMillis": { "$avg": "$attr.durationMillis" },
      "avg_bytesRead": { "$avg": "$attr.storage.data.bytesRead" },
      "avg_bytesWritten": { "$avg": "$attr.storage.data.bytesWritten" },
      "avg_timeReadingMicros": { "$avg": "$attr.storage.data.timeReadingMicros" },
      "avg_timeWritingMicros": { "$avg": "$attr.storage.data.timeWritingMicros" },
      // summed metrics
      "sum_keysExamined": { "$sum": "$attr.keysExamined" },
      "sum_docsExamined": { "$sum": "$attr.docsExamined" },
      "sum_nreturned": { "$sum": "$attr.nreturned" },
      "sum_reslen": { "$sum": "$attr.reslen" },
      "sum_durationMillis": { "$sum": "$attr.durationMillis" },
      "sum_bytesRead": { "$sum": "$attr.storage.data.bytesRead" },
      "sum_bytesWritten": { "$sum": "$attr.storage.data.bytesWritten" },
      "sum_timeReadingMicros": { "$sum": "$attr.storage.data.timeReadingMicros" },
      "sum_timeWritingMicros": { "$sum": "$attr.storage.data.timeWritingMicros" },
      // top metrics
      "top_keysExamined": { "$top": { output: [ "$attr.keysExamined" ], sortBy: { "attr.keysExamined": -1 }}},
      "top_docsExamined": { "$top": { output: [ "$attr.docsExamined" ], sortBy: { "attr.docsExamined": -1 }}},
      "top_nreturned": { "$top": { output: [ "$attr.nreturned" ], sortBy: { "attr.nreturned": -1 }}},
      "top_reslen": { "$top": { output: [ "$attr.reslen" ], sortBy: { "attr.reslen": -1 }}},
      "top_durationMillis": { "$top": { output: [ "$attr.durationMillis" ], sortBy: { "attr.durationMillis": -1 }}},
      "top_bytesRead": { "$top": { output: [ "$attr.storage.data.bytesRead" ], sortBy: { "attr.storage.data.bytesRead": -1 }}},
      "top_bytesWritten": { "$top": { output: [ "$attr.storage.data.bytesWritten" ], sortBy: { "attr.storage.data.bytesWritten": -1 }}},
      "top_timeReadingMicros": { "$top": { output: [ "$attr.storage.data.timeReadingMicros" ], sortBy: { "attr.storage.data.timeReadingMicros": -1 }}},
      "top_timeWritingMicros": { "$top": { output: [ "$attr.storage.data.timeWritingMicros" ], sortBy: { "attr.storage.data.timeWritingMicros": -1 }}},
    }
  },
// Focus on storage usage
/*   {
    $match: {
      $or: [
        { $expr: { $gt: [ "$sum_bytesRead", 0 ]}},
        { $expr: { $gt: [ "$sum_bytesWritten", 0 ]}}
    ]}
  }, */
// Focus on query efficiency
/*   {
    $match: {
      $or: [
        { $expr: { $gt: [ "$sum_keysExamined", "$sum_nreturned" ]}},
        { $expr: { $gt: [ "$sum_docsExamined", "$sum_nreturned" ]}}
    ]}
  }, */
  {
    $project:{
      "ns": "$_id.attr.ns",
      "command_type": "$_id.command_type",
      "planCacheKey": "$_id.attr.planCacheKey",
      "planSummary": "$_id.attr.planSummary",
      "count": "$count",
      "last_time": { $arrayElemAt : [ "$last_time", 0 ]},
      "avg_keysExamined":{ $trunc: [ "$avg_keysExamined" , 2 ] },
      "avg_docsExamined": { $trunc: [ "$avg_docsExamined" , 2 ] },
      "avg_nreturned": { $trunc: [ "$avg_nreturned" , 2 ] },
      "avg_reslen": { $trunc: [ "$avg_reslen" , 2 ] },
      "avg_durationMillis": { $trunc: [ "$avg_durationMillis" , 2 ] },
      "avg_bytesRead": { $trunc: [ "$avg_bytesRead" , 2 ] },
      "avg_bytesWritten": { $trunc: [ "$avg_bytesWritten" , 2 ] },
      "avg_timeReadingMillis": { $trunc: [ { $divide: [ "$avg_timeReadingMicros", 1000 ]} , 2 ] },
      "avg_timeWritingMillis": { $trunc: [ { $divide: [ "$avg_timeWritingMicros", 1000 ]} , 2 ] },
      "sum_keysExamined": "$sum_keysExamined",
      "sum_docsExamined": "$sum_docsExamined",
      "sum_nreturned": "$sum_nreturned",
      "sum_reslen": "$sum_reslen",
      "sum_durationMillis": "$sum_durationMillis",
      "sum_bytesRead": "$sum_bytesRead",
      "sum_bytesWritten": "$sum_bytesWritten",
      "sum_timeReadingMillis": { $divide: ["$sum_timeReadingMicros", 1000 ]},
      "sum_timeWritingMillis": { $divide: ["$sum_timeWritingMicros", 1000 ]},
      "top_keysExamined": { $arrayElemAt : [ "$top_keysExamined", 0 ]},
      "top_docsExamined": { $arrayElemAt : [ "$top_docsExamined", 0 ]},
      "top_nreturned": { $arrayElemAt : [ "$top_nreturned", 0 ]},
      "top_reslen": { $arrayElemAt : [ "$top_reslen", 0 ]},
      "top_durationMillis": { $arrayElemAt : [ "$top_durationMillis", 0 ]},
      "top_bytesRead": { $arrayElemAt : [ "$top_bytesRead", 0 ]},
      "top_bytesWritten": { $arrayElemAt : [ "$top_bytesWritten", 0 ]},
      "top_timeReadingMillis": {$divide: [ { $arrayElemAt : [ "$top_timeReadingMicros", 0 ]}, 1000]},
      "top_timeWritingMillis": {$divide: [ { $arrayElemAt : [ "$top_timeWritingMicros", 0 ]}, 1000]},
    }
  },
  // Top slowest
  /*{
    $sort: {
      "top_durationMillis": -1
    }
  },*/
  {
    $sort: {
      "count": -1
    }
  },
]);

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
      },
    }
  },
  {
    $match: { "is_system": false }
  },
  {
    $addFields: {query_type: { $cond: { if: { $eq: ["$attr.type", "command"]}, then: "$command_type", else: "$attr.type"}}}
  },
  {
    $group:{
      "_id": {
        "ns": "$attr.ns",
        "command_type": "$query_type",
        "queryHash": "$attr.queryHash",
        "planCacheKey": "$attr.planCacheKey",
        "planSummary": "$attr.planSummary",
      },
      // event relevance
      "count": { "$sum": 1 },
      // last time it happened. Might have been too long ago
      "last_time": { "$top": { output: [ "$t" ], sortBy: { "t": -1 }}},
      // averaged metrics
      "avg_docsExamined": { "$avg": "$attr.docsExamined" },
      "avg_keysExamined": { "$avg": "$attr.keysExamined" },
      "avg_nreturned": { "$avg": "$attr.nreturned" },
      "avg_keysDeleted": { "$avg": "$attr.keysDeleted" },
      "avg_ndeleted": { "$avg": "$attr.ndeleted" },
      "avg_keysInserted": { "$avg": "$attr.keysInserted" },
      "avg_ninserted": { "$avg": "$attr.ninserted" },
      "avg_nModified": { "$avg": "$attr.nModified" },
      "avg_reslen": { "$avg": "$attr.reslen" },
      "avg_durationMillis": { "$avg": "$attr.durationMillis" },
      "avg_totalOplogSlotDurationMicros": { "$avg": "$attr.totalOplogSlotDurationMicros" },
      "avg_waitForWriteConcernDurationMillis": { "$avg": "$attr.waitForWriteConcernDurationMillis" },
      "avg_planningTimeMicros": { "$avg": "$attr.planningTimeMicros" },
      "avg_remoteOpWaitMillis": { "$avg": "$attr.remoteOpWaitMillis" },
      "avg_cpuNanos": { "$avg": "$attr.cpuNanos" },
      "avg_totalTimeQueuedMicros": { "$avg": "$attr.queues.execution.totalTimeQueuedMicros" },
      "avg_bytesRead": { "$avg": "$attr.storage.data.bytesRead" },
      "avg_bytesWritten": { "$avg": "$attr.storage.data.bytesWritten" },
      "avg_timeReadingMicros": { "$avg": "$attr.storage.data.timeReadingMicros" },
      "avg_timeWritingMicros": { "$avg": "$attr.storage.data.timeWritingMicros" },
      // summed metrics
      "sum_docsExamined": { "$sum": "$attr.docsExamined" },
      "sum_keysExamined": { "$sum": "$attr.keysExamined" },
      "sum_nreturned": { "$sum": "$attr.nreturned" },
      "sum_keysDeleted": { "$sum": "$attr.keysDeleted" },
      "sum_ndeleted": { "$sum": "$attr.ndeleted" },
      "sum_keysInserted": { "$sum": "$attr.keysInserted" },
      "sum_ninserted": { "$sum": "$attr.ninserted" },
      "sum_nModified": { "$sum": "$attr.nModified" },
      "sum_reslen": { "$sum": "$attr.reslen" },
      "sum_durationMillis": { "$sum": "$attr.durationMillis" },
      "sum_totalOplogSlotDurationMicros": { "$sum": "$attr.totalOplogSlotDurationMicros" },
      "sum_waitForWriteConcernDurationMillis": { "$sum": "$attr.waitForWriteConcernDurationMillis" },
      "sum_planningTimeMicros": { "$sum": "$attr.planningTimeMicros" },
      "sum_remoteOpWaitMillis": { "$sum": "$attr.remoteOpWaitMillis" },
      "sum_cpuNanos": { "$sum": "$attr.cpuNanos" },
      "sum_totalTimeQueuedMicros": { "$sum": "$attr.queues.execution.totalTimeQueuedMicros" },
      "sum_bytesRead": { "$sum": "$attr.storage.data.bytesRead" },
      "sum_bytesWritten": { "$sum": "$attr.storage.data.bytesWritten" },
      "sum_timeReadingMicros": { "$sum": "$attr.storage.data.timeReadingMicros" },
      "sum_timeWritingMicros": { "$sum": "$attr.storage.data.timeWritingMicros" },
      // top metrics
      "top_docsExamined": { "$top": { output: [ "$attr.docsExamined" ], sortBy: { "attr.docsExamined": -1 }}},
      "top_keysExamined": { "$top": { output: [ "$attr.keysExamined" ], sortBy: { "attr.keysExamined": -1 }}},
      "top_nreturned": { "$top": { output: [ "$attr.nreturned" ], sortBy: { "attr.nreturned": -1 }}},
      "top_keysDeleted": { "$top": { output: [ "$attr.keysDeleted" ], sortBy: { "attr.keysDeleted": -1 }}},
      "top_ndeleted": { "$top": { output: [ "$attr.ndeleted" ], sortBy: { "attr.ndeleted": -1 }}},
      "top_keysInserted": { "$top": { output: [ "$attr.keysInserted" ], sortBy: { "attr.keysInserted": -1 }}},
      "top_ninserted": { "$top": { output: [ "$attr.ninserted" ], sortBy: { "attr.ninserted": -1 }}},
      "top_nModified": { "$top": { output: [ "$attr.nModified" ], sortBy: { "attr.nModified": -1 }}},
      "top_reslen": { "$top": { output: [ "$attr.reslen" ], sortBy: { "attr.reslen": -1 }}},
      "top_durationMillis": { "$top": { output: [ "$attr.durationMillis" ], sortBy: { "attr.durationMillis": -1 }}},
      "top_totalOplogSlotDurationMicros": { "$top": { output: [ "$attr.totalOplogSlotDurationMicros" ], sortBy: { "attr.totalOplogSlotDurationMicros": -1 }}},
      "top_waitForWriteConcernDurationMillis": { "$top": { output: [ "$attr.waitForWriteConcernDurationMillis" ], sortBy: { "attr.waitForWriteConcernDurationMillis": -1 }}},
      "top_planningTimeMicros": { "$top": { output: [ "$attr.planningTimeMicros" ], sortBy: { "attr.planningTimeMicros": -1 }}},
      "top_remoteOpWaitMillis": { "$top": { output: [ "$attr.remoteOpWaitMillis" ], sortBy: { "attr.remoteOpWaitMillis": -1 }}},
      "top_cpuNanos": { "$top": { output: [ "$attr.cpuNanos" ], sortBy: { "attr.cpuNanos": -1 }}},
      "top_totalTimeQueuedMicros": { "$top": { output: [ "$attr.queues.execution.totalTimeQueuedMicros" ], sortBy: { "attr.queues.execution.totalTimeQueuedMicros": -1 }}},
      "top_bytesRead": { "$top": { output: [ "$attr.storage.data.bytesRead" ], sortBy: { "attr.storage.data.bytesRead": -1 }}},
      "top_bytesWritten": { "$top": { output: [ "$attr.storage.data.bytesWritten" ], sortBy: { "attr.storage.data.bytesWritten": -1 }}},
      "top_timeReadingMicros": { "$top": { output: [ "$attr.storage.data.timeReadingMicros" ], sortBy: { "attr.storage.data.timeReadingMicros": -1 }}},
      "top_timeWritingMicros": { "$top": { output: [ "$attr.storage.data.timeWritingMicros" ], sortBy: { "attr.storage.data.timeWritingMicros": -1 }}},
    }
  },
  {
    $project:{
      "count": "$count",
      "last_time": { $arrayElemAt : [ "$last_time", 0 ]},
      // averaged metrics
      "avg_docsExamined": { $trunc: [ "$avg_docsExamined" , 2 ] },
      "avg_keysExamined":{ $trunc: [ "$avg_keysExamined" , 2 ] },
      "avg_nreturned": { $trunc: [ "$avg_nreturned" , 2 ] },
      "avg_keysDeleted": { $trunc: [ "$avg_keysDeleted" , 2 ] },
      "avg_ndeleted": { $trunc: [ "$avg_ndeleted" , 2 ] },
      "avg_keysInserted": { $trunc: [ "$avg_keysInserted" , 2 ] },
      "avg_ninserted": { $trunc: [ "$avg_ninserted" , 2 ] },
      "avg_nModified": { $trunc: [ "$avg_nModified" , 2 ] },
      "avg_reslen": { $trunc: [ "$avg_reslen" , 2 ] },
      "avg_durationMillis": { $trunc: [ "$avg_durationMillis" , 2 ] },
      "avg_totalOplogSlotDurationMillis": { $trunc: [ { $divide: [ "$avg_totalOplogSlotDurationMicros", 1000 ]} , 2 ] },
      "avg_waitForWriteConcernDurationMillis": { $trunc: [ "$avg_waitForWriteConcernDurationMillis" , 2 ] },
      "avg_planningTimeMillis": { $trunc: [ { $divide: [ "$avg_planningTimeMicros", 1000 ]} , 2 ] },
      "avg_remoteOpWaitMillis": { $trunc: [ "$avg_remoteOpWaitMillis" , 2 ] },
      "avg_cpuMillis": { $trunc: [ { $divide: [ "$avg_cpuNanos", 1000000 ]} , 2 ] },
      "avg_totalTimeQueuedMillis": { $trunc: [ { $divide: [ "$avg_totalTimeQueuedMicros", 1000 ]} , 2 ] },
      "avg_bytesRead": { $trunc: [ "$avg_bytesRead" , 2 ] },
      "avg_bytesWritten": { $trunc: [ "$avg_bytesWritten" , 2 ] },
      "avg_timeReadingMillis": { $trunc: [ { $divide: [ "$avg_timeReadingMicros", 1000 ]} , 2 ] },
      "avg_timeWritingMillis": { $trunc: [ { $divide: [ "$avg_timeWritingMicros", 1000 ]} , 2 ] },
      // summed metrics
      "sum_docsExamined": "$sum_docsExamined",
      "sum_keysExamined": "$sum_keysExamined",
      "sum_nreturned": "$sum_nreturned",
      "sum_keysDeleted": "$sum_keysDeleted",
      "sum_ndeleted": "$sum_ndeleted",
      "sum_keysInserted": "$sum_keysInserted",
      "sum_ninserted": "$sum_ninserted",
      "sum_nModified": "$sum_nModified",
      "sum_reslen": "$sum_reslen",
      "sum_durationMillis": "$sum_durationMillis",
      "sum_totalOplogSlotDurationMillis": { $trunc: [ { $divide: [ "$sum_totalOplogSlotDurationMicros", 1000 ]} , 2 ] },
      "sum_waitForWriteConcernDurationMillis": "$sum_waitForWriteConcernDurationMillis",
      "sum_planningTimeMillis": { $trunc: [ { $divide: [ "$sum_planningTimeMicros", 1000 ]} , 2 ] },
      "sum_remoteOpWaitMillis": "$sum_remoteOpWaitMillis",
      "sum_cpuMillis": { $trunc: [ { $divide: [ "$sum_cpuNanos", 1000000 ]} , 2 ] },
      "sum_totalTimeQueuedMillis": { $trunc: [ { $divide: [ "$sum_totalTimeQueuedMicros", 1000 ]} , 2 ] },
      "sum_bytesRead": "$sum_bytesRead",
      "sum_bytesWritten": "$sum_bytesWritten",
      "sum_timeReadingMillis": { $divide: ["$sum_timeReadingMicros", 1000 ]},
      "sum_timeWritingMillis": { $divide: ["$sum_timeWritingMicros", 1000 ]},
      // top metrics
      "top_docsExamined": { $arrayElemAt : [ "$top_docsExamined", 0 ]},
      "top_keysExamined": { $arrayElemAt : [ "$top_keysExamined", 0 ]},
      "top_nreturned": { $arrayElemAt : [ "$top_nreturned", 0 ]},
      "top_keysDeleted": { $arrayElemAt : [ "$top_keysDeleted", 0 ]},
      "top_ndeleted": { $arrayElemAt : [ "$top_ndeleted", 0 ]},
      "top_keysInserted": { $arrayElemAt : [ "$top_keysInserted", 0 ]},
      "top_ninserted": { $arrayElemAt : [ "$top_ninserted", 0 ]},
      "top_nModified": { $arrayElemAt : [ "$top_nModified", 0 ]},
      "top_reslen": { $arrayElemAt : [ "$top_reslen", 0 ]},
      "top_durationMillis": { $arrayElemAt : [ "$top_durationMillis", 0 ]},
      "top_oplogSlotDurationMillis": { $trunc: [ {$divide: [ { $arrayElemAt : [ "$top_totalOplogSlotDurationMicros", 0 ]}, 1000]}, 2 ] },
      "top_waitForWriteConcernDurationMillis": { $arrayElemAt : [ "$top_waitForWriteConcernDurationMillis", 0 ]},
      "top_planningTimeMillis": { $trunc: [ {$divide: [ { $arrayElemAt : [ "$top_planningTimeMicros", 0 ]}, 1000]}, 2 ] },
      "top_remoteOpWaitMillis": { $arrayElemAt : [ "$top_remoteOpWaitMillis", 0 ]},
      "top_cpuMillis": { $trunc: [ {$divide: [ { $arrayElemAt : [ "$top_cpuNanos", 0 ]}, 1000000]}, 2 ] },
      "top_totalTimeQueuedMillis": { $trunc: [ {$divide: [ { $arrayElemAt : [ "$top_totalTimeQueuedMicros", 0 ]}, 1000]}, 2 ] },
      "top_bytesRead": { $arrayElemAt : [ "$top_bytesRead", 0 ]},
      "top_bytesWritten": { $arrayElemAt : [ "$top_bytesWritten", 0 ]},
      "top_timeReadingMillis": { $trunc: [ {$divide: [ { $arrayElemAt : [ "$top_timeReadingMicros", 0 ]}, 1000]}, 2 ] },
      "top_timeWritingMillis": { $trunc: [ {$divide: [ { $arrayElemAt : [ "$top_timeWritingMicros", 0 ]}, 1000]}, 2 ] },
    }
  },
  {
    $sort: {
      "count": -1
    }
  },
  {
    $limit : 100
  }
]);

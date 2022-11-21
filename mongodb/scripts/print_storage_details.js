//
// Print storage details for all collections and indexes.
// Supports sharded clusters
//
// @author alex.bevilacqua@mongodb.com
// @version 1.2
// @updated 2022-04-19
//
// History:
// 1.2 - Properly filter out views
// 1.1 - Include Document Count / Average Object Size
// 1.0 - Initial Release

// You can remove the condition excluding the admin, config and local database if you have full privileges
//
// Example of privileges
// use admin
// db.grantRolesToUser( "user", [ { role: "__system", db: "admin" } ] )
// db.grantRolesToUser( "user", [ { role: "clusterAdmin", db: "admin" } ] )
// db.grantRolesToUser( "user", [ { role: "dbAdminAnyDatabase", db: "admin" } ] )

var fmt = function (bytes) {
    // comment this out to format the results
    // return bytes;

    var sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
    if (bytes == 0) return '0 Byte';
    var i = parseInt(Math.floor(Math.log(bytes) / Math.log(1024)));
    return Math.round(bytes / Math.pow(1024, i), 2) + ' ' + sizes[i];
}

var getDetail = function (label, stats) {
    var detail = {
        name: label,
        count: stats.count,
        avgSize: stats.avgObjSize,
        size: stats.size,
        storageSize: stats.storageSize,
        reusableSpace: stats.wiredTiger["block-manager"]["file bytes available for reuse"],
        indexSpace: stats.totalIndexSize,
        indexReusable: 0,
    };

    var indexKeys = Object.keys(stats.indexDetails);
    for (var i = 0; i < indexKeys.length; i++) {
        detail.indexReusable += stats.indexDetails[indexKeys[i]]["block-manager"]["file bytes available for reuse"];
    }

    return detail;
}

var dbSizeReport = function (dbname) {
    var results = []
    db.getSiblingDB(dbname).getCollectionInfos({ type: "collection" }, { nameOnly: true }).forEach(function(c) {    
        var coll = db.getSiblingDB(dbname).getCollection(c.name);
        var s = coll.stats({
            indexDetails: true
        });
        if (s.hasOwnProperty("sharded") && s.sharded) {
            var shards = Object.keys(s.shards);
            for (var i = 0; i < shards.length; i++) {
                var shard = shards[i];
                var shardStat = s.shards[shard];
                results.push(getDetail(s.ns + " (" + shard + ")", shardStat));
            }
        } else {
            results.push(getDetail(s.ns, s));
        }
    });

    var totals = [0, 0, 0, 0, 0];
    print(["Namespace", "Total Documents", "Average Document Size", "Uncompressed", "Compressed", "Reusable from Collections", "Indexes", "Reusable from Indexes"].join(","))
    for (var i = 0; i < results.length; i++) {
        var row = results[i];
        print([row.name, row.count, row.avgSize, fmt(row.size), fmt(row.storageSize), fmt(row.reusableSpace), fmt(row.indexSpace), fmt(row.indexReusable)].join(","))
        totals[0] += row.size;
        totals[1] += row.storageSize;
        totals[2] += row.reusableSpace;
        totals[3] += row.indexSpace;
        totals[4] += row.indexReusable;
    }

    print(["Total", "", "", fmt(totals[0]), fmt(totals[1]), fmt(totals[2]), fmt(totals[3]), fmt(totals[4])].join(","));
}

db.getMongo().getDBNames().forEach(function (dbname) {

  if ( dbname != 'admin' && dbname != 'config' && dbname != 'local') {
      print("---------------------")
      print(dbname);
      print("---------------------")
      dbSizeReport(dbname);
  };
});

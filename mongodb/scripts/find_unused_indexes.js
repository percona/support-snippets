/* 
Objective: This script will print in every collection's wiredTiger output.uri file in the system.
Last change (dd/mm/yyyy): 31/10/2023.
What changed: Added the script.
Editor: Jean da Silva.
*/

var ldb = db.adminCommand({ listDatabases: 1 });

for (i = 0; i < ldb.databases.length; i++) {
    if (ldb.databases[i].name != 'admin' && ldb.databases[i].name != 'config' && ldb.databases[i].name != 'local') {
        print('DATABASE ', ldb.databases[i].name);
        print('+++++++++++++++++++++++++++++++++++++++++');
        
        var currentDb = db.getSiblingDB(ldb.databases[i].name);
        var collections = currentDb.getCollectionNames();
        var summarizedIndexes = {};
        
        for (j = 0; j < collections.length; j++) {
            if (collections[j] != 'system.profile') {
                var indexStats = currentDb.runCommand({ aggregate: collections[j], pipeline: [{ $indexStats: {} }], cursor: { batchSize: 1000 } }).cursor.firstBatch;
                
                for (k = 0; k < indexStats.length; k++) {
                    var indexName = indexStats[k].name;
                    var indexUsage = indexStats[k].accesses.ops;
                    
                    if (summarizedIndexes[indexName]) {
                        summarizedIndexes[indexName].usage += indexUsage;
                    } else {
                        summarizedIndexes[indexName] = {
                            usage: indexUsage,
                            collection: collections[j]
                        };
                    }
                }
            }
        }
        
      for (var index in summarizedIndexes) {
            if (index !== '_id_' && summarizedIndexes[index].usage == 0) {
              print(" Collection: ", summarizedIndexes[index].collection);
                print("   Index name: ", index);
                print("   Index access sum: ", summarizedIndexes[index].usage);
              print("   Drop command: db.getSiblingDB('" + ldb.databases[i].name + "')." + summarizedIndexes[index].collection + ".dropIndex('" + index + "');");
                print("\n");
            }
        }
    }
}

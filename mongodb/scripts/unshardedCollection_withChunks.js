//The following script will interact with all databases(ignoring admin and config) and their collections.stats().
//If it's true that the collection is not sharded, save the namespace into the array .
//Then, using those namespaces, it will match from config.chunk if there is any chunk for that namespace:


var info = [];

db.adminCommand({
  listDatabases: 1
}).databases.forEach(function(dbname) {
  if (dbname.name != "admin" && dbname.name != "config") {
    db.getSiblingDB(dbname.name).getCollectionNames().forEach(function(cname) {
      var stats = db.getSiblingDB(dbname.name).getCollection(cname).stats();
      if (!stats.sharded) {
        info.push(stats.ns);
      }
    });
  }
});

var configDB = db.getSiblingDB("config");
var chunksColl = configDB.chunks;

var matchingChunks = chunksColl.find({ns: {$in: info}}).toArray();

print("Unsharded collections with matching chunks in the config database: ");
printjson(matchingChunks);

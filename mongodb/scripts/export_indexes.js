// Create index command
// This function will read and extract the indexes of all databases and prepare the MongoDB command to create it

db.getMongo().getDBNames().forEach(function(dbName) {
  	if (dbName != "admin" && dbName != "local") {
  	db.getSiblingDB(dbName).getCollectionNames().forEach(function(coll) {
	  db.getSiblingDB(dbName)[coll].getIndexes().forEach(function(index) {
	    if ("_id_" !== index.name) {
	      print("db.getSiblingDB('" + dbName + "')." + coll + ".createIndex(" + tojson(index.key) + ")");
	    }
	  });
	});
  	}
});

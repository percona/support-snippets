/* 
Objective: This script will print in every collection's wiredTiger output.uri file in the system.
Last change (dd/mm/yyyy): 29/01/2024.
What changed: Added the script.
Editor: Jean da Silva.
*/

// Switch to admin database to get a list of databases
var adminDb = db.getSiblingDB("admin");

// This will list the databases and their sizes
var dbs = adminDb.runCommand({ "listDatabases": 1 }).databases;

// Iterate through each database
dbs.forEach(function(database) {
    // Empty line after every database detail
    print("");
    var currentDb = db.getSiblingDB(database.name);
    print("DB name: " + currentDb.getName());
    // List collections (excluding views)
    var collInfos = currentDb.runCommand({ "listCollections": 1, "filter": { "type": "collection" } });
    var collNames = collInfos.cursor.firstBatch.map(function(coll) { return coll.name; });
    
    // Iterate through each collection
    collNames.forEach(function(collName) {
        var cnt = currentDb.getCollection(collName).stats().wiredTiger.uri;
        print("Collection name: " + collName + ", wiredTigerFile: " + cnt);
    });
});
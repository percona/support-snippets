/**
 * MongoDB Fragmentation Analyzer Script
 *
 * This script iterates over all non-system databases and their collections,
 * calculates the fragmentation ratio based on storageSize and freeStorageSize,
 * and prints the top 10 most fragmented collections.
 *
 * Fragmentation Ratio Formula:
 *    fragmentationRatio = freeStorageSize / storageSize
 *
 * Steps:
 * 1. Retrieve all databases.
 * 2. Filter out system databases ('admin', 'config', 'local').
 * 3. Iterate over each collection in each database.
 * 4. Retrieve storage statistics using the collStats command.
 * 5. Calculate fragmentation ratio and store results.
 * 6. Sort collections by fragmentation ratio in descending order.
 * 7. Print the top 10 most fragmented collections.
 *
 * Git Commit Details:
 * Commit Message: "Add MongoDB fragmentation analysis script"
 * Extended Description:
 * - Implemented a script to analyze fragmentation across all MongoDB collections.
 * - Excludes system databases and system collections.
 * - Uses collStats to determine storage fragmentation.
 * - Sorts and displays the top 10 most fragmented collections.
 * - Adds comments and documentation for clarity and maintainability.
 */

var ldb = db.adminCommand({ listDatabases: 1 }); // Get list of databases
var fragmentationData = []; // Array to store fragmentation details

for (var i = 0; i < ldb.databases.length; i++) {
    var dbName = ldb.databases[i].name;
    
    // Skip system databases
    if (dbName !== 'admin' && dbName !== 'config' && dbName !== 'local') {
        var currentDb = db.getSiblingDB(dbName);
        var collections = currentDb.getCollectionNames();
        
        for (var j = 0; j < collections.length; j++) {
            var collName = collections[j];
            
            // Skip system profile collection
            if (collName !== 'system.profile') {
                var stats = currentDb.runCommand({ collStats: collName });
                
                if (stats.ok) {
                    var storageSize = stats.storageSize || 0; // Total allocated storage
                    var freeStorageSize = stats.freeStorageSize || 0; // Unused storage
                    
                    // Ensure storageSize is greater than 0 to prevent division by zero
                    if (storageSize > 0) {
                        var fragmentationRatio = freeStorageSize / storageSize;
                        
                        // Store relevant data for sorting and output
                        fragmentationData.push({
                            db: dbName,
                            collection: collName,
                            fragmentationRatio: fragmentationRatio,
                            storageSize: storageSize,
                            freeStorageSize: freeStorageSize
                        });
                    }
                }
            }
        }
    }
}

// Sort collections by highest fragmentation ratio and take the top 10
fragmentationData.sort(function(a, b) {
    return b.fragmentationRatio - a.fragmentationRatio;
});

// Print the top 10 fragmented collections
print("Top 10 most fragmented collections:");
print("===================================");
for (var k = 0; k < Math.min(10, fragmentationData.length); k++) {
    var entry = fragmentationData[k];
    print("Database: " + entry.db);
    print("Collection: " + entry.collection);
    print("Fragmentation Ratio: " + (entry.fragmentationRatio * 100).toFixed(2) + "%");
    print("Storage Size: " + entry.storageSize + " bytes");
    print("Free Storage Size: " + entry.freeStorageSize + " bytes");
    print("-----------------------------------");
}

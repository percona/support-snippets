// The command below will copy one collection to a new one. Edit the match condition as needed

db.<source-collection>.aggregate([ { $match: {} }, { $out: "temp_collection" } ])

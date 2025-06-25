/* 
Objective: This script will calculate the Cardinality for large collections from a sample.
Last change (dd/mm/yyyy): 25/06/2025.
What changed: Renamed the output from "counts" to "samples" for better understanding.
Editor: Jean da Silva.
*/


db.getSiblingDB('<database-name>').getCollection('<collection-name>').aggregate([
  { $sample: { size: 10000 } },
  {
    $facet: {
      dist_count: [
        { $group: { _id: "<field-name>" } }
      ],
      samples: [ // renamed from "count"
        { $count: "samples" } // renamed count field to "samples"
      ]
    }
  },
  {
    $addFields: {
      dist_count: { $size: "$dist_count" },
      samples: { $first: "$samples.samples" } // adjusted field reference
    }
  }
]);

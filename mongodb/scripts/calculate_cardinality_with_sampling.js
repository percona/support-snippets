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

/* 
Objective: // adding multiple fields for finding cardinality for multiple fields when one intended to create compsite index
Last change (dd/mm/yyyy): 27/06/2025.
Editor: Vinodh Guruji.
*/

db.getSiblingDB('<database-name>').getCollection('<collection-name>').aggregate([
  { $sample: { size: 10000 } },
  {
    $facet: {
      dist_count: [
        { $group: { _id: {field1: "<field-name>", field2: "<field-name>", ..  } } }
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

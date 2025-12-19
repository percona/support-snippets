db.getSiblingDB('percona').getCollection('log').aggregate([
{
  $sort: { t: 1}
},
{
  $limit: 1
},
{
  "$project": {
    "_id": 0,
    "t": 1
  }
}
]);
db.getSiblingDB('percona').getCollection('log').aggregate([
{
  $sort: { t: -1}
},
{
  $limit: 1
},
{
  "$project": {
    "_id": 0,
    "t": 1
  }
}
]);

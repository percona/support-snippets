-- Get dataset size per storage engine in MySQL

SET @current_innodb_stats_on_metadata = @@global.innodb_stats_on_metadata;
SET @@global.innodb_stats_on_metadata = 0;
SELECT engine,
  COUNT(*) tables,
  CONCAT(ROUND(SUM(table_rows)/1000000,2),'M') rows,
  CONCAT(ROUND(SUM(data_length)/(1024*1024*1024),2),'G') data,
  CONCAT(ROUND(SUM(index_length)/(1024*1024*1024),2),'G') idx,
  CONCAT(ROUND(SUM(data_length+index_length)/(1024*1024*1024),2),'G') total_size,
  ROUND(SUM(index_length)/SUM(data_length),2) idxfrac
  FROM information_schema.TABLES
  GROUP BY engine
  ORDER BY SUM(data_length+index_length) DESC LIMIT 10;
SET @@global.innodb_stats_on_metadata = @current_innodb_stats_on_metadata;

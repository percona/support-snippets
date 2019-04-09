Very simple MongoDB log parser that extracts information about network connections and saves them in two files.

Example:
```
./network_connections_log_parser.py mongod.log

Completed processing of log file mongod.log:
- Number of recorded connections: 47723
- Number of precessed seconds: 27707

- Generated JSON file: mongod.log.json

- Generated CSV file: mongod.log.csv
```

The .json file includes a dictionary-structure containing specific information for each processed connection. It can be imported into Python for punctual analysis.

Example:
```
import json, ast
file = open('mongod.log-20190318.json')
data = json.load(file)
ast.literal_eval(json.dumps(data['496503']))
```
```
{'auth_as': 'principal eadba',
 'auth_at': '2019-03-17 03:27:33',
 'auth_on': 'admin',
 'closed_at': '2019-03-17 03:27:33',
 'open_at': '2019-03-17 03:27:33',
 'source_ip': '127.0.0.1',
 'source_port': '60568'}
```

The .csv file organizes information regarding the number of open connections as well as opened and closed connection "per second":
```
timestamp;open connections;opened;closed
2019-03-25 10:14:25;994;1;1
2019-03-25 10:14:30;995;2;1
2019-03-25 10:14:32;990;2;7
(...)
```
It could be used imported into a spreadsheet to generate a graph like the following:
![Network connections graph example](https://github.com/percona/support-snippets/blob/master/mongodb/network_log_parser/sample.png)

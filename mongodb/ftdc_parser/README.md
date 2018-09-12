
## FTDC Parser

- This tool parses diagnostic.data from MongoDB.

Dependency
- Python:
matplotlib
argparse
ast
json

- Repo:
https://github.com/10gen/ftdc-utils

### How to use:

Install ftdc utils using:
`go get github.com/10gen/ftdc-utils/cmd/ftdc`
and move the ftdc binary to /usr/bin

From a running mongodb (3.2+) use ftdc tool to export as a JSON;



    cd /mongodb/data/
    ftdc decode metrics.interim -o ftdc.json

> Writing output to ftdc.json
chunk in file 'metrics.interim' with 940 metrics and 280 deltas on Wed Sep 12 10:21:47 -03 2018
found 281 samples


Use the ftdc_parser.py to evaluate the metrics:

`python ftdc_parser.py -i ftdc.json`

> Loading file...
Total of timestamps : 1
0 Start Time: 2018-09-12 13:26:47 # of deltas: 80

0 is the timestamp, for bigger files each slice will have 5 mintutes.

`python ftdc_parser.py -i ftdc.json -generate True -d 0`

where --generate means show the metrics -d means the time slice, 0 in that case. 

If want to filter by a specific  value use -f 'text' as follows:

`python ftdc_parser.py -i ftdc.json --generate True -d 0 -f 'inserted'`

> Loading file...
Total of timestamps : 1
serverStatus.metrics.document.inserted;25;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;


### Generating graphs
graph.py receive as stdin the output of the ftdc_parser.py

Use the same parameters as earlier but add the -t True flag to show the timestamps:
`python ftdc_parser.py -i ftdc.json --generate True -d 0 -f 'inserted' -t True | python graph.py`

> Generating ['serverStatus.metrics.document.inserted']

Process will generate a graph for each line:
serverStatus.metrics.document.inserted.png

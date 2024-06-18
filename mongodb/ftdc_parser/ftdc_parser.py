import ast
import json
import argparse
import datetime
from datetime import timedelta

parser = argparse.ArgumentParser()

parser.add_argument("--input", "-i", type=str, required=True)
parser.add_argument("--generate", "-p", type=bool, required=False, default=False)
parser.add_argument("--date", "-d", type=int, required=False)
parser.add_argument("--timestamp", "-t", type=bool, required=False, default=False)
parser.add_argument("--filter","-f", type=str, default='')

args = parser.parse_args()

if args.input == '':
   print('Error to read file');
try:
  print('Loading file...')
  f = open(args.input,'r')
  data = json.load(f)
except:
  print('Wrong file type - use export')
  exit()

print('Total of timestamps : ' + str(len(data)))

if not args.generate:
  count = 0
  for samples in data:
    all_metrics = samples['Metrics']
    #print 'Number of Deltas: ' + str( samples['NDeltas'])
    for metric in all_metrics:
      if not args.generate:
        if metric['Key'] == 'start':
          mytime = datetime.datetime.utcfromtimestamp((int(metric['Value'])/1000))
          print(str(count) + ' Start Time: ' +  mytime.strftime('%Y-%m-%d %H:%M:%S') + ' # of deltas: ' + str( samples['NDeltas']))
          count = count + 1;
else:
  headertimestamps = ''
  all_metrics = data[args.date]
  for metric in all_metrics['Metrics']:
    total = ''
    for deltas in metric['Deltas']:
      total += str(deltas) + ';'
    if args.timestamp:
      if metric['Key'] == 'start':
          headertimestamps = ''
          mytime = datetime.datetime.utcfromtimestamp((int(metric['Value'])/1000))
          for deltas in metric['Deltas']:
            mytime = mytime + timedelta(milliseconds=int(deltas))
            headertimestamps  +=  mytime.strftime('%Y-%m-%d %H:%M:%S') + ';'
          print('Timestamps;' + headertimestamps)
      #for deltas in metric['Deltas']:
      #  total += str(deltas) + ';'
    if not args.filter == '':
      if args.filter in metric['Key']:
        print(metric['Key'] + ';' + str(metric['Value']) + ';' +  str(total))
    else:
      print(metric['Key'] + ';' + str(metric['Value']) + ';' +  str(total))

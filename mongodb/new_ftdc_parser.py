import json
import argparse
import datetime
from datetime import timedelta

# Parse command-line arguments
parser = argparse.ArgumentParser()
parser.add_argument("--input", "-i", type=str, required=True, help="Input JSON file")
parser.add_argument("--generate", "-p", action="store_true", help="Generate metrics")
parser.add_argument("--start-date", "-s", type=str, help="Start date (YYYY-MM-DD HH:MM:SS)")
parser.add_argument("--end-date", "-e", type=str, help="End date (YYYY-MM-DD HH:MM:SS)")
parser.add_argument("--timestamp", "-t", action="store_true", help="Include timestamps")
parser.add_argument("--filter", "-f", type=str, default='', help="Filter metrics by key")
args = parser.parse_args()

# Load JSON data from file
try:
    with open(args.input, 'r') as f:
        data = json.load(f)
    print('Total of timestamps:', len(data))
except Exception as e:
    print(f"Error loading file: {e}")
    exit(1)

# Parse date arguments
start_date = datetime.datetime.strptime(args.start_date, '%Y-%m-%d %H:%M:%S') if args.start_date else None
end_date = datetime.datetime.strptime(args.end_date, '%Y-%m-%d %H:%M:%S') if args.end_date else None

# Function to print timestamp details
def print_timestamps(samples, count):
    for metric in samples['Metrics']:
        if metric['Key'] == 'start':
            mytime = datetime.datetime.utcfromtimestamp(int(metric['Value']) / 1000)
            if (not start_date or mytime >= start_date) and (not end_date or mytime <= end_date):
                print(f"{count} Start Time: {mytime.strftime('%Y-%m-%d %H:%M:%S')} # of deltas: {samples['NDeltas']}")

# Function to generate metrics
def generate_metrics(samples):
    for metric in samples['Metrics']:
        if args.timestamp and metric['Key'] == 'start':
            mytime = datetime.datetime.utcfromtimestamp(int(metric['Value']) / 1000)
            timestamps = []
            for delta in metric['Deltas']:
                mytime += timedelta(milliseconds=int(delta))
                if (not start_date or mytime >= start_date) and (not end_date or mytime <= end_date):
                    timestamps.append(mytime.strftime('%Y-%m-%d %H:%M:%S'))
            if timestamps:
                print('Timestamps;' + ';'.join(timestamps))
        if args.filter in metric['Key']:
            deltas_str = ';'.join(str(delta) for delta in metric['Deltas'])
            print(f"{metric['Key']};{metric['Value']};{deltas_str}")
        elif not args.filter:
            deltas_str = ';'.join(str(delta) for delta in metric['Deltas'])
            print(f"{metric['Key']};{metric['Value']};{deltas_str}")

# Process data
if not args.generate:
    count = 0
    for samples in data:
        print_timestamps(samples, count)
        count += 1
else:
    for samples in data:
        if start_date or end_date:
            for metric in samples['Metrics']:
                if metric['Key'] == 'start':
                    mytime = datetime.datetime.utcfromtimestamp(int(metric['Value']) / 1000)
                    if (not start_date or mytime >= start_date) and (not end_date or mytime <= end_date):
                        generate_metrics(samples)
                        break
        else:
            generate_metrics(samples)

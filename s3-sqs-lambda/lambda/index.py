import json


def handler(event, context):
    for record in event.get("Records", []):
        body = json.loads(record["body"])
        for s3_record in body.get("Records", []):
            bucket = s3_record["s3"]["bucket"]["name"]
            key = s3_record["s3"]["object"]["key"]
            print(f"New object uploaded -> Bucket: {bucket}, File: {key}")

    return {"statusCode": 200}

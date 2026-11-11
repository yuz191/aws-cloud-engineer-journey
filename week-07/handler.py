"""PropertyLite's single-listing read path for API Gateway HTTP API."""

import json
import os
from decimal import Decimal


def _table():
    # boto3 is included in the Lambda Python runtime. Import on invocation so
    # local handler tests do not need AWS credentials or the SDK installed.
    import boto3

    return boto3.resource("dynamodb").Table(os.environ.get("TABLE_NAME", "Properties"))


def _csv_shape(value):
    """Match the string-valued fields returned by PropertyLite's CSV reader."""
    if isinstance(value, Decimal):
        return str(value)
    if isinstance(value, dict):
        return {key: _csv_shape(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_csv_shape(item) for item in value]
    return value


def _response(status, body):
    return {
        "statusCode": status,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body),
    }


def lambda_handler(event, context):
    params = event.get("pathParameters") or {}
    listing_id = params.get("id")
    if not isinstance(listing_id, str) or not listing_id:
        return _response(400, {"error": "missing property id"})

    result = _table().get_item(Key={"L_ListingID": listing_id})
    item = result.get("Item")
    if item is None:
        return _response(404, {"error": "not found"})
    return _response(200, _csv_shape(item))

import json
import unittest
from decimal import Decimal
from unittest.mock import patch

import handler


class FakeTable:
    def __init__(self, item=None):
        self.item = item
        self.key = None

    def get_item(self, *, Key):
        self.key = Key
        return {"Item": self.item} if self.item is not None else {}


class HandlerTests(unittest.TestCase):
    def test_found_listing_matches_csv_response_shape(self):
        table = FakeTable({"L_ListingID": "R100234", "L_SystemPrice": Decimal("450000")})
        with patch.object(handler, "_table", return_value=table):
            response = handler.lambda_handler({"pathParameters": {"id": "R100234"}}, None)
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(table.key, {"L_ListingID": "R100234"})
        self.assertEqual(json.loads(response["body"]), {"L_ListingID": "R100234", "L_SystemPrice": "450000"})

    def test_unknown_listing_returns_propertylite_404(self):
        with patch.object(handler, "_table", return_value=FakeTable()):
            response = handler.lambda_handler({"pathParameters": {"id": "missing"}}, None)
        self.assertEqual(response["statusCode"], 404)
        self.assertEqual(json.loads(response["body"]), {"error": "not found"})

    def test_missing_route_parameter_does_not_read_dynamodb(self):
        with patch.object(handler, "_table") as get_table:
            response = handler.lambda_handler({"pathParameters": None}, None)
        self.assertEqual(response["statusCode"], 400)
        get_table.assert_not_called()


if __name__ == "__main__":
    unittest.main()

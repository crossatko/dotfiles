"""Tests for bin/weather (WMO code mapping, location parsing, caching, offline fallback), all against mock files.

python3 -I -m unittest discover -s config/quickshell/bin/tests
"""
import importlib.machinery
import importlib.util
import json
import os
import tempfile
import unittest

BIN = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "weather")

HOURS = ["2030-01-01T%02d:00" % h for h in range(0, 24)]
FORECAST = {
    "current": {"time": "2030-01-01T20:15", "temperature_2m": 21.4, "apparent_temperature": 20.1, "relative_humidity_2m": 55,
                "is_day": 0, "weather_code": 61, "wind_speed_10m": 16.0},
    "hourly": {"time": HOURS, "temperature_2m": [10.0 + h for h in range(24)], "weather_code": [61] * 24,
               "is_day": [1 if 7 <= h < 17 else 0 for h in range(24)], "precipitation_probability": [30] * 24},
    "daily": {"time": ["2030-01-01", "2030-01-02", "2030-01-03"], "weather_code": [61, 0, 3],
              "temperature_2m_max": [22.0, 25.0, 20.0], "temperature_2m_min": [12.0, 13.5, 10.0],
              "precipitation_probability_max": [80, None, 10]},
}
HOUR = 3600.0
DAY = 86400.0


def load_module(cache, mock):
    os.environ["QS_WEATHER_CACHE"] = cache
    os.environ["QS_WEATHER_MOCK"] = mock
    loader = importlib.machinery.SourceFileLoader("weather_under_test", BIN)
    spec = importlib.util.spec_from_loader(loader.name, loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


class Weather(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.cache = os.path.join(self.tmp.name, "cache")
        self.mock = os.path.join(self.tmp.name, "mock")
        os.makedirs(self.mock)
        self.put("forecast", {"status": 200, "body": FORECAST})
        self.put("ip", {"status": 200, "body": {"success": True, "latitude": 1.5, "longitude": 2.5, "city": "Exampleville"}})
        self.put("geocode", {"status": 200, "body": {"results": [{"latitude": 3.5, "longitude": 4.5, "name": "Sampletown"}]}})
        self.w = load_module(self.cache, self.mock)

    def tearDown(self):
        self.tmp.cleanup()

    def put(self, name, data):
        with open(os.path.join(self.mock, name + ".json"), "w") as f:
            json.dump(data, f)

    def drop(self, name):
        os.remove(os.path.join(self.mock, name + ".json"))

    def test_codes(self):
        d = self.w.describe
        self.assertEqual(d(0)[0], "clear")
        self.assertEqual(d(2)[0], "partly")
        self.assertEqual(d(3)[0], "cloudy")
        self.assertEqual(d(45)[0], "fog")
        self.assertEqual(d(53)[0], "drizzle")
        self.assertEqual(d(65)[0], "rain")
        self.assertEqual(d(81)[0], "showers")
        self.assertEqual(d(75)[0], "snow")
        self.assertEqual(d(99)[0], "storm")
        self.assertEqual(d(1234)[0], "unknown")
        self.assertEqual(d(None)[0], "unknown")

    def test_every_documented_code_is_mapped(self):
        for c in (0, 1, 2, 3, 45, 48, 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 71, 73, 75, 77, 80, 81, 82, 85, 86, 95, 96, 99):
            self.assertNotEqual(self.w.describe(c)[0], "unknown", c)

    def test_coords(self):
        self.assertEqual(self.w.parse_coords("10.5, -20.25"), (10.5, -20.25))
        self.assertEqual(self.w.parse_coords("10 20"), (10.0, 20.0))
        self.assertIsNone(self.w.parse_coords("Sampletown"))
        self.assertIsNone(self.w.parse_coords("95, 10"))
        self.assertIsNone(self.w.parse_coords(""))

    def test_auto_location_and_shape(self):
        r = self.w.run("", "metric", True, 600, now=1000)
        self.assertTrue(r["ok"])
        self.assertEqual(r["location"], {"name": "Exampleville", "source": "ip"})
        self.assertEqual(r["unitsLabel"], {"temp": "°C", "wind": "km/h"})
        self.assertEqual(r["current"]["kind"], "rain")
        self.assertFalse(r["current"]["isDay"])
        self.assertEqual(len(r["daily"]), 3)
        self.assertEqual([d["rel"] for d in r["daily"]], [0, 1, None])
        self.assertIsNone(r["daily"][1]["pop"])
        # from the current hour (20:00) to the end of what the answer has
        self.assertEqual([h["time"] for h in r["hourly"]], ["20:00", "21:00", "22:00", "23:00"])
        self.assertEqual(r["hourly"][0]["time"], "20:00")
        self.assertEqual(r["hourly"][0]["temp"], 30.0)
        self.assertFalse(r["hourly"][0]["isDay"])
        self.assertEqual(r["hourly"][0]["pop"], 30)
        for gone in ("code", "sunrise", "sunset", "windDir", "precip"):
            self.assertNotIn(gone, json.dumps(r))
        self.assertNotIn("lat", json.dumps(r))

    def test_ip_cached_when_service_gone(self):
        self.w.run("", "metric", True, 600, now=1000)
        self.drop("ip")
        r = self.w.run("", "metric", True, 600, now=2000)
        self.assertTrue(r["ok"])
        self.assertEqual(r["location"]["name"], "Exampleville")

    def test_search_and_coords(self):
        self.assertEqual(self.w.run("Sampletown", "metric", True, 600, now=1)["location"], {"name": "Sampletown", "source": "search"})
        r = self.w.run("1.234, 5.678", "imperial", True, 600, now=1)
        self.assertEqual(r["location"], {"name": "Custom location", "source": "coords"})
        self.assertNotIn("1.23", json.dumps(r))
        self.assertNotIn("5.68", json.dumps(r))
        self.assertEqual(r["unitsLabel"]["temp"], "°F")

    def test_place_not_found(self):
        self.put("geocode", {"status": 200, "body": {}})
        r = self.w.run("Nowhere", "metric", True, 600, now=1)
        self.assertFalse(r["ok"])
        self.assertEqual(r["error"], "Place not found")

    def test_fresh_answer_is_reused_and_stale_fallback(self):
        self.w.run("", "metric", True, 600, now=1000)
        self.drop("forecast")
        self.assertFalse(self.w.run("", "metric", False, 600, now=1100)["stale"])   # fresh: no request at all
        r = self.w.run("", "metric", False, 600, now=1000 + 2 * HOUR)                # old + offline: last answer, marked
        self.assertTrue(r["ok"])
        self.assertTrue(r["stale"])
        self.assertEqual(r["error"], "Weather service unreachable")
        self.assertEqual(r["generatedAt"], 1000)                                     # the panel can say how old it is

    def test_stale_is_capped(self):
        self.w.run("", "metric", True, 600, now=1000)
        self.drop("forecast")
        self.assertTrue(self.w.run("", "metric", False, 600, now=1000 + DAY - 10)["stale"])
        r = self.w.run("", "metric", False, 600, now=1000 + DAY + 10)
        self.assertEqual((r["ok"], r["error"]), (False, "Weather service unreachable"))

    def test_stale_drops_the_past_and_does_not_call_yesterday_today(self):
        self.w.run("", "metric", True, 600, now=1000)
        self.drop("forecast")
        r = self.w.run("", "metric", False, 600, now=1000 + 5 * HOUR)               # 01:15 on the next day
        self.assertEqual([(d["date"], d["rel"]) for d in r["daily"]], [("2030-01-02", 0), ("2030-01-03", 1)])
        self.assertEqual(r["hourly"], [])                                            # the answer has no hours past midnight

    def test_units_change_works_offline(self):
        self.w.run("", "metric", True, 600, now=1000)
        self.drop("forecast")
        r = self.w.run("", "imperial", False, 600, now=1000 + 2 * HOUR)
        self.assertTrue(r["ok"] and r["stale"])
        self.assertEqual(r["unitsLabel"], {"temp": "°F", "wind": "mph"})
        self.assertAlmostEqual(r["current"]["temp"], 70.5, places=1)
        self.assertAlmostEqual(r["current"]["wind"], 9.9, places=1)
        self.assertAlmostEqual(r["daily"][0]["max"], 71.6, places=1)

    def test_cache_is_per_location(self):
        self.w.run("Sampletown", "metric", True, 600, now=1000)
        self.drop("forecast")
        self.assertFalse(self.w.run("", "metric", False, 600, now=1100)["ok"])

    def test_invalid_geocode_json_is_a_fetch_error(self):
        with open(os.path.join(self.mock, "geocode.json"), "w") as f:
            f.write("{not json")
        r = self.w.run("Nowhere", "metric", True, 600, now=1)
        self.assertEqual((r["ok"], r["error"]), (False, "Location unavailable"))

    def test_network_errors_never_crash(self):
        for body in ('{"current": 5}', "[]", "null"):
            with open(os.path.join(self.mock, "forecast.json"), "w") as f:
                f.write('{"status": 200, "body": %s}' % body)
            r = self.w.run("", "metric", True, 600, now=1)
            self.assertFalse(r["ok"], body)
            self.assertEqual(r["error"], "Weather service unreachable")

    def test_incomplete_read_is_an_oserror(self):
        import http.client
        class R:
            def __enter__(self): return self
            def __exit__(self, *a): return False
            def read(self, *a): raise http.client.IncompleteRead(b"x")
        self.w.MOCK = ""
        orig = self.w.urllib.request.urlopen
        self.addCleanup(setattr, self.w.urllib.request, "urlopen", orig)
        self.w.urllib.request.urlopen = lambda req, timeout=0: R()
        with self.assertRaises(OSError):
            self.w.get_json("forecast", "https://example.invalid/")
        r = self.w.run("1,2", "metric", True, 600, now=1)
        self.assertEqual((r["ok"], r["error"]), (False, "Weather service unreachable"))

    def test_ip_fallback_service(self):
        self.drop("ip")
        self.put("ip2", {"status": 200, "body": {"latitude": 1.5, "longitude": 2.5, "city": ""}})
        r = self.w.run("", "metric", True, 600, now=1)
        self.assertEqual(r["location"]["name"], "Current location")

    def test_ip_third_service(self):
        self.drop("ip")
        self.put("ip3", {"status": 200, "body": {"loc": "1.5,2.5", "city": ""}})
        r = self.w.run("", "metric", True, 600, now=1)
        self.assertEqual(r["location"]["name"], "Current location")

    def test_nothing_cached_and_offline(self):
        self.drop("forecast")
        self.drop("ip")
        r = self.w.run("", "metric", True, 600, now=1)
        self.assertEqual((r["ok"], r["error"]), (False, "Location unavailable"))


NOW = 1900000000.0           # 2030-03-17T17:46:40Z
KP_ROWS = [{"time_tag": "2030-03-17T09:00:00", "Kp": 2.0, "a_running": 7, "station_count": 8},
           {"time_tag": "2030-03-17T15:00:00", "Kp": 6.33, "a_running": 80, "station_count": 8}]


class Aurora(unittest.TestCase):
    """--kp: NOAA planetary Kp (mocked) and the latitude -> required Kp rule. Fixture coordinates are made up."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.mock = os.path.join(self.tmp.name, "mock")
        os.makedirs(self.mock)
        self.w = load_module(os.path.join(self.tmp.name, "cache"), self.mock)

    def tearDown(self):
        self.tmp.cleanup()

    def put(self, name, data):
        with open(os.path.join(self.mock, name + ".json"), "w") as f:
            json.dump(data, f)

    def test_required_kp_by_latitude(self):
        # the dipole pole sits at 80.7 N, 72.7 W: a point on its meridian is easy to reason about
        self.assertAlmostEqual(self.w.geomag_lat(80.7, -72.7), 90.0, places=3)
        self.assertEqual(self.w.kp_needed(62.0, -72.7), 0)                  # geomagnetic 71.3
        self.assertEqual(self.w.kp_needed(50.0, -72.7), 4)                  # 59.3
        self.assertEqual(self.w.kp_needed(40.0, -72.7), 8)                  # 49.3: only a strong storm
        self.assertIsNone(self.w.kp_needed(30.0, -72.7))                    # 39.3: never
        self.assertIsNone(self.w.kp_needed(0.0, 0.0))                       # equator: never
        self.assertEqual(self.w.kp_needed(-62.0, 107.3), 0)                 # southern oval is symmetric

    def test_table_order(self):
        kps = [kp for _, kp in self.w.REQUIRED_KP]
        floors = [f for f, _ in self.w.REQUIRED_KP]
        self.assertEqual(kps, sorted(kps))
        self.assertEqual(floors, sorted(floors, reverse=True))

    def test_parse_kp(self):
        self.assertEqual(self.w.parse_kp(KP_ROWS, NOW), 6.33)
        self.assertIsNone(self.w.parse_kp(KP_ROWS, NOW + 7 * HOUR))          # too old
        self.assertIsNone(self.w.parse_kp({"x": 1}, NOW))
        self.assertIsNone(self.w.parse_kp([{"time_tag": "bad", "Kp": 3}], NOW))
        self.assertIsNone(self.w.parse_kp([{"time_tag": "2030-03-17T15:00:00", "Kp": 12}], NOW))

    def test_aurora_block(self):
        self.put("kp", {"status": 200, "body": KP_ROWS})
        self.put("ip", {"status": 200, "body": {"success": True, "latitude": 62.0, "longitude": -72.7, "city": "Exampleville"}})
        a = self.w.aurora("", NOW)
        self.assertEqual(a, {"kp": 6.33, "likely": True})                    # ~ 70 N geomagnetic needs Kp 0
        self.put("ip", {"status": 200, "body": {"success": True, "latitude": 10.0, "longitude": 20.0, "city": "Exampleville"}})
        os.remove(os.path.join(self.tmp.name, "cache", "location.json"))
        os.remove(os.path.join(self.tmp.name, "cache", "kp.json"))
        self.assertEqual(self.w.aurora("", NOW), {"kp": 6.33, "likely": False})     # low latitude: never

    def test_kp_cache_and_failure(self):
        self.put("kp", {"status": 200, "body": KP_ROWS})
        self.assertEqual(self.w.current_kp(NOW), 6.33)
        os.remove(os.path.join(self.mock, "kp.json"))
        self.assertEqual(self.w.current_kp(NOW + 600), 6.33)                 # inside 30 min: cached, no request
        self.assertEqual(self.w.current_kp(NOW + 2 * HOUR), 6.33)            # NOAA down: the cached value up to 6 h
        self.assertIsNone(self.w.current_kp(NOW + 7 * HOUR))                 # then nothing

    def test_no_kp_without_flag_and_no_coordinates_printed(self):
        os.environ["QS_WEATHER_CACHE"] = os.path.join(self.tmp.name, "cache")
        self.put("kp", {"status": 200, "body": KP_ROWS})
        self.put("forecast", {"status": 200, "body": FORECAST})
        self.put("ip", {"status": 200, "body": {"success": True, "latitude": 61.2345, "longitude": 9.8765, "city": "Exampleville"}})
        plain = self.w.run("", "metric", True, 600, now=NOW)
        self.assertNotIn("aurora", plain)
        with_kp = self.w.run("", "metric", True, 600, now=NOW, kp=True)
        self.assertEqual(set(with_kp["aurora"]), {"kp", "likely"})
        dump = json.dumps(with_kp)
        self.assertNotIn("61.23", dump)
        self.assertNotIn("9.87", dump)
        self.assertEqual(with_kp["current"]["tempC"], 21.4)

    def test_temp_c_stays_celsius_in_imperial(self):
        self.put("forecast", {"status": 200, "body": FORECAST})
        self.put("ip", {"status": 200, "body": {"success": True, "latitude": 1.5, "longitude": 2.5, "city": "Exampleville"}})
        r = self.w.run("", "imperial", True, 600, now=NOW)
        self.assertEqual(r["current"]["tempC"], 21.4)
        self.assertEqual(r["current"]["temp"], 70.5)


if __name__ == "__main__":
    unittest.main()

import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lib"))
from diacritics import flow, htmlmode  # noqa: E402

CHROMIUM_PLAIN = ("<meta charset='utf-8'><span style=\"color: rgb(0, 0, 0); font-family: sans-serif; "
                  "-webkit-text-stroke-width: 0px;\">zlutoucky kun</span>")
CHROMIUM_RICH = ("<meta charset='utf-8'><p style=\"color: rgb(0, 0, 0); -webkit-text-stroke-width: 0px;\">a <b>zlutoucky</b> "
                 "<a href=\"https://example.com/?x=1&amp;y=2\">odkaz</a></p>")
FIREFOX_RICH = "<html><body><!--StartFragment--><ul><li>prvni</li><li>druha</li></ul><!--EndFragment--></body></html>"
# plain text that only looks like HTML source: stays plain mode, the prompt keeps the tags
SOURCE_TEXT = '<p>zlutoucky kun <a href="https://example.com/a?x=1&amp;y=2">odkaz</a> <strong>tucne</strong></p>'


class Markup(unittest.TestCase):
    def test_lone_wrapper_is_plain(self):
        self.assertFalse(htmlmode.has_real_markup(CHROMIUM_PLAIN))
        self.assertFalse(htmlmode.has_real_markup("zlutoucky kun"))
        self.assertFalse(htmlmode.has_real_markup("<meta charset='utf-8'>"))

    def test_real_markup(self):
        self.assertTrue(htmlmode.has_real_markup(CHROMIUM_RICH))
        self.assertTrue(htmlmode.has_real_markup(FIREFOX_RICH))
        self.assertTrue(htmlmode.has_real_markup("<b>x</b>"))
        self.assertTrue(htmlmode.has_real_markup("<span>a</span><span>b</span>"))

    def test_strip_wrapper(self):
        self.assertEqual(htmlmode.strip_wrapper(FIREFOX_RICH), "<ul><li>prvni</li><li>druha</li></ul>")
        self.assertEqual(htmlmode.strip_wrapper(CHROMIUM_RICH),
                         "<p>a <b>zlutoucky</b> <a href=\"https://example.com/?x=1&amp;y=2\">odkaz</a></p>")

    def test_real_inline_style_stays(self):
        self.assertEqual(htmlmode.strip_wrapper("<b style=\"color: red\">x</b>"), "<b style=\"color: red\">x</b>")

    def test_wrap(self):
        self.assertEqual(htmlmode.wrap("<b>x</b>"), "<meta charset='utf-8'><b>x</b>")

    def test_to_plain(self):
        self.assertEqual(htmlmode.to_plain("<p>a <b>b</b><br>c</p><ul><li>x</li><li>y &amp; z</li></ul>"),
                         "a b\nc\n- x\n- y & z")


class FlowMode(unittest.TestCase):
    def copied(self, types, html):
        with mock.patch.object(flow.clipboard, "list_types", return_value=types), \
             mock.patch.object(flow.clipboard, "read", return_value=html.encode()):
            return flow._copied_html()

    def test_html_mode(self):
        self.assertEqual(self.copied(["text/plain", "text/html"], FIREFOX_RICH), "<ul><li>prvni</li><li>druha</li></ul>")

    def test_no_html_type_is_plain_mode(self):
        self.assertIsNone(self.copied(["text/plain;charset=utf-8", "text/plain"], SOURCE_TEXT))

    def test_html_source_text_stays_plain_mode(self):
        # a textarea copy offers text/plain only; even if text/html carried the escaped source it has no real tags
        self.assertIsNone(self.copied(["text/html"], "&lt;p&gt;zlutoucky&lt;/p&gt;"))

    def test_lone_wrapper_is_plain_mode(self):
        self.assertIsNone(self.copied(["text/plain", "text/html"], CHROMIUM_PLAIN))


if __name__ == "__main__":
    unittest.main()

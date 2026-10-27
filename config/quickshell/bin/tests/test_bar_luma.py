import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOL = Path(__file__).resolve().parent.parent / "bar-luma"


@unittest.skipUnless(shutil.which("magick"), "ImageMagick missing")
class BarLuma(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)

    def img(self, name, *args):
        p = self.tmp / name
        subprocess.run(["magick", *args, str(p)], check=True)
        return p

    def run_tool(self, *args):
        r = subprocess.run([sys.executable, "-I", str(TOOL), *map(str, args)], capture_output=True, text=True)
        return r.returncode, (json.loads(r.stdout)["cols"] if r.stdout else None)

    def test_flat_bright_and_dark(self):
        rc, c = self.run_tool(self.img("b.png", "-size", "800x600", "xc:white"), 1920, 1080, 58, "top")
        self.assertEqual(rc, 0)
        self.assertEqual(len(c), 64)
        self.assertGreater(min(x[0] for x in c), 0.95)
        rc, c = self.run_tool(self.img("d.png", "-size", "800x600", "xc:black"), 1920, 1080, 58, "bottom")
        self.assertLess(max(x[2] for x in c), 0.01)

    def test_split_columns_follow_the_picture(self):
        p = self.img("s.png", "-size", "1920x1080", "xc:black", "-fill", "white", "-draw", "rectangle 0,0 959,1079")
        _, c = self.run_tool(p, 1920, 1080, 58, "top")
        self.assertGreater(c[5][0], 0.9)
        self.assertLess(c[58][0], 0.05)

    def test_edge_and_cover_crop(self):
        # white top 100 px of a 1920x1080 picture: top strip bright, bottom strip dark
        p = self.img("e.png", "-size", "1920x1080", "xc:black", "-fill", "white", "-draw", "rectangle 0,0 1919,99")
        self.assertGreater(self.run_tool(p, 1920, 1080, 58, "top")[1][10][0], 0.9)
        self.assertLess(self.run_tool(p, 1920, 1080, 58, "bottom")[1][10][0], 0.05)
        # a 4:3 picture on a 16:9 screen is cropped top and bottom (cover): its top 25 % row is not on screen
        q = self.img("c.png", "-size", "800x600", "xc:black", "-fill", "white", "-draw", "rectangle 0,0 799,20")
        self.assertLess(self.run_tool(q, 1920, 1080, 58, "top")[1][10][0], 0.05)

    def test_bad_input(self):
        self.assertEqual(self.run_tool(self.tmp / "missing.png", 1920, 1080, 58, "top")[0], 1)
        self.assertEqual(self.run_tool("x", 1920, 1080, 58, "left")[0], 2)


if __name__ == "__main__":
    unittest.main()

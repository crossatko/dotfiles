"""The model choice per mode (en, cs, translate): the file formats, the refusals, and reloads only when the pair changes."""
import argparse
import importlib.machinery
import importlib.util
import json
import os
import stat
import tempfile
import unittest

from helpers import Scripted

from dictation import whisper
from test_lifecycle import Base
from test_service import Client

BIN = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "bin", "dictation")


def load_cli():
    loader = importlib.machinery.SourceFileLoader("dictation_cli", BIN)
    spec = importlib.util.spec_from_loader("dictation_cli", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


TURBO, FULL, FUTO = "large-v3-turbo", "large-v3", "futo-small-en"


class Files(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = os.path.join(self.tmp.name, "models")
        os.makedirs(self.dir)
        self.file = os.path.join(self.tmp.name, "stt-models.json")

    def tearDown(self):
        self.tmp.cleanup()

    def install(self, *names):
        for n in names:
            open(os.path.join(self.dir, f"ggml-{n}.bin"), "w").close()

    def write(self, obj):
        with open(self.file, "w") as f:
            f.write(obj if isinstance(obj, str) else json.dumps(obj))

    def chosen(self, mode, **kw):
        return whisper.chosen_models(self.file, mode=mode, directory=self.dir, **kw)

    def test_mode_keys(self):
        for mode, key in (("en", "en"), ("cs", "cs"), ("de", "cs"), ("auto", "cs"), ("translate", "translate"),
                          ("translate:cs", "translate"), ("translate:auto", "translate")):
            self.assertEqual(whisper.model_mode(mode), key, mode)

    def test_defaults_english_fast_is_futo_only_when_installed(self):
        self.assertEqual(self.chosen("en"), {"live": TURBO, "final": TURBO})
        self.install(FUTO)
        self.assertEqual(self.chosen("en"), {"live": FUTO, "final": TURBO})
        self.assertEqual(self.chosen("cs"), {"live": TURBO, "final": FULL})
        self.assertEqual(self.chosen("translate"), {"live": TURBO, "final": FULL})

    def test_a_version_1_file_applies_to_every_mode(self):
        self.install(FUTO)
        self.write({"version": 1, "live": "small", "final": "large-v3-q5_0"})
        for mode in whisper.MODES:
            self.assertEqual(self.chosen(mode), {"live": "small", "final": "large-v3-q5_0"}, mode)

    def test_a_version_2_file_is_per_mode_and_partial_entries_fall_back(self):
        self.install(FUTO)
        self.write({"version": 2, "en": {"live": "small", "final": FULL}, "cs": {"final": "large-v3-q5_0"}})
        self.assertEqual(self.chosen("en"), {"live": "small", "final": FULL})
        self.assertEqual(self.chosen("cs"), {"live": TURBO, "final": "large-v3-q5_0"})
        self.assertEqual(self.chosen("translate"), {"live": TURBO, "final": FULL})

    def test_bad_entries_leave_the_default(self):
        self.write({"version": 2, "en": {"live": "../x", "final": 7}, "cs": "oops", "translate": None})
        self.assertEqual(self.chosen("en"), {"live": TURBO, "final": TURBO})
        self.assertEqual(self.chosen("cs"), {"live": TURBO, "final": FULL})
        self.write("not json")
        self.assertEqual(self.chosen("translate"), {"live": TURBO, "final": FULL})

    def test_explicit_arguments_win(self):
        self.write({"version": 2, "en": {"live": "small", "final": FULL}})
        self.assertEqual(self.chosen("en", live="medium"), {"live": "medium", "final": FULL})

    def test_a_missing_chosen_model_is_an_error_naming_the_file(self):
        self.install(TURBO)
        names = {"live": FUTO, "final": TURBO}
        with self.assertRaises(whisper.ModelMissing) as cm:
            whisper.model_paths(names, self.dir, mode="en")
        self.assertIn("ggml-futo-small-en.bin", str(cm.exception))
        self.assertEqual(cm.exception.code, "no-model")

    def test_the_english_model_serves_english_only(self):
        self.install(FUTO, FULL, TURBO)
        names = {"live": FUTO, "final": FULL}
        self.assertEqual(whisper.model_paths(names, self.dir, mode="en")["live"], os.path.join(self.dir, f"ggml-{FUTO}.bin"))
        for mode in ("cs", "translate"):
            with self.assertRaises(whisper.ModelUnsuitable) as cm:
                whisper.model_paths(names, self.dir, mode=mode)
            self.assertEqual(cm.exception.code, "no-model")
            self.assertIn("English only", str(cm.exception))
        with self.assertRaises(whisper.ModelUnsuitable):  # as the full model too
            whisper.model_paths({"live": TURBO, "final": FUTO}, self.dir, mode="cs")

    def test_translation_needs_a_full_model_that_can_translate(self):
        self.install(TURBO, FULL)
        whisper.model_paths({"live": TURBO, "final": FULL}, self.dir, mode="translate")
        with self.assertRaises(whisper.ModelUnsuitable) as cm:
            whisper.model_paths({"live": FULL, "final": TURBO}, self.dir, mode="translate")
        self.assertIn("cannot translate", str(cm.exception))
        whisper.model_paths({"live": FULL, "final": TURBO}, self.dir, mode="cs")  # fine when not translating


class Reloads(Base):
    """The service reloads at a begin only when the pair for the session's mode differs from the loaded one."""

    PAIRS = {"en": ("futo", "full"), "cs": ("turbo", "full"), "translate": ("turbo", "full")}

    def run_modes(self, *modes, pairs=None):
        pairs = pairs or self.PAIRS
        made = []

        def make(mode):
            made.append(whisper.model_mode(mode))
            return Scripted(["a b", "a b c"], final="a b c.")

        self.start(make, models_key=lambda mode: pairs[whisper.model_mode(mode)])
        self.svc.per_mode = True
        c = Client(self.path)
        c.until(lambda e: e.get("event") == "status" and e["state"] == "idle")
        for mode in modes:
            c.send(f"begin {mode}")
            c.until(lambda e: e.get("event") == "state" and e["state"] == "listening")
            c.send("cancel")
            c.until(lambda e: e.get("event") == "state" and e["state"] == "idle")
        c.close()
        return made

    def test_a_new_pair_reloads_the_same_pair_does_not(self):
        # en -> en: loaded once; en -> cs: another fast model; cs -> translate: the same pair; translate -> de: the same
        self.assertEqual(self.run_modes("en", "en", "cs", "translate", "de"), ["en", "cs"])

    def test_going_back_reloads_again(self):
        self.assertEqual(self.run_modes("en", "cs", "en"), ["en", "cs", "en"])

    def test_one_pair_for_every_mode_never_reloads(self):
        same = {m: ("turbo", "full") for m in whisper.MODES}
        self.assertEqual(self.run_modes("en", "cs", "translate", pairs=same), ["en"])


class RealKey(Base):
    """bin/dictation's own key function and recognizer factory, the real Service, chosen_models and model_paths: a pair
    that is loaded for one mode must never be reused for a mode it cannot serve."""

    ENV = ("DICTATION_MODEL_DIR", "DICTATION_MODELS_FILE", "DICTATION_PREFS_FILE", "DICTATION_WORKER")

    def setUp(self):
        self.saved = {k: os.environ.get(k) for k in self.ENV}
        self.work = tempfile.TemporaryDirectory()
        self.models = os.path.join(self.work.name, "models")
        os.makedirs(self.models)
        for n in (TURBO, FULL, FUTO):
            open(os.path.join(self.models, f"ggml-{n}.bin"), "w").close()
        worker = os.path.join(self.work.name, "worker")
        with open(worker, "w") as fh:
            fh.write("#!/bin/bash\necho '{\"ready\":true}'\nexec cat >/dev/null\n")
        os.chmod(worker, stat.S_IRWXU)
        self.models_file = os.path.join(self.work.name, "stt-models.json")
        os.environ.update(DICTATION_MODEL_DIR=self.models, DICTATION_MODELS_FILE=self.models_file,
                          DICTATION_PREFS_FILE=os.path.join(self.work.name, "prefs.json"), DICTATION_WORKER=worker)
        self.cli = load_cli()

    def tearDown(self):
        super().tearDown()
        for k, v in self.saved.items():
            os.environ.pop(k, None)
            if v is not None:
                os.environ[k] = v
        self.work.cleanup()

    def begins(self, args, *modes):
        """For each mode: the first state-or-error event after `begin`."""
        self.start(lambda mode: self.cli.recognizer(args, mode), models_key=lambda mode: self.cli.models_key(args, mode))
        self.svc.per_mode = True
        c = Client(self.path)
        c.until(lambda e: e.get("event") == "status" and e["state"] == "idle")
        out = []
        for mode in modes:
            c.send(f"begin {mode}")
            ev = c.until(lambda e: (e.get("event") == "state" and e["state"] == "listening") or e.get("event") == "error")[-1]
            out.append(ev)
            if ev.get("event") != "error":
                c.send("cancel")
                c.until(lambda e: e.get("event") == "state" and e["state"] == "idle")
        c.close()
        return out

    def args(self, **kw):
        return argparse.Namespace(**dict(dict(live=None, final=None, no_gpu=True, final_beam=5, verbose=False), **kw))

    def test_an_english_only_pair_is_refused_for_cs_and_translate_after_en_loaded_it(self):
        for modes, why in ((("en", "cs"), "English only"), (("en", "translate"), "English only")):
            with self.subTest(modes=modes):
                ev = self.begins(self.args(live=FUTO), *modes)
                self.assertEqual(ev[0].get("event"), "state")
                self.assertEqual((ev[1].get("event"), ev[1].get("code")), ("error", "no-model"))
                self.assertIn(why, ev[1]["message"])
                self.tearDown_service()

    def test_the_same_from_a_version_1_file(self):
        with open(self.models_file, "w") as fh:
            json.dump({"version": 1, "live": FUTO, "final": FULL}, fh)
        ev = self.begins(self.args(), "en", "cs")
        self.assertEqual(ev[0].get("event"), "state")
        self.assertEqual((ev[1].get("event"), ev[1].get("code")), ("error", "no-model"))

    def test_a_full_model_that_cannot_translate_is_refused_for_translate_after_en_loaded_it(self):
        ev = self.begins(self.args(final=TURBO), "en", "translate")
        self.assertEqual(ev[0].get("event"), "state")
        self.assertEqual((ev[1].get("event"), ev[1].get("code")), ("error", "no-model"))
        self.assertIn("cannot translate", ev[1]["message"])

    def test_a_good_pair_still_loads_once_for_every_mode(self):
        made = []
        real = self.cli.recognizer
        self.cli.recognizer = lambda a, m: made.append(m) or real(a, m)
        ev = self.begins(self.args(live=TURBO, final=FULL), "en", "cs", "translate")
        self.assertEqual([e.get("event") for e in ev], ["state"] * 3)
        self.assertEqual(made, ["en"])

    def tearDown_service(self):
        self.svc.shutdown()
        self.thread.join(10)


if __name__ == "__main__":
    unittest.main()

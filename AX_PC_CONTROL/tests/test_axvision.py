#!/usr/bin/env python3
"""Tests for AX Vision, the fast eye for PC1.

These run on the Linux sandbox with no screen, because every interesting part of
the package is pure: geometry, frame differencing, colour finding and the state
classifier all take arrays and numbers. Only ``capture`` and the daemon loop need
Windows, and they are kept thin so there is little in them to get wrong.

The test that matters most is ``test_menu_is_not_called_black``: the client menu
is a dark scrim and a black screen is a dead renderer, and telling them apart is
the whole reason the classifier exists. If those two ever swap, the agent goes
looking for a rendering bug when it should press ESC.

Run: python3 AX_PC_CONTROL/tests/test_axvision.py
Exit code is non-zero when anything fails, so CI fails loudly.
"""

from __future__ import annotations

import json
import os
import sys
import unittest

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from axvision import capture, engine, geometry, signature, state  # noqa: E402


def solid(w: int, h: int, colour: tuple[int, int, int]) -> np.ndarray:
    frame = np.zeros((h, w, 3), dtype=np.uint8)
    frame[:, :] = colour
    return frame


def noisy_world(w: int = 320, h: int = 180, seed: int = 1) -> np.ndarray:
    """A frame that looks like a rendered 3D scene: many colours, little black."""
    rng = np.random.default_rng(seed)
    frame = rng.integers(60, 220, size=(h, w, 3), dtype=np.uint8)
    return frame


class GeometryTests(unittest.TestCase):
    def test_clamp_keeps_a_window_that_hangs_off_the_screen(self):
        # A window dragged left so a third of it is off screen.
        clamped = geometry.clamp((-100, 50, 400, 300), (0, 0, 1600, 900))
        self.assertEqual(clamped, (0, 50, 300, 300))
        self.assertTrue(geometry.contains((0, 0, 1600, 900), clamped))

    def test_clamp_of_a_fully_offscreen_rect_is_empty(self):
        clamped = geometry.clamp((2000, 100, 100, 100), (0, 0, 1600, 900))
        self.assertTrue(geometry.is_empty(clamped))

    def test_intersection_of_disjoint_rects_is_empty(self):
        self.assertTrue(geometry.is_empty(geometry.intersect((0, 0, 10, 10), (50, 50, 10, 10))))

    def test_iou_is_one_for_identical_and_zero_for_disjoint(self):
        r = (10, 10, 100, 100)
        self.assertAlmostEqual(geometry.iou(r, r), 1.0)
        self.assertEqual(geometry.iou(r, (500, 500, 100, 100)), 0.0)

    def test_iou_of_a_half_shifted_box_is_between(self):
        a = (0, 0, 100, 100)
        b = (50, 0, 100, 100)
        self.assertAlmostEqual(geometry.iou(a, b), 5000 / 15000, places=4)

    def test_tiles_cover_the_rectangle_with_no_gaps(self):
        rect = (5, 7, 101, 53)  # deliberately not divisible by 4 or 3
        tiles = geometry.tile(rect, 4, 3)
        self.assertEqual(len(tiles), 12)
        covered = sum(geometry.area(t) for t in tiles)
        self.assertEqual(covered, geometry.area(rect))
        # Every tile is inside the rectangle.
        for t in tiles:
            self.assertTrue(geometry.contains(rect, t), t)

    def test_union_of_empty_is_the_other(self):
        self.assertEqual(geometry.union((0, 0, 0, 0), (1, 2, 3, 4)), (1, 2, 3, 4))


class SignatureTests(unittest.TestCase):
    def test_identical_frames_do_not_count_as_changed(self):
        a = noisy_world()
        self.assertEqual(signature.change_ratio(a, a.copy()), 0.0)
        self.assertFalse(signature.has_changed(a, a.copy()))

    def test_small_jitter_below_the_threshold_is_not_a_change(self):
        # A still scene with a light flickering by a couple of levels. The old
        # exact comparison would call this motion and make every "did it move"
        # answer useless.
        a = noisy_world()
        b = a.copy()
        b[0:20, 0:20] = np.clip(b[0:20, 0:20].astype(int) + 3, 0, 255).astype(np.uint8)
        self.assertFalse(signature.has_changed(a, b))

    def test_a_moved_avatar_is_a_change(self):
        # The avatar is a small bright block on a static background, which is
        # exactly the case a tile-average signature misses and a diff catches.
        a = noisy_world(320, 180)
        b = a.copy()
        b[80:120, 100:140] = (255, 255, 255)
        self.assertTrue(signature.has_changed(a, b))
        boxes = signature.changed_boxes(a, b)
        self.assertTrue(boxes, "a moved avatar must produce at least one changed tile")

    def test_change_boxes_point_at_the_region_that_moved(self):
        a = solid(320, 180, (30, 30, 30))
        b = a.copy()
        b[0:45, 0:80] = (250, 250, 250)  # top-left corner
        boxes = signature.changed_boxes(a, b, cols=8, rows=6)
        self.assertTrue(boxes)
        # Every reported box is in the top-left quadrant.
        for x, y, w, h in boxes:
            self.assertLess(x + w, 160 + 1)
            self.assertLess(y + h, 90 + 1)

    def test_shape_mismatch_is_an_error_not_a_wrong_answer(self):
        with self.assertRaises(ValueError):
            signature.change_ratio(solid(10, 10, (0, 0, 0)), solid(20, 10, (0, 0, 0)))

    def test_colour_share_finds_a_hud_gold_badge(self):
        frame = solid(200, 100, (10, 10, 10))
        frame[10:30, 10:50] = (255, 206, 84)  # 40x20 of 200x100 = 4%
        share = signature.colour_share(frame, (255, 206, 84), tolerance=10)
        self.assertAlmostEqual(share, (40 * 20) / (200 * 100), places=4)

    def test_colour_boxes_locate_the_badge(self):
        frame = solid(320, 180, (10, 10, 10))
        frame[140:170, 280:310] = (255, 206, 84)  # bottom-right
        boxes = signature.colour_boxes(frame, (255, 206, 84), tolerance=10)
        self.assertTrue(boxes)
        for x, y, w, h in boxes:
            self.assertGreaterEqual(x, 160)
            self.assertGreaterEqual(y, 90)

    def test_brightness_is_weighted_by_the_eye_not_flat(self):
        # Pure blue looks much darker than pure green at the same level. A flat
        # mean would call them equal.
        blue = signature.brightness(solid(10, 10, (0, 0, 255)))
        green = signature.brightness(solid(10, 10, (0, 255, 0)))
        self.assertGreater(green, blue * 3)

    def test_dark_share_of_black_is_one(self):
        self.assertAlmostEqual(signature.dark_share(solid(10, 10, (0, 0, 0))), 1.0)

    def test_distinct_colours_separates_a_world_from_a_panel(self):
        world = noisy_world()
        panel = solid(320, 180, (18, 20, 28))
        self.assertGreater(signature.distinct_colours(world), signature.distinct_colours(panel) * 10)

    def test_signature_has_one_number_per_tile(self):
        sig = signature.signature(noisy_world(), cols=8, rows=6)
        self.assertEqual(len(sig), 48)


class StateTests(unittest.TestCase):
    def test_world_is_recognised(self):
        st = state.classify_frame(noisy_world())
        self.assertEqual(st.label, "world", st.as_dict())

    def test_black_screen_is_recognised(self):
        st = state.classify_frame(solid(320, 180, (0, 0, 0)))
        self.assertEqual(st.label, "black", st.as_dict())

    def test_menu_is_not_called_black(self):
        # The client menu is a dark scrim over a dimmed game: mostly dark, but
        # not the total blackness of a dead renderer. On PC1 it measured 94%
        # dark, so the fixture is built to that figure rather than a guess.
        frame = solid(320, 180, (2, 3, 5))
        # A band of menu chrome and a bright label, together about 6% of pixels.
        frame[0:8, :] = (40, 44, 60)
        frame[40:46, 40:120] = (200, 200, 210)
        st = state.classify_frame(frame)
        self.assertEqual(st.label, "menu", st.as_dict())
        self.assertTrue(any("ESC" in h for h in st.hints), st.hints)

    def test_black_is_chosen_over_menu_when_nothing_draws(self):
        # Ordering matters: a truly black screen must not be called the menu, or
        # the agent presses ESC forever on a dead renderer.
        st = state.classify_frame(solid(320, 180, (0, 0, 0)))
        self.assertEqual(st.label, "black")

    def test_flat_panel_is_recognised(self):
        st = state.classify_frame(solid(320, 180, (18, 20, 28)))
        self.assertEqual(st.label, "panel", st.as_dict())

    def test_the_same_scene_is_classified_the_same_at_any_size(self):
        # This is the bug the first classifier shipped with: thresholds in pixel
        # counts, calibrated on a 1600x900 screen, called a 320x180 capture of
        # the same scene "unknown". A phone-sized capture and a desktop capture
        # of one scene must agree.
        for size in ((320, 180), (640, 360), (1280, 720)):
            w, h = size
            world = noisy_world(w, h)
            self.assertEqual(state.classify_frame(world).label, "world", f"world at {size}")
            self.assertEqual(state.classify_frame(solid(w, h, (0, 0, 0))).label, "black", f"black at {size}")
            self.assertEqual(state.classify_frame(solid(w, h, (18, 20, 28))).label, "panel", f"panel at {size}")

    def test_every_state_carries_a_reason_and_hints(self):
        for frame in (noisy_world(), solid(320, 180, (0, 0, 0)), solid(320, 180, (18, 20, 28))):
            st = state.classify_frame(frame)
            self.assertTrue(st.reason)
            self.assertTrue(st.hints)

    def test_stats_report_the_frame_size(self):
        st = state.classify_frame(noisy_world(640, 360))
        self.assertEqual((st.stats.width, st.stats.height), (640, 360))


class GameWindowTests(unittest.TestCase):
    """The game window is chosen by the process that owns it, not its title.

    On PC1 a browser tab sat on a Roblox page, and the engine picked that
    browser because its title contains "Roblox". It then read a web page and
    called it the game. The title is not the identity; the owning process is.
    """

    def test_picks_the_player_over_a_browser_with_roblox_in_its_title(self):
        # The browser was maximized and the player window was not, so area
        # alone would pick the browser: the process has to decide.
        windows = [
            (101, "RobloxPlayerBeta.exe", "Roblox", 1600 * 829),
            (102, "msedge.exe", "Roblox | OpenHands - Personal - Microsoft Edge", 1920 * 1080),
            (103, "explorer.exe", "Program Manager", 1920 * 1080),
        ]
        self.assertEqual(capture.pick_game_window(windows), 101)

    def test_ignores_studio_without_needing_a_title_guess(self):
        windows = [
            (201, "RobloxStudioBeta.exe", "Roblox Studio - My Place", 1600 * 829),
            (202, "RobloxPlayerBeta.exe", "AX Arena: Farm and Fight", 1600 * 829),
        ]
        self.assertEqual(capture.pick_game_window(windows), 202)

    def test_falls_back_to_studio_when_the_player_is_not_running(self):
        # The published place is unrated, and Roblox hides unrated experiences
        # from the client, so Play mode in Studio is the only way to render it.
        windows = [
            (203, "RobloxStudioBeta.exe", "Roblox Studio - AXArena", 1600 * 829),
            (204, "msedge.exe", "Roblox | OpenHands - Personal - Microsoft Edge", 1600 * 829),
        ]
        self.assertEqual(capture.pick_game_window(windows), 203)

    def test_picks_the_largest_window_of_a_process(self):
        # Studio owns several visible top-level windows; the first one
        # enumerated on PC1 was a 350x1 strip, which captures nothing.
        windows = [
            (205, "RobloxStudioBeta.exe", "RobloxStudio", 350 * 1),
            (206, "RobloxStudioBeta.exe", "AXArena.rbxlx - Roblox Studio", 1600 * 829),
            (207, "RobloxStudioBeta.exe", "Tooltip", 200 * 20),
        ]
        self.assertEqual(capture.pick_game_window(windows), 206)

    def test_the_player_still_wins_over_a_larger_studio_window(self):
        windows = [
            (208, "RobloxStudioBeta.exe", "Roblox Studio", 1920 * 1080),
            (209, "RobloxPlayerBeta.exe", "Roblox", 800 * 600),
        ]
        self.assertEqual(capture.pick_game_window(windows), 209)

    def test_returns_zero_when_only_other_windows_mention_roblox(self):
        windows = [
            (301, "chrome.exe", "Roblox - Google Chrome", 1600 * 829),
            (302, "notepad.exe", "notes about Roblox", 1600 * 829),
        ]
        self.assertEqual(capture.pick_game_window(windows), 0)

    def test_the_process_name_match_is_case_insensitive(self):
        windows = [(401, "ROBLOXPLAYERBETA.EXE", "Roblox", 1600 * 829)]
        self.assertEqual(capture.pick_game_window(windows), 401)


class EngineTests(unittest.TestCase):
    """The engine with a synthetic grabber, so the loop is tested without Windows."""

    def _engine(self, frames, **kwargs):
        it = iter(frames)

        def grab(_rect):
            try:
                return next(it)
            except StopIteration:
                return frames[-1]

        return engine.Engine(grab, (0, 0, 320, 180), interval=0.001, classify_every=1, **kwargs)

    def test_capture_once_stores_a_frame(self):
        eng = self._engine([noisy_world()])
        frame = eng.capture_once()
        self.assertIsNotNone(frame)
        self.assertEqual(eng.latest().index, 0)

    def test_history_is_bounded(self):
        eng = self._engine([noisy_world(seed=i) for i in range(1, 5)], history=3)
        for _ in range(5):
            eng.capture_once()
        self.assertLessEqual(len(eng.frames), 3)

    def test_a_failing_grab_does_not_kill_the_loop(self):
        calls = {"n": 0}

        def grab(_rect):
            calls["n"] += 1
            if calls["n"] == 1:
                raise OSError("window gone")
            return noisy_world()

        eng = engine.Engine(grab, (0, 0, 320, 180), classify_every=1)
        self.assertIsNone(eng.capture_once())
        self.assertIsNotNone(eng.capture_once())
        self.assertIn("window gone", eng.answer("health")["last_error"])

    def test_changed_answers_from_the_ring_buffer(self):
        a = noisy_world(seed=1)
        b = noisy_world(seed=2)
        eng = self._engine([a, b], history=10)
        eng.capture_once()
        eng.capture_once()
        answer = eng.answer("changed", seconds=60)
        self.assertTrue(answer["ok"], answer)
        self.assertTrue(answer["changed"], answer)
        self.assertGreater(answer["ratio"], 0.5)

    def test_changed_boxes_are_in_screen_coordinates(self):
        # The engine's rect starts at (100, 50), so a change in the frame's
        # top-left tile must be reported around (100, 50), not (0, 0). This is
        # the bug that makes a click land in the wrong place.
        a = solid(320, 180, (30, 30, 30))
        b = a.copy()
        b[0:30, 0:40] = (250, 250, 250)

        it = iter([a, b])

        def grab(_rect):
            try:
                return next(it)
            except StopIteration:
                return b

        eng = engine.Engine(grab, (100, 50, 320, 180), classify_every=1)
        eng.capture_once()
        eng.capture_once()
        answer = eng.answer("changed", seconds=60)
        self.assertTrue(answer["boxes"], answer)
        first = answer["boxes"][0]
        self.assertGreaterEqual(first["x"], 100)
        self.assertGreaterEqual(first["y"], 50)

    def test_colour_answer_reports_share_and_boxes(self):
        frame = solid(320, 180, (10, 10, 10))
        frame[10:40, 10:60] = (255, 206, 84)
        eng = self._engine([frame])
        eng.capture_once()
        answer = eng.answer("colour", colour=(255, 206, 84), tolerance=10, min_ratio=0.01)
        self.assertTrue(answer["ok"], answer)
        self.assertGreater(answer["share"], 0.0)
        self.assertTrue(answer["boxes"], answer)

    def test_motion_reports_the_peak_not_the_average(self):
        # One brief move then stillness. A before/after diff would average the
        # move away; the peak catches it.
        still = solid(320, 180, (30, 30, 30))
        moved = still.copy()
        moved[80:120, 100:140] = (255, 255, 255)
        eng = self._engine([still, moved, still, still, still], history=10)
        for _ in range(5):
            eng.capture_once()
        answer = eng.answer("motion", seconds=60)
        self.assertTrue(answer["ok"], answer)
        self.assertTrue(answer["moving"], answer)
        self.assertGreater(answer["peak_ratio"], answer["mean_ratio"])

    def test_state_answer_carries_an_age(self):
        eng = self._engine([noisy_world()])
        eng.capture_once()
        answer = eng.answer("state")
        self.assertTrue(answer["ok"], answer)
        self.assertEqual(answer["state"], "world")
        self.assertGreaterEqual(answer["age_ms"], 0)

    def test_health_reports_the_rect_and_frame_count(self):
        eng = self._engine([noisy_world()])
        eng.capture_once()
        health = eng.answer("health")
        self.assertEqual(health["rect"]["w"], 320)
        self.assertEqual(health["frames"], 1)

    def test_a_full_hd_capture_is_stored_reduced(self):
        # The mutation that removed downscaling from the engine stayed green
        # until this test existed, and that mutation is a real memory leak: a
        # full-HD frame is 6MB and sixty of them is 373MB held while the game
        # runs. The stored frame must be the small one.
        full = noisy_world(1920, 1080)

        def grab(_rect):
            return full

        eng = engine.Engine(grab, (0, 0, 1920, 1080), analysis_width=480, classify_every=1)
        frame = eng.capture_once()
        self.assertLessEqual(frame.pixels.shape[1], 480)
        self.assertEqual(eng.scale, 4)

    def test_a_box_found_in_a_reduced_frame_maps_back_to_the_screen(self):
        # A change in the reduced frame's top-left corner must be reported at
        # the engine's rect origin, not at zero, and the box must be scaled up
        # to screen pixels or a click built from it lands in the wrong place.
        full = solid(1920, 1080, (30, 30, 30))
        changed = full.copy()
        changed[0:120, 0:160] = (250, 250, 250)  # a big bright corner
        frames = iter([full, changed])

        def grab(_rect):
            try:
                return next(frames)
            except StopIteration:
                return changed

        eng = engine.Engine(grab, (100, 50, 1920, 1080), analysis_width=480, classify_every=1)
        eng.capture_once()
        eng.capture_once()
        answer = eng.answer("changed", seconds=60)
        self.assertTrue(answer["boxes"], answer)
        first = answer["boxes"][0]
        self.assertGreaterEqual(first["x"], 100)
        self.assertGreaterEqual(first["y"], 50)

    def test_unknown_question_is_an_error_not_a_crash(self):
        eng = self._engine([noisy_world()])
        answer = eng.answer("what-colour-is-the-dragon")
        self.assertFalse(answer["ok"])
        self.assertIn("unknown question", answer["error"])

    def test_health_reports_the_scale_and_analysis_width(self):
        # A caller needs to know how much the stored frame is reduced to turn a
        # box from the analysis back into a screen coordinate.
        eng = self._engine([noisy_world()])
        eng.capture_once()
        health = eng.answer("health")
        self.assertIn("scale", health)
        self.assertIn("analysis_width", health)

    def test_snapshot_saves_the_frame_the_answer_came_from(self):
        # The saved picture must be the analysed frame, not a fresh screenshot
        # taken later. That is the difference between evidence and decoration.
        import tempfile

        frame = noisy_world(320, 180)
        eng = self._engine([frame])
        eng.capture_once()
        with tempfile.TemporaryDirectory() as tmp:
            out = os.path.join(tmp, "shot.png")
            answer = eng.answer("snapshot", out=out)
            # Checked inside the block: the directory is removed on exit, and
            # asserting afterwards tests the cleanup, not the snapshot.
            self.assertTrue(os.path.exists(out))
        self.assertTrue(answer["ok"], answer)
        self.assertEqual(answer["frame"], 0)
        self.assertEqual(answer["stored"], {"w": 320, "h": 180})

    def test_snapshot_without_a_path_is_an_error_not_a_crash(self):
        eng = self._engine([noisy_world()])
        eng.capture_once()
        answer = eng.answer("snapshot")
        self.assertFalse(answer["ok"])
        self.assertIn("output path", answer["error"])

    def test_snapshot_with_no_frames_says_so(self):
        eng = self._engine([noisy_world()])
        answer = eng.answer("snapshot", out="x.png")
        self.assertFalse(answer["ok"])
        self.assertIn("no frames", answer["error"])

    def test_at_or_before_finds_the_frame_before_a_moment(self):
        eng = self._engine([noisy_world(seed=i) for i in range(1, 6)], history=10)
        for _ in range(5):
            eng.capture_once()
        middle = list(eng.frames)[2]
        found = eng.at_or_before(middle.at)
        self.assertEqual(found.index, middle.index)


class SpeedTests(unittest.TestCase):
    """The point of this package is speed, so speed is asserted, not assumed.

    The budgets are set against the frame the engine actually analyses, which is
    a reduced copy (about 422x227 for PC1's 1264x681 client area), not the raw
    screen. That is the whole design: the screen is grabbed at full size, then
    reduced once, and every later question is answered from the small frame.
    Measuring against full HD would be measuring a path the engine never takes.

    The budget is 30ms, and it is derived rather than picked. The watcher's
    interval is 100ms, so an operation that costs 30ms still leaves two thirds
    of the frame for capture and for the next question. The measured figures are
    far below it on both machines, and the gap between them is why the budget is
    not tighter: this ran at 3.4ms on the sandbox and at 15.9ms on PC1, whose
    Intel HD CPU is roughly five times slower. A budget set to the fast machine
    would fail on the slow one and teach nothing.
    """

    STORED = (480, 270)
    BUDGET_S = 0.030

    def test_a_stored_frame_can_be_classified_within_the_frame_budget(self):
        import time

        frame = noisy_world(*self.STORED)
        state.classify_frame(frame)  # warm up
        began = time.perf_counter()
        for _ in range(20):
            state.classify_frame(frame)
        per_call = (time.perf_counter() - began) / 20
        self.assertLess(per_call, self.BUDGET_S, f"classify took {per_call * 1000:.1f}ms")

    def test_change_detection_on_a_stored_frame_is_within_the_frame_budget(self):
        import time

        a = noisy_world(*self.STORED, seed=1)
        b = noisy_world(*self.STORED, seed=2)
        signature.change_ratio(a, b)  # warm up
        began = time.perf_counter()
        for _ in range(20):
            signature.change_ratio(a, b)
        per_call = (time.perf_counter() - began) / 20
        self.assertLess(per_call, self.BUDGET_S, f"diff took {per_call * 1000:.1f}ms")

    def test_a_full_hd_screen_is_reduced_once_then_analysed_cheaply(self):
        import time

        full = noisy_world(1920, 1080)
        began = time.perf_counter()
        small, factor = signature.downscale(full, 480)
        reduce_ms = (time.perf_counter() - began) * 1000
        self.assertEqual(factor, 4)
        self.assertLess(reduce_ms, 5.0, f"downscale took {reduce_ms:.1f}ms")
        # And the reduced frame is the cheap one everything else works on.
        self.assertLess(small.nbytes, 1_000_000)

    def test_downscaling_makes_a_full_hd_frame_cheap_to_hold(self):
        frame = noisy_world(1920, 1080)
        small, factor = signature.downscale(frame, 480)
        self.assertEqual(factor, 4)
        self.assertLessEqual(small.shape[1], 480)
        self.assertLess(small.nbytes, frame.nbytes / 10)

    def test_downscale_leaves_a_small_frame_alone(self):
        frame = noisy_world(320, 180)
        small, factor = signature.downscale(frame, 480)
        self.assertEqual(factor, 1)
        self.assertIs(small, frame)

    def test_sampled_diff_still_catches_a_moved_avatar(self):
        # A 60x50 avatar on a 480x270 frame is about 2% of the pixels, which is
        # what the avatar actually covers once the frame is reduced. Sampling
        # every second pixel must still see it.
        a = noisy_world(*self.STORED, seed=1)
        b = a.copy()
        b[120:170, 200:260] = (255, 255, 255)
        self.assertTrue(signature.has_changed(a, b, step=2))

    def test_sampled_changed_boxes_are_reported_in_original_coordinates(self):
        a = solid(320, 180, (30, 30, 30))
        b = a.copy()
        b[100:120, 200:240] = (250, 250, 250)
        boxes = signature.changed_boxes(a, b, cols=8, rows=6, step=2)
        self.assertTrue(boxes)
        for x, y, w, h in boxes:
            self.assertLessEqual(x + w, 320)
            self.assertLessEqual(y + h, 180)


class CliTests(unittest.TestCase):
    """The CLI, driven on Linux by pointing its runtime directory at a temp dir.

    ``python -m axvision health`` failed on PC1 with "No module named
    axvision.__main__" because the package had no ``__main__.py``, and every
    documented command uses that form. The first test here is the guard for it.
    """

    def setUp(self):
        import tempfile
        from axvision import cli

        self.cli = cli
        self._saved = cli.RUNTIME
        self.tmp = tempfile.mkdtemp(prefix="axvision-test-")
        cli.RUNTIME = self.tmp
        cli.PID_FILE = os.path.join(self.tmp, "axvision.pid")
        cli.STATE_FILE = os.path.join(self.tmp, "axvision.state.json")
        cli.REQ_FILE = os.path.join(self.tmp, "request.json")
        cli.RES_FILE = os.path.join(self.tmp, "response.json")
        cli.LOG_FILE = os.path.join(self.tmp, "axvision.log")

    def tearDown(self):
        import shutil

        self.cli.RUNTIME = self._saved
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_the_default_runtime_is_not_a_windows_path_on_linux(self):
        # A hardcoded Windows default is created as a literal folder named
        # "C:\AX-Runtime\vision" in the current directory when the module is
        # used anywhere else, which is how a junk directory ended up in the repo.
        import importlib

        saved = os.environ.pop("AX_VISION_DIR", None)
        try:
            reloaded = importlib.reload(self.cli)
            if os.name == "nt":
                self.assertTrue(reloaded.RUNTIME.startswith("C:"))
            else:
                self.assertNotIn("\\", reloaded.RUNTIME)
                self.assertTrue(reloaded.RUNTIME.startswith("/"))
        finally:
            if saved is not None:
                os.environ["AX_VISION_DIR"] = saved
            importlib.reload(self.cli)

    def test_the_package_can_be_run_as_a_module(self):
        # ``python -m axvision`` needs a __main__ module inside the package.
        import axvision.__main__ as entry

        self.assertTrue(callable(entry.main))

    def test_the_parser_knows_every_documented_command(self):
        parser = self.cli.build_parser()
        for command in ("start", "stop", "state", "changed", "motion", "colour", "health"):
            args = parser.parse_args([command])
            self.assertTrue(callable(args.func), command)

    def test_an_unknown_command_is_rejected(self):
        parser = self.cli.build_parser()
        with self.assertRaises(SystemExit):
            parser.parse_args(["fly-the-dragon"])

    def test_pid_file_round_trips(self):
        with open(self.cli.PID_FILE, "w", encoding="utf-8") as fh:
            fh.write("4242\n")
        self.assertEqual(self.cli._read_pid(), 4242)

    def test_a_missing_pid_file_reads_as_zero_not_an_error(self):
        self.assertEqual(self.cli._read_pid(), 0)

    def test_a_dead_pid_is_not_alive(self):
        self.assertFalse(self.cli._pid_alive(0))
        self.assertFalse(self.cli._pid_alive(-1))

    def test_atomic_write_leaves_no_temp_file_behind(self):
        self.cli._atomic_write(self.cli.STATE_FILE, {"state": "world"})
        self.assertTrue(os.path.exists(self.cli.STATE_FILE))
        self.assertFalse(os.path.exists(self.cli.STATE_FILE + ".tmp"))
        self.assertEqual(self.cli._read_state()["state"], "world")

    def test_the_mailbox_answers_a_request_from_the_engine(self):
        # The watcher serves a request file and writes a response the caller
        # polls for. This drives both halves against a synthetic engine, which
        # is the whole contract between the two processes.
        from axvision import engine

        def grab(_rect):
            return noisy_world()

        eng = engine.Engine(grab, (0, 0, 320, 180), classify_every=1)
        eng.capture_once()
        self.cli._atomic_write(self.cli.REQ_FILE, {"id": "abc", "question": "state"})
        self.cli._answer_mailbox(eng)
        with open(self.cli.RES_FILE, encoding="utf-8") as fh:
            answer = json.load(fh)
        self.assertEqual(answer["id"], "abc")
        self.assertTrue(answer["ok"], answer)
        self.assertEqual(answer["state"], "world")

    def test_a_bad_question_gets_an_error_not_a_crash(self):
        from axvision import engine

        eng = engine.Engine(lambda _r: noisy_world(), (0, 0, 320, 180), classify_every=1)
        eng.capture_once()
        self.cli._atomic_write(self.cli.REQ_FILE, {"id": "x", "question": "sing"})
        self.cli._answer_mailbox(eng)
        with open(self.cli.RES_FILE, encoding="utf-8") as fh:
            answer = json.load(fh)
        self.assertFalse(answer["ok"])
        self.assertIn("unknown question", answer["error"])

    def test_a_query_with_no_watcher_falls_back_to_a_oneshot(self):
        # On Linux there is no screen, so the oneshot path fails - but it must
        # fail as a JSON error, not as a traceback, or the caller cannot tell
        # "no watcher" from "the tool is broken".
        answer = self.cli._ask_oneshot("state")
        self.assertIn("ok", answer)

    def test_colour_query_parses_an_rgb_string(self):
        seen = {}

        def fake_ask(question, **kwargs):
            seen["question"] = question
            seen.update(kwargs)
            return {"ok": True}

        self.cli._ask = fake_ask
        args = self.cli.build_parser().parse_args(["colour", "--rgb", "1,2,3", "--tolerance", "9"])
        self.cli.cmd_query(args)
        self.assertEqual(seen["colour"], [1, 2, 3])
        self.assertEqual(seen["tolerance"], 9)


class FrozenTests(unittest.TestCase):
    """A frozen picture is not the same thing as a quiet game.

    This was found live. The Roblox client on PC1 had been running four hours and
    its surface had stopped updating: two captures forty seconds apart were
    byte-identical, while the desktop around it was live (moving the cursor
    changed the pixels at the cursor). The engine reported "world" with the same
    confidence it reports a running game, so an agent acting on that would send
    input into a dead surface and conclude the game ignored it.

    A human spots this in a second. The engine has to spot it too, so it tracks
    how long the picture has been unchanged and says so.
    """

    def _engine(self, frames, clock):
        return engine.Engine(
            _SequenceGrabber(frames), (0, 0, 320, 180), interval=0.1, classify_every=1,
            frozen_after=2.0, clock=lambda: clock.now,
        )

    def test_a_screen_that_never_changes_is_reported_frozen(self):
        clock = FakeClock()
        still = noisy_world(seed=7)
        eng = self._engine([still], clock)
        eng.capture_once()
        self.assertFalse(eng.answer("state")["frozen"])
        for _ in range(30):
            clock.advance(0.2)
            eng.capture_once()
        answer = eng.answer("state")
        self.assertTrue(answer["frozen"], answer)
        self.assertGreaterEqual(answer["still_ms"], 2000)

    def test_a_screen_that_keeps_changing_is_never_frozen(self):
        clock = FakeClock()
        frames = [noisy_world(seed=i) for i in range(1, 20)]
        eng = self._engine(frames, clock)
        for _ in range(18):
            eng.capture_once()
            clock.advance(0.2)
        self.assertFalse(eng.answer("state")["frozen"])

    def test_a_screen_that_stops_moving_goes_frozen_then_recovers(self):
        # The interesting case is a game that hangs and then comes back, which
        # is exactly what a stalled client does. The flag must clear itself.
        clock = FakeClock()
        moving = [noisy_world(seed=i) for i in range(1, 10)]
        still = noisy_world(seed=99)
        # Moving, then twenty identical frames, then moving again: the shape of a
        # client that hangs and comes back. The tail is long enough that the run
        # ends while the picture is still changing, so the assertion at the end
        # tests recovery rather than the grabber repeating its last frame.
        tail = [noisy_world(seed=200 + i) for i in range(20)]
        seq = moving + [still] * 20 + tail
        eng = engine.Engine(
            _SequenceGrabber(seq), (0, 0, 320, 180), interval=0.1, classify_every=1,
            frozen_after=2.0, clock=lambda: clock.now,
        )
        for _ in range(9):
            eng.capture_once()
            clock.advance(0.2)
        self.assertFalse(eng.answer("state")["frozen"])
        for _ in range(15):
            eng.capture_once()
            clock.advance(0.2)
        self.assertTrue(eng.answer("state")["frozen"])
        for _ in range(20):
            eng.capture_once()
            clock.advance(0.2)
        self.assertFalse(eng.answer("state")["frozen"])

    def test_changed_says_the_screen_is_frozen_rather_than_just_quiet(self):
        clock = FakeClock()
        still = noisy_world(seed=5)
        eng = self._engine([still], clock)
        for _ in range(30):
            eng.capture_once()
            clock.advance(0.2)
        answer = eng.answer("changed", seconds=1.0)
        self.assertFalse(answer["changed"])
        self.assertTrue(answer["frozen"], answer)

    def test_a_frozen_screen_is_not_a_black_screen(self):
        # "Frozen" and "black" are different diagnoses with different fixes, and
        # a frozen frame of a running game still classifies as the world.
        clock = FakeClock()
        eng = self._engine([noisy_world(seed=3)], clock)
        for _ in range(30):
            eng.capture_once()
            clock.advance(0.2)
        answer = eng.answer("state")
        self.assertEqual(answer["state"], "world")
        self.assertTrue(answer["frozen"])


class FakeClock:
    def __init__(self):
        self.now = 1000.0
        self.frames_seen = 0

    def advance(self, seconds):
        self.now += seconds


class _SequenceGrabber:
    """Returns frames from a list in order, repeating the last one."""

    def __init__(self, frames):
        self.frames = list(frames)
        self.i = 0

    def __call__(self, _rect):
        frame = self.frames[min(self.i, len(self.frames) - 1)]
        self.i += 1
        return frame


if __name__ == "__main__":
    unittest.main(verbosity=2)

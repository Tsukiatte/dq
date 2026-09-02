"""Module load order. Definition order is load-bearing: a module may only import
(`local x = S.x`) from modules listed BEFORE it. Keep in sync with main.lua."""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")
BUNDLE = os.path.join(ROOT, "DungeonAutofarm.lua")

ORDER = ["core", "gamedata", "uikit", "hazards", "precast", "threat", "nav", "mover", "clone", "path", "macro", "streamer", "config", "ui", "main"]

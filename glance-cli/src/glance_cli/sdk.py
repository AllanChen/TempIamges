"""Optional typed helpers for Widget authors."""

from pathlib import Path
from typing import Literal, TypedDict


class WidgetInput(TypedDict, total=False):
    path: str
    url: str
    assetID: str


class WidgetTask(TypedDict, total=False):
    taskId: str
    widgetId: str
    version: str
    commandId: str
    parameters: dict
    input: WidgetInput


class TextOutput(TypedDict):
    type: Literal["text"]
    text: str


class FileOutput(TypedDict):
    type: Literal["image", "video", "audio"]
    path: str


class MediaURLOutput(TypedDict):
    type: Literal["image", "video", "audio"]
    url: str


def text(value: str) -> TextOutput:
    return {"type": "text", "text": value}


def image(path: str | Path) -> FileOutput:
    return {"type": "image", "path": str(path)}


def video(path: str | Path) -> FileOutput:
    return {"type": "video", "path": str(path)}


def audio(path: str | Path) -> FileOutput:
    return {"type": "audio", "path": str(path)}


def result(*outputs: TextOutput | FileOutput | MediaURLOutput) -> dict:
    return {"outputs": list(outputs)}

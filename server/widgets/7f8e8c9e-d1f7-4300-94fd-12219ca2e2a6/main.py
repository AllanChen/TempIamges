"""Download all media (images and videos) from an X (Twitter) post.

Input: the post URL or tweet ID (parameters.prompt), e.g. "https://x.com/user/status/123...".
The tweet is resolved through X's public syndication API, with the fxtwitter mirror as a
fallback. Every photo and the best-quality MP4 variant of every video is downloaded into
GLANCE_TASK_OUTPUT_DIR and returned as image/video outputs.
"""

import argparse
import json
import logging
import math
import os
import re
import tempfile
import uuid
from pathlib import Path

import requests

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)

USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"
SYNDICATION_URL = "https://cdn.syndication.twimg.com/tweet-result"
FXTWITTER_URL = "https://api.fxtwitter.com/status"
REQUEST_TIMEOUT = 60
MAX_RETRIES = 3
MAX_BYTES = 50 * 1024 * 1024  # runtime upload limit per output file
MAX_MEDIA = 8  # a post can carry at most 4 media; cap defensively

STATUS_PATTERN = re.compile(
    r"(?:^|//|\.)(?:www\.|mobile\.)?(?:x|twitter)\.com/[A-Za-z0-9_]{1,20}/status(?:es)?/(\d{5,25})")
ID_PATTERN = re.compile(r"^\d{5,25}$")


class TweetNotFoundError(Exception):
    """The post does not exist or is not public; retrying will not help."""


class NoMediaError(Exception):
    """The post exists but contains no image or video."""


def parse_tweet_id(text: str) -> str:
    """Extract the numeric tweet ID from a post URL, or accept a bare ID."""
    text = text.strip()
    if ID_PATTERN.match(text):
        return text
    match = STATUS_PATTERN.search(text)
    if match:
        return match.group(1)
    raise ValueError(
        "无法识别 X 帖子链接。请提供形如 https://x.com/用户名/status/123456 的链接，"
        "或直接提供帖子 ID。")


def js_base36(number: float) -> str:
    """Emulate JavaScript Number.prototype.toString(36) for the syndication token."""
    digits = "0123456789abcdefghijklmnopqrstuvwxyz"
    integer = int(number)
    fraction = number - integer
    result = ""
    while integer:
        integer, remainder = divmod(integer, 36)
        result = digits[remainder] + result
    result = result or "0"
    if fraction > 0:
        result += "."
        for _ in range(20):  # JS prints enough digits to capture double precision
            fraction *= 36
            digit = int(fraction)
            result += digits[digit]
            fraction -= digit
        result = result.rstrip("0")
    return result


def syndication_token(tweet_id: str) -> str:
    """The token X's syndication endpoint expects, derived from the tweet ID."""
    token = js_base36((int(tweet_id) / 1e15) * math.pi)
    return token.replace(".", "").replace("0", "")


def best_photo_url(url: str) -> str:
    """Ask pbs.twimg.com for the largest available version of a photo."""
    if "pbs.twimg.com" in url and "name=" not in url:
        separator = "&" if "?" in url else "?"
        return f"{url}{separator}name=orig"
    return url


def best_video_variant(variants: list) -> str:
    """Pick the highest-bitrate MP4 from a video_info.variants list."""
    mp4s = [variant for variant in variants
            if variant.get("content_type") == "video/mp4" and variant.get("url")]
    if not mp4s:
        return ""
    return max(mp4s, key=lambda variant: variant.get("bitrate") or 0)["url"]


def media_from_syndication(tweet_id: str) -> list:
    """Resolve media through X's public syndication API.

    Returns a list of (kind, url) with kind "image" or "video"."""
    response = requests.get(
        SYNDICATION_URL,
        params={"id": tweet_id, "lang": "en", "token": syndication_token(tweet_id)},
        headers={"User-Agent": USER_AGENT}, timeout=REQUEST_TIMEOUT)
    if response.status_code == 404:
        raise TweetNotFoundError(f"syndication returned 404 for tweet {tweet_id}")
    response.raise_for_status()
    body = response.json()
    details = body.get("mediaDetails") or []
    media = []
    for item in details:
        kind = item.get("type")
        if kind == "photo" and item.get("media_url_https"):
            media.append(("image", best_photo_url(item["media_url_https"])))
        elif kind in ("video", "animated_gif"):
            url = best_video_variant((item.get("video_info") or {}).get("variants") or [])
            if url:
                media.append(("video", url))
    if media:
        return media
    if body.get("text") is not None or body.get("user"):
        raise NoMediaError(f"tweet {tweet_id} has no downloadable media")
    raise RuntimeError(f"syndication returned an unexpected payload: {str(body)[:300]}")


def media_from_fxtwitter(tweet_id: str) -> list:
    """Fallback resolver through the fxtwitter mirror API (same (kind, url) list)."""
    response = requests.get(f"{FXTWITTER_URL}/{tweet_id}",
                            headers={"User-Agent": USER_AGENT}, timeout=REQUEST_TIMEOUT)
    if response.status_code in (404, 400):
        raise TweetNotFoundError(f"fxtwitter returned {response.status_code} for tweet {tweet_id}")
    response.raise_for_status()
    body = response.json()
    media = (body.get("tweet") or {}).get("media") or {}
    results = [("image", best_photo_url(photo["url"])) for photo in media.get("photos") or []
               if photo.get("url")]
    results += [("video", video["url"]) for video in media.get("videos") or [] if video.get("url")]
    if results:
        return results
    if (body.get("tweet") or {}).get("text"):
        raise NoMediaError(f"tweet {tweet_id} has no downloadable media")
    raise RuntimeError(f"fxtwitter returned an unexpected payload: {str(body)[:300]}")


def resolve_media(tweet_id: str) -> list:
    """Try the syndication API first, then the fxtwitter mirror."""
    errors = []
    for resolver in (media_from_syndication, media_from_fxtwitter):
        try:
            media = resolver(tweet_id)
            logger.info("Resolved %d media item(s) for tweet %s via %s",
                        len(media), tweet_id, resolver.__name__)
            return media[:MAX_MEDIA]
        except (TweetNotFoundError, NoMediaError):
            raise
        except Exception as error:
            logger.warning("%s failed for tweet %s: %s", resolver.__name__, tweet_id, error)
            errors.append(error)
    raise RuntimeError(f"无法解析该帖子的媒体：{errors[-1]}")


def download(url: str, destination: Path) -> None:
    """Stream one media file to disk, enforcing the 50 MB per-file limit."""
    with requests.get(url, headers={"User-Agent": USER_AGENT}, timeout=REQUEST_TIMEOUT,
                      stream=True) as response:
        response.raise_for_status()
        with destination.open("wb") as output:
            size = 0
            for chunk in response.iter_content(chunk_size=1024 * 1024):
                size += len(chunk)
                if size > MAX_BYTES:
                    destination.unlink(missing_ok=True)
                    raise ValueError(f"媒体文件超过 50 MB，无法作为结果返回：{url}")
                output.write(chunk)
    if destination.stat().st_size == 0:
        destination.unlink(missing_ok=True)
        raise RuntimeError(f"下载到的文件为空：{url}")


def suffix_for(kind: str, url: str) -> str:
    suffix = Path(url.split("?")[0]).suffix.lower()
    if kind == "video":
        return suffix if suffix in (".mp4", ".mov", ".webm") else ".mp4"
    return suffix if suffix in (".jpg", ".jpeg", ".png", ".webp", ".gif") else ".jpg"


def run_download(tweet_id: str, output_dir: Path) -> list:
    """Resolve and download all media of the tweet; transient failures are retried."""
    media = resolve_media(tweet_id)
    outputs = []
    counters = {"image": 0, "video": 0}
    for kind, url in media:
        counters[kind] += 1
        destination = output_dir / f"x-{tweet_id}-{kind}-{counters[kind]}{suffix_for(kind, url)}"
        for attempt in range(1, MAX_RETRIES + 1):
            try:
                download(url, destination)
                break
            except ValueError:
                raise  # over-limit files are a permanent condition
            except Exception:
                if attempt == MAX_RETRIES:
                    raise
                logger.warning("Download attempt %d/%d failed for %s; retrying",
                               attempt, MAX_RETRIES, url, exc_info=True)
        logger.info("Downloaded %s (%d bytes)", destination.name, destination.stat().st_size)
        outputs.append({"type": kind, "path": str(destination)})
    return outputs


def download_post(prompt: str) -> dict:
    tweet_id = parse_tweet_id(prompt)
    output_dir = Path(os.environ.get("GLANCE_TASK_OUTPUT_DIR") or tempfile.mkdtemp(prefix="glance-widget-"))
    output_dir.mkdir(parents=True, exist_ok=True)
    try:
        outputs = run_download(tweet_id, output_dir)
    except TweetNotFoundError:
        raise ValueError(
            "找不到这条 X 帖子，或它不是公开的。请确认链接正确、帖子未删除且账号未设为私密。"
        ) from None
    except NoMediaError:
        raise ValueError("这条 X 帖子没有可下载的图片或视频。") from None
    return {"outputs": outputs}


def main(task: dict) -> dict:
    """Use parameters.prompt as the X post URL (fall back to the task input URL or path)."""
    parameters = task.get("parameters") or {}
    prompt = parameters.get("prompt")
    if prompt is not None and not isinstance(prompt, str):
        raise ValueError("帖子链接必须是文本。")
    if not (prompt or "").strip():
        inputs = task.get("input") or {}
        prompt = inputs.get("url") or inputs.get("path") or ""
    prompt = (prompt or "").strip()
    if not prompt:
        raise ValueError("请提供 X 帖子链接，例如 https://x.com/用户名/status/123456。")
    return download_post(prompt)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Download all media of an X post")
    parser.add_argument("url", help="post URL or tweet ID")
    arguments = parser.parse_args()
    print(json.dumps(download_post(arguments.url), ensure_ascii=False))

"""PhoWhisperTranscriber: uploads audio to the Kaggle speech server through a fake HTTP transport."""

import httpx
import pytest

from app.service.voice.transcriber import AsrRejected, AsrUnavailable, PhoWhisperTranscriber

TUNNEL = "https://secret-words.trycloudflare.com"


def make_transcriber(handler) -> PhoWhisperTranscriber:
    """Transcriber whose HTTP calls go to `handler` instead of the network."""
    http = httpx.Client(base_url=TUNNEL, transport=httpx.MockTransport(handler),
                        headers={"Authorization": "Bearer t0ken"})
    return PhoWhisperTranscriber(http=http)


def test_uploads_raw_audio_with_token_and_returns_text(tmp_path):
    audio = tmp_path / "a.m4a"
    audio.write_bytes(b"fake-audio")
    seen = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen.update(path=request.url.path, auth=request.headers["Authorization"], body=request.content)
        return httpx.Response(200, json={"text": "  học giải tích lúc bảy giờ  "})

    result = make_transcriber(handler).transcribe_file(str(audio))

    assert result.text == "học giải tích lúc bảy giờ"
    assert seen == {"path": "/transcribe", "auth": "Bearer t0ken", "body": b"fake-audio"}


def test_errors_do_not_leak_the_tunnel_url(tmp_path):
    audio = tmp_path / "a.wav"
    audio.write_bytes(b"x")
    transcriber = make_transcriber(lambda request: httpx.Response(401))

    with pytest.raises(AsrUnavailable) as error:  # 401 = wrong ASR_TOKEN in .env: fixable, so retry later
        transcriber.transcribe_file(str(audio))

    assert "401" in str(error.value) and "trycloudflare" not in str(error.value)


def test_undecodable_audio_is_final(tmp_path):
    audio = tmp_path / "a.wav"
    audio.write_bytes(b"x")
    with pytest.raises(AsrRejected):
        make_transcriber(lambda request: httpx.Response(400)).transcribe_file(str(audio))


def test_missing_url_fails_early():
    with pytest.raises(AsrUnavailable, match="ASR_BASE_URL"):
        PhoWhisperTranscriber(base_url="")

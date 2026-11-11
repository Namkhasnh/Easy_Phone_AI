"""1B.15: one real `/v1/transcribe` model call (API_CONTRACT §7.4). Costs money — `pytest -m live` only.

The clip is synthetic: macOS `say` (voice "Linh", vi_VN) reads a fixed sentence into an M4A/AAC file, so no
user audio is involved. Checks that `MODEL_TRANSCRIBE` accepts our request (incl. `include: logprobs`) and
returns Vietnamese text. Skipped where `say` is missing.
"""

import asyncio
import shutil
import subprocess
from pathlib import Path

import pytest

from app.config import Settings
from app.schemas.media import MediaMeta
from app.services import transcribe_service
from app.services.llm import LLMClient, make_openai
from app.services.metering import CostMeter, Deadline
from tests.live_eval import fuzzy_equal

pytestmark = pytest.mark.live

SENTENCE = "Nhắc tôi tám giờ sáng mai uống thuốc"


@pytest.mark.skipif(shutil.which("say") is None, reason="needs macOS `say`")
def test_live_transcribe(tmp_path: Path):
    clip = tmp_path / "speech.m4a"
    subprocess.run(["say", "-v", "Linh", "-o", str(clip), "--file-format=m4af", "--data-format=aac", SENTENCE],
                   check=True)
    data = clip.read_bytes()
    settings = Settings()
    transcribe_service.check_audio(data, settings)  # same checks as the route (≤ 2 MB, M4A)

    async def run():
        client = make_openai(settings)
        try:
            llm = LLMClient(settings, client.chat.completions, client.audio.transcriptions)
            meter = CostMeter()
            out = await transcribe_service.transcribe(
                data, MediaMeta(schemaVersion=1, locale="vi-VN"), llm, Deadline(settings.REQUEST_BUDGET_SECONDS), meter)
            return out, meter
        finally:
            await client.close()

    out, meter = asyncio.run(run())
    print(f"\n{settings.MODEL_TRANSCRIBE}: confidence={out.confidence} cost=${float(meter.cost_usd):.5f} "
          f"match={fuzzy_equal(SENTENCE, out.text)}")
    assert out.text.strip()
    assert fuzzy_equal(SENTENCE, out.text)  # synthetic sentence, not user content
    assert out.confidence is None or 0.0 <= out.confidence <= 1.0

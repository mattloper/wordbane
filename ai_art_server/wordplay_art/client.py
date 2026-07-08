"""Minimal Draw Things gRPC client for generating Wordplay art.

The server streams progress "signposts" then a final ``generatedImages`` payload.
The generation settings ride along as a FlatBuffer (``GenerationConfiguration``),
which is the fiddly part — we build it from the flatc-generated classes below.

Usage:
    uv run python -m wordplay_art.client echo
    uv run python -m wordplay_art.client generate \
        --model flux_2_klein_9b_q8p.ckpt --prompt "a fierce cartoon dragon" \
        --out dragon.png --width 512 --height 512 --steps 6
"""
from __future__ import annotations

import argparse
import os
import sys

import grpc
import flatbuffers
import numpy as np
import fpzip
from PIL import Image

# The proto- and flatc-generated modules import their siblings as top-level names,
# so put the generated dir on the path and import them flat.
_GEN = os.path.join(os.path.dirname(__file__), "_generated")
if _GEN not in sys.path:
    sys.path.insert(0, _GEN)

import imageService_pb2 as pb           # noqa: E402
import imageService_pb2_grpc as pb_grpc  # noqa: E402
import GenerationConfiguration as GC     # noqa: E402

from . import presets                    # noqa: E402

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 7859
_MAX_MSG = 256 * 1024 * 1024  # images can be big; lift the 4MB gRPC default


def _channel(host: str, port: int) -> grpc.Channel:
    return grpc.insecure_channel(
        f"{host}:{port}",
        options=[
            ("grpc.max_receive_message_length", _MAX_MSG),
            ("grpc.max_send_message_length", _MAX_MSG),
        ],
    )


def build_configuration(
    *, model: str, width: int, height: int, steps: int, seed: int,
    guidance_scale: float, sampler: int, guidance_embed: float, shift: float,
    batch_size: int, seed_mode: int, resolution_dependent_shift: bool,
) -> bytes:
    """Serialize a GenerationConfiguration FlatBuffer. Draw Things stores the size
    as 64-pixel units, so width/height (pixels) are divided by 64."""
    if width % 64 or height % 64:
        raise ValueError("width/height must be multiples of 64")
    b = flatbuffers.Builder(1024)
    model_off = b.CreateString(model)  # strings must exist before the table starts
    GC.GenerationConfigurationStart(b)
    GC.GenerationConfigurationAddId(b, 0)
    GC.GenerationConfigurationAddModel(b, model_off)
    GC.GenerationConfigurationAddStartWidth(b, width // 64)
    GC.GenerationConfigurationAddStartHeight(b, height // 64)
    GC.GenerationConfigurationAddSeed(b, seed)
    GC.GenerationConfigurationAddSteps(b, steps)
    GC.GenerationConfigurationAddGuidanceScale(b, guidance_scale)
    GC.GenerationConfigurationAddSampler(b, sampler)
    GC.GenerationConfigurationAddBatchCount(b, 1)
    GC.GenerationConfigurationAddBatchSize(b, batch_size)
    GC.GenerationConfigurationAddClipSkip(b, 1)
    GC.GenerationConfigurationAddSeedMode(b, seed_mode)
    GC.GenerationConfigurationAddShift(b, shift)
    GC.GenerationConfigurationAddResolutionDependentShift(b, resolution_dependent_shift)
    GC.GenerationConfigurationAddSpeedUpWithGuidanceEmbed(b, True)
    GC.GenerationConfigurationAddGuidanceEmbed(b, guidance_embed)
    cfg = GC.GenerationConfigurationEnd(b)
    b.Finish(cfg)
    return bytes(b.Output())


_COMPRESSED_MAGIC = 1012247  # header[0] flags fpzip-compressed float16 pixel data


def decode_image(raw: bytes) -> Image.Image:
    """Draw Things returns a raw ccv_nnc tensor: a 68-byte header (17x uint32;
    [6:8]=height,width, [8]=channels), then float16 pixels in [-1, 1] — fpzip-
    compressed when header[0] == 1012247. Decode it to a PIL image."""
    header = np.frombuffer(raw, dtype=np.uint32, count=17)
    height, width, channels = int(header[6]), int(header[7]), int(header[8])
    if header[0] == _COMPRESSED_MAGIC:
        buf = fpzip.decompress(raw[68:], order="C").astype(np.float16).tobytes()
    else:
        buf = raw[68:]
    data = np.frombuffer(buf, dtype=np.float16, count=width * height * channels)
    px = np.clip((data.astype(np.float32) + 1.0) * 127.0, 0, 255).astype(np.uint8)
    px = px.reshape((height, width, channels))
    mode = {1: "L", 3: "RGB", 4: "RGBA"}.get(channels, "RGB")
    return Image.fromarray(px, mode)


def echo(host: str, port: int, name: str = "wordplay") -> pb.EchoReply:
    with _channel(host, port) as ch:
        stub = pb_grpc.ImageGenerationServiceStub(ch)
        return stub.Echo(pb.EchoRequest(name=name), timeout=10)


def generate(
    *, prompt: str, model: str, host: str = DEFAULT_HOST, port: int = DEFAULT_PORT,
    negative_prompt: str = "", seed: int = 0, batch_size: int = 1,
    overrides: dict | None = None, on_progress=None,
) -> list[bytes]:
    """Run one generation; return the final image(s) as encoded bytes. The
    generation config is looked up from presets.json by model, with `overrides`
    (a dict of preset fields, e.g. {"steps": 6}) applied on top."""
    params = presets.resolve(model, overrides)
    cfg = build_configuration(model=model, seed=seed, batch_size=batch_size, **params)
    req = pb.ImageGenerationRequest(
        prompt=prompt, negativePrompt=negative_prompt, configuration=cfg,
        user="wordplay", device=pb.LAPTOP, chunked=False,
    )
    images: list[bytes] = []
    with _channel(host, port) as ch:
        stub = pb_grpc.ImageGenerationServiceStub(ch)
        for resp in stub.GenerateImage(req):
            if on_progress is not None and resp.HasField("currentSignpost"):
                on_progress(resp.currentSignpost)
            if resp.generatedImages:
                images = list(resp.generatedImages)  # keep the latest non-empty set
    return images


# --- CLI ---------------------------------------------------------------------

def _cmd_echo(a) -> int:
    r = echo(a.host, a.port)
    print(f"OK: server said {r.message!r}")
    print(f"    serverIdentifier={r.serverIdentifier}  sharedSecretMissing={r.sharedSecretMissing}")
    if r.sharedSecretMissing:
        print("    NOTE: this server requires a shared secret (set one in the client).")
    return 0


def _cmd_presets(a) -> int:
    for name, p in presets.load().items():
        print(f"{name}  (matches: {', '.join(p.get('match', []))})")
        if p.get("note"):
            print(f"    note: {p['note']}")
        for k, v in p.items():
            if k not in ("match", "note"):
                print(f"    {k} = {v}")
    return 0


def _cmd_generate(a) -> int:
    def prog(sp):
        which = sp.WhichOneof("signpost") if hasattr(sp, "WhichOneof") else "?"
        sys.stderr.write(f"\r  … {which}        ")
        sys.stderr.flush()
    overrides: dict = {}
    for item in a.overrides:
        key, _, val = item.partition("=")
        overrides[key.strip()] = val
    imgs = generate(
        prompt=a.prompt, model=a.model, host=a.host, port=a.port,
        negative_prompt=a.negative, seed=a.seed, overrides=overrides, on_progress=prog,
    )
    sys.stderr.write("\n")
    if not imgs:
        print("No image returned — check the model name exists on the server.", file=sys.stderr)
        return 1
    img = decode_image(imgs[0])
    if a.downscale and a.downscale < img.width:
        img = img.resize((a.downscale, a.downscale), Image.LANCZOS)
    img.save(a.out)
    print(f"wrote {a.out} ({img.width}x{img.height}; {len(imgs)} image(s) generated)")
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Draw Things gRPC client for Wordplay art.")
    p.add_argument("--host", default=DEFAULT_HOST)
    p.add_argument("--port", type=int, default=DEFAULT_PORT)
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("echo", help="ping the server (no model needed)")
    sub.add_parser("presets", help="list model-family presets")

    g = sub.add_parser("generate", help="generate one image")
    g.add_argument("--model", required=True, help="model filename as known to Draw Things")
    g.add_argument("--prompt", required=True)
    g.add_argument("--negative", default="")
    g.add_argument("--out", required=True)
    g.add_argument("--seed", type=int, default=0)
    g.add_argument("--set", dest="overrides", action="append", default=[], metavar="KEY=VALUE",
                   help="override a preset field, e.g. --set steps=6 --set shift=2.5 (repeatable)")
    g.add_argument("--downscale", type=int, default=0, help="resize the square output to N px")

    a = p.parse_args(argv)
    if a.cmd == "echo":
        return _cmd_echo(a)
    if a.cmd == "presets":
        return _cmd_presets(a)
    if a.cmd == "generate":
        return _cmd_generate(a)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())

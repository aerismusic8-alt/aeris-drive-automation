#!/usr/bin/env python3
"""MCP client for a winremote-mcp server running on PC1.

winremote-mcp exposes a Windows desktop over the Model Context Protocol:
screenshots, PowerShell, file transfer, GUI clicks, services and scheduled
tasks. It runs on the Windows machine, so this is the piece that turns a
running PC1 into something an agent can actually operate.

This client is deliberately small and does no writing of its own. It connects,
optionally calls one tool, and prints the result as JSON. The caller decides
what to run.

  python3 ax-winremote-mcp.py --url http://127.0.0.1:8090/mcp --list-tools
  python3 ax-winremote-mcp.py --url http://127.0.0.1:8090/mcp \
      --call Snapshot --args '{"max_width": 1280}'
  python3 ax-winremote-mcp.py --url http://127.0.0.1:8090/mcp \
      --call Shell --args '{"command": "hostname"}'

Auth: pass --auth-key or set WINREMOTE_AUTH_KEY. The server refuses to bind a
non-loopback address without one, so a remote URL always needs it.

Reaching a PC1 on a home LAN from an agent that is not on that LAN needs a
tunnel. Tailscale is the least work: it gives TLS and needs no inbound port.
When this process is not itself in the tailnet, run tailscaled in userspace
mode and pass --tailnet-proxy socks5://127.0.0.1:1055. Only tailnet traffic is
routed through that proxy; everything else stays direct, because Tailscale's
userspace proxy cannot carry non-tailnet traffic. This script does not create a
tunnel and does not assume one exists.
"""

from __future__ import annotations

import argparse
import asyncio
import base64
import json
import os
import sys

import httpx2

# PC1 is Windows, where stdout defaults to a legacy code page rather than UTF-8.
# A tool result carrying any non-ASCII character -- a Thai filename in a file
# listing, a glyph in a screenshot caption -- raised UnicodeEncodeError inside
# print() and killed the call, so Shell and Snapshot reported an error for
# results they had already fetched successfully. Force UTF-8 so the JSON is
# written intact on every host.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

from mcp import ClientSession
from mcp.client.streamable_http import create_mcp_http_client, streamable_http_client

# Tailscale hands out addresses from this range. Traffic to it only exists
# inside the tailnet, so it has to go through the local SOCKS5 proxy that
# tailscaled runs in userspace mode.
TAILNET_CIDR = "100.64.0.0/10"


def _headers(auth_key: str | None) -> dict[str, str] | None:
    if not auth_key:
        return None
    return {"Authorization": f"Bearer {auth_key}"}


def _is_loopback_host(host: str) -> bool:
    return host in {"localhost", "127.0.0.1", "::1"} or host.startswith("127.")


def _build_http_client(auth_key: str | None, tailnet_proxy: str | None, url: str = ""):
    """Build the HTTP client the MCP transport will use.

    Without a tailnet proxy, defer to the SDK's own factory so its streaming
    timeouts are preserved. With one, build the client directly because the
    factory has no parameter for mounts.

    The proxy is attached as per-host mounts rather than by setting ALL_PROXY.
    Tailscale's userspace SOCKS5 proxy carries tailnet traffic only, so a global
    proxy setting would send every unrelated request into a proxy that cannot
    route it, including this process's own internet access.

    Two mount shapes are needed:

      - the tailnet CIDR, for URLs that use a 100.x address directly;
      - the URL's own origin, for `https://<machine>.<tailnet>.ts.net` names,
        which is what `tailscale serve` produces. Those names resolve through
        MagicDNS, so the SOCKS5 proxy has to resolve them, and it does: httpx
        sends the name to the proxy rather than resolving it locally.

    Loopback URLs never get a mount, so a local server stays reachable even
    when a tailnet proxy is configured.
    """
    headers = _headers(auth_key)

    if not tailnet_proxy:
        return create_mcp_http_client(headers=headers) if headers else None

    transport = httpx2.AsyncHTTPTransport(proxy=tailnet_proxy)
    mounts = {
        f"http://{TAILNET_CIDR}": transport,
        f"https://{TAILNET_CIDR}": transport,
    }

    host = url.split("//", 1)[-1].split("/", 1)[0].split(":", 1)[0] if "//" in url else ""
    if host and not _is_loopback_host(host):
        scheme = url.split("//", 1)[0]
        mounts[f"{scheme}//{host}"] = transport

    kwargs: dict = {
        "mounts": mounts,
        # No read timeout: MCP uses a long-lived SSE stream that must not be
        # cut off while the server is idle.
        "timeout": httpx2.Timeout(30.0, read=None),
    }
    if headers:
        kwargs["headers"] = headers
    return httpx2.AsyncClient(**kwargs)


def _resolve_args(args) -> dict:
    """Tool arguments, read from --args-file when it is given.

    Windows PowerShell 5.1 drops the double quotes when it hands an inline JSON
    string to a native program, so `--args '{"command":"hostname"}'` reaches
    this process as `{command:hostname}` and json.loads rejects it. The file
    path is passed through untouched, which is why it is the safer channel on
    that host.
    """
    if getattr(args, "args_file", None):
        with open(args.args_file, encoding="utf-8") as fh:
            raw = fh.read()
        try:
            parsed = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise SystemExit(f"--args-file is not valid JSON: {exc}") from exc
        if not isinstance(parsed, dict):
            raise SystemExit("--args-file must hold a JSON object")
        return parsed
    return _parse_args(args.args)


def _parse_args(raw: str | None) -> dict:
    if not raw:
        return {}
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"--args is not valid JSON: {exc}") from exc
    if not isinstance(parsed, dict):
        raise SystemExit("--args must be a JSON object")
    return parsed


def _summarize_tool(tool) -> dict:
    schema = getattr(tool, "inputSchema", None) or {}
    properties = schema.get("properties", {}) if isinstance(schema, dict) else {}
    required = schema.get("required", []) if isinstance(schema, dict) else []
    return {
        "name": getattr(tool, "name", None),
        "description": (getattr(tool, "description", None) or "").strip().split("\n")[0][:160],
        "required": list(required),
        "parameters": sorted(properties.keys()),
    }


def _image_from_text(text: str) -> dict | None:
    """Recover an image that arrived encoded inside a text item.

    Servers differ in how they send image content. Some emit a real `image`
    content item; others serialise the same thing to JSON and send it as text,
    which is what a list-returning tool does when the transport stringifies it.
    Both are a screenshot, and treating the second as plain text is how an agent
    ends up with a base64 blob it cannot look at.
    """
    stripped = text.strip()
    if not stripped.startswith("{"):
        return None
    try:
        parsed = json.loads(stripped)
    except (ValueError, TypeError):
        return None
    if not isinstance(parsed, dict) or parsed.get("type") != "image":
        return None
    data = parsed.get("data")
    if not isinstance(data, str) or not data:
        return None
    return {"data": data, "mimeType": parsed.get("mimeType")}


def _render_result(result, save_dir: str | None = None, stem: str = "image") -> dict:
    """Flatten an MCP tool result into JSON-serialisable pieces.

    Image content is reported by size rather than inlined, so a screenshot does
    not blow up a terminal or a log. When `save_dir` is given the bytes are also
    written there, because a size is not something anyone can look at: without
    this an agent driving the desktop is blind, holding a number where the
    screen should be.
    """
    out: dict = {"isError": bool(getattr(result, "isError", False)), "content": []}
    image_index = 0
    for item in getattr(result, "content", []) or []:
        item_type = getattr(item, "type", None)
        if item_type == "text":
            text = getattr(item, "text", "") or ""
            embedded = _image_from_text(text)
            if embedded:
                item_type = "image"
                data = embedded["data"]
                mime = embedded["mimeType"]
            else:
                out["content"].append({"type": "text", "text": text})
                continue
        elif item_type == "image":
            data = getattr(item, "data", "") or ""
            mime = getattr(item, "mimeType", None)
        else:
            out["content"].append({"type": str(item_type), "raw": str(item)[:400]})
            continue

        entry: dict = {"type": "image", "mimeType": mime, "base64Length": len(data)}
        if save_dir and data:
            image_index += 1
            ext = "png" if (mime or "").endswith("png") else "bin"
            path = os.path.join(save_dir, f"{stem}-{image_index}.{ext}")
            try:
                with open(path, "wb") as fh:
                    fh.write(base64.b64decode(data))
                entry["savedTo"] = path
                entry["savedBytes"] = os.path.getsize(path)
            except Exception as exc:  # noqa: BLE001 - report, never fail the call
                entry["saveError"] = f"{type(exc).__name__}: {exc}"
        out["content"].append(entry)
    structured = getattr(result, "structuredContent", None)
    if structured is not None:
        out["structuredContent"] = structured
    return out


async def run(args: argparse.Namespace) -> int:
    url = args.url

    # This SDK version takes a preconfigured httpx client rather than a bare
    # headers mapping, so auth and any tailnet proxy are attached there.
    http_client = _build_http_client(args.auth_key, args.tailnet_proxy, args.url)

    async with streamable_http_client(url, http_client=http_client) as streams:
        # Older SDKs yield (read, write, get_session_id); this one yields
        # (read, write). Unpack by length so either version works.
        read, write = streams[0], streams[1]
        async with ClientSession(read, write) as session:
            init = await session.initialize()
            server = getattr(init, "server_info", None) or getattr(init, "serverInfo", None)
            report: dict = {
                "url": url,
                "server": {
                    "name": getattr(server, "name", None),
                    "version": getattr(server, "version", None),
                },
                "protocolVersion": getattr(init, "protocol_version", None)
                or getattr(init, "protocolVersion", None),
            }

            if args.list_tools:
                listed = await session.list_tools()
                tools = list(getattr(listed, "tools", []) or [])
                report["toolCount"] = len(tools)
                report["tools"] = [_summarize_tool(t) for t in tools]
                print(json.dumps(report, indent=2, ensure_ascii=False))
                return 0

            if args.call:
                # The server answers an unknown tool name with a plain
                # "Unknown tool" text and isError false, so a typo would look
                # like success. Check the name against the advertised list
                # first, and fail loudly instead.
                listed = await session.list_tools()
                known = {getattr(t, "name", None) for t in (getattr(listed, "tools", []) or [])}
                if args.call not in known:
                    report["tool"] = args.call
                    report["error"] = "UNKNOWN_TOOL"
                    report["available"] = sorted(n for n in known if n)
                    print(json.dumps(report, indent=2, ensure_ascii=False))
                    return 1

                result = await session.call_tool(args.call, _resolve_args(args))
                report["tool"] = args.call
                report["result"] = _render_result(
                    result,
                    save_dir=args.save_images,
                    stem=args.call.replace("/", "_"),
                )
                print(json.dumps(report, indent=2, ensure_ascii=False))
                return 1 if report["result"]["isError"] else 0

            print(json.dumps(report, indent=2, ensure_ascii=False))
            return 0


def _describe_error(exc: BaseException, depth: int = 0) -> list[str]:
    """Flatten nested exception groups into readable lines.

    The MCP transport raises through anyio task groups, so a plain connection
    refusal arrives wrapped as "unhandled errors in a TaskGroup" and the actual
    reason is buried a level or two down. Flatten it, otherwise every network
    problem looks identical and undiagnosable.
    """
    lines = [f"{'  ' * depth}{type(exc).__name__}: {exc}"]
    if isinstance(exc, BaseExceptionGroup):
        for sub in exc.exceptions:
            lines.extend(_describe_error(sub, depth + 1))
    return lines


def _hint_for(args: argparse.Namespace, exc: BaseException) -> str | None:
    """Turn a connection failure into the one next step worth trying.

    A bare failure here is almost always the tailnet not being up, and saying so
    is more useful than the exception text.
    """
    text = " ".join(_describe_error(exc)).lower()
    is_tailnet_url = args.url.split("//", 1)[-1].split(":", 1)[0].startswith("100.")

    if "socks" in text or "proxy" in text:
        if not args.tailnet_proxy:
            return (
                "The URL looks like a tailnet address but no SOCKS5 proxy was given. "
                "Run tailscaled in userspace mode and pass "
                "--tailnet-proxy socks5://127.0.0.1:1055"
            )
        return (
            "The SOCKS5 proxy refused the connection. Check that tailscaled is "
            "running and that this node is logged in (`tailscale status`). "
            "A logged-out node accepts the proxy connection but routes nothing."
        )
    if is_tailnet_url:
        return (
            "Tailnet address unreachable. Confirm the target node is online in "
            "`tailscale status` and that its MCP server is bound to a reachable "
            "address, not just 127.0.0.1."
        )
    if "connect" in text or "refused" in text or "timeout" in text:
        return "Nothing is listening at that URL, or a firewall is dropping it."
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description="Call a winremote-mcp server on PC1")
    parser.add_argument("--url", default=os.environ.get("WINREMOTE_MCP_URL", "http://127.0.0.1:8090/mcp"))
    parser.add_argument("--auth-key", default=os.environ.get("WINREMOTE_AUTH_KEY"))
    parser.add_argument(
        "--tailnet-proxy",
        default=os.environ.get("WINREMOTE_TAILNET_PROXY"),
        help="SOCKS5 proxy for tailnet traffic, e.g. socks5://127.0.0.1:1055. "
        "Only 100.64.0.0/10 is routed through it; other traffic stays direct.",
    )
    parser.add_argument("--list-tools", action="store_true", help="List the tools the server exposes")
    parser.add_argument("--call", help="Tool name to call")
    parser.add_argument("--args", help="JSON object of tool arguments")
    parser.add_argument(
        "--args-file",
        help="Path to a file holding the JSON tool arguments. Use this instead of "
        "--args when the caller is Windows PowerShell 5.1: it strips the quotes "
        "out of an inline JSON argument before it reaches the process, so --args "
        "arrives mangled. A file survives that.",
    )
    parser.add_argument(
        "--save-images",
        default=os.environ.get("WINREMOTE_SAVE_IMAGES"),
        metavar="DIR",
        help="Write image content (e.g. a Snapshot screenshot) into DIR as PNG "
        "files and report the path of each. Without this a screenshot is "
        "reported as a byte count only, which cannot be looked at.",
    )
    args = parser.parse_args()

    if args.save_images:
        os.makedirs(args.save_images, exist_ok=True)

    try:
        return asyncio.run(run(args))
    except Exception as exc:  # noqa: BLE001 - report the failure as JSON for the caller
        print(
            json.dumps(
                {
                    "error": type(exc).__name__,
                    "detail": _describe_error(exc),
                    "hint": _hint_for(args, exc),
                },
                indent=2,
                ensure_ascii=False,
            )
        )
        return 2


if __name__ == "__main__":
    sys.exit(main())

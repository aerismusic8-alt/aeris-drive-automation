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
non-loopback address without one, so a remote URL always needs it. Over an
untrusted network put TLS in front; a bare key over plain HTTP is not enough.

Reaching a PC1 on a home LAN from an agent that is not on that LAN needs a
tunnel. This script does not create one and does not assume one exists.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys

from mcp import ClientSession
from mcp.client.streamable_http import create_mcp_http_client, streamable_http_client


def _headers(auth_key: str | None) -> dict[str, str] | None:
    if not auth_key:
        return None
    return {"Authorization": f"Bearer {auth_key}"}


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


def _render_result(result) -> dict:
    """Flatten an MCP tool result into JSON-serialisable pieces.

    Image content is reported by size rather than inlined, so a screenshot does
    not blow up a terminal or a log.
    """
    out: dict = {"isError": bool(getattr(result, "isError", False)), "content": []}
    for item in getattr(result, "content", []) or []:
        item_type = getattr(item, "type", None)
        if item_type == "text":
            out["content"].append({"type": "text", "text": getattr(item, "text", "")})
        elif item_type == "image":
            data = getattr(item, "data", "") or ""
            out["content"].append(
                {
                    "type": "image",
                    "mimeType": getattr(item, "mimeType", None),
                    "base64Length": len(data),
                }
            )
        else:
            out["content"].append({"type": str(item_type), "raw": str(item)[:400]})
    structured = getattr(result, "structuredContent", None)
    if structured is not None:
        out["structuredContent"] = structured
    return out


async def run(args: argparse.Namespace) -> int:
    url = args.url
    headers = _headers(args.auth_key)

    # This SDK version takes a preconfigured httpx client rather than a bare
    # headers mapping, so the Authorization header is attached here.
    http_client = create_mcp_http_client(headers=headers) if headers else None

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

                result = await session.call_tool(args.call, _parse_args(args.args))
                report["tool"] = args.call
                report["result"] = _render_result(result)
                print(json.dumps(report, indent=2, ensure_ascii=False))
                return 1 if report["result"]["isError"] else 0

            print(json.dumps(report, indent=2, ensure_ascii=False))
            return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Call a winremote-mcp server on PC1")
    parser.add_argument("--url", default=os.environ.get("WINREMOTE_MCP_URL", "http://127.0.0.1:8090/mcp"))
    parser.add_argument("--auth-key", default=os.environ.get("WINREMOTE_AUTH_KEY"))
    parser.add_argument("--list-tools", action="store_true", help="List the tools the server exposes")
    parser.add_argument("--call", help="Tool name to call")
    parser.add_argument("--args", help="JSON object of tool arguments")
    args = parser.parse_args()

    try:
        return asyncio.run(run(args))
    except Exception as exc:  # noqa: BLE001 - report the failure as JSON for the caller
        print(json.dumps({"error": type(exc).__name__, "detail": str(exc)[:500]}))
        return 2


if __name__ == "__main__":
    sys.exit(main())

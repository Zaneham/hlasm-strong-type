#!/usr/bin/env python3
"""Test harness for hlasm-lsp: references and macro go-to-definition."""

import subprocess
import json
import sys
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(SCRIPT_DIR)
SERVER = os.path.join(ROOT_DIR, "_build", "default", "bin", "main.exe")
DATA_DIR = os.path.join(ROOT_DIR, "data")
MACRO_DIR = os.path.join(ROOT_DIR, "resources", "bixoft-macros")
TEST_FILE = os.path.join(SCRIPT_DIR, "test_register.asm")
TEST_URI = "file:///test/test_register.asm"

passed = 0
failed = 0


def read_message(proc):
    """Read one JSON-RPC message from the server."""
    headers = {}
    guard = 0
    while guard < 64:
        guard += 1
        line = b""
        while True:
            c = proc.stdout.read(1)
            if not c:
                return None
            if c == b"\n":
                break
            line += c
        text = line.decode().strip()
        if text == "":
            break
        if ":" in text:
            key, val = text.split(":", 1)
            headers[key.strip().lower()] = val.strip()
    length = int(headers.get("content-length", 0))
    if length <= 0:
        return None
    body = proc.stdout.read(length)
    return json.loads(body)


def send_message(proc, msg):
    """Send a JSON-RPC message to the server."""
    body = json.dumps(msg)
    header = f"Content-Length: {len(body)}\r\n\r\n"
    proc.stdin.write(header.encode())
    proc.stdin.write(body.encode())
    proc.stdin.flush()


def send_request(proc, rid, method, params=None):
    msg = {"jsonrpc": "2.0", "id": rid, "method": method}
    if params is not None:
        msg["params"] = params
    send_message(proc, msg)


def send_notification(proc, method, params=None):
    msg = {"jsonrpc": "2.0", "method": method}
    if params is not None:
        msg["params"] = params
    send_message(proc, msg)


def read_response(proc, expected_id):
    """Read messages until we get the response with the expected id."""
    guard = 0
    while guard < 32:
        guard += 1
        msg = read_message(proc)
        if msg is None:
            return None
        if "id" in msg and msg["id"] == expected_id:
            return msg
    return None


def check(name, condition, detail=""):
    global passed, failed
    if condition:
        print(f"  PASS: {name}")
        passed += 1
    else:
        print(f"  FAIL: {name} -- {detail}")
        failed += 1


def main():
    global passed, failed

    if not os.path.exists(SERVER):
        print(f"Server not found at {SERVER}")
        print("Run: opam exec -- dune build")
        return 1

    with open(TEST_FILE, "r") as f:
        test_text = f.read()

    proc = subprocess.Popen(
        [SERVER, "--data-dir", DATA_DIR, "--macro-dir", MACRO_DIR],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        bufsize=0,
    )

    try:
        # ---- Initialize ----
        print("=== Initialize ===")
        send_request(proc, 1, "initialize", {
            "processId": os.getpid(),
            "capabilities": {},
            "rootUri": "file:///test",
        })
        resp = read_response(proc, 1)
        check("initialize response received", resp is not None)

        caps = resp["result"]["capabilities"]
        check("referencesProvider advertised",
              caps.get("referencesProvider") is True,
              f"got: {caps.get('referencesProvider')}")
        check("definitionProvider advertised",
              caps.get("definitionProvider") is True)

        send_notification(proc, "initialized", {})

        # ---- Open document ----
        print("\n=== Open Document ===")
        send_notification(proc, "textDocument/didOpen", {
            "textDocument": {
                "uri": TEST_URI,
                "languageId": "hlasm",
                "version": 1,
                "text": test_text,
            }
        })

        # Server publishes diagnostics after didOpen
        diag_msg = read_message(proc)
        check("diagnostics published",
              diag_msg is not None
              and diag_msg.get("method") == "textDocument/publishDiagnostics")
        if diag_msg:
            diags = diag_msg["params"]["diagnostics"]
            check("type mismatch diagnostics present", len(diags) >= 2,
                  f"got {len(diags)} diagnostics")

        # ---- References: WORK (with declaration) ----
        # Line 8 (0-indexed): "WORK     EQUREG R3,G"
        # Expected: line 8 (decl), 17 (LR), 22 (LE), 32 (BCT)
        print("\n=== References (WORK, includeDeclaration=true) ===")
        send_request(proc, 2, "textDocument/references", {
            "textDocument": {"uri": TEST_URI},
            "position": {"line": 8, "character": 0},
            "context": {"includeDeclaration": True},
        })
        resp = read_response(proc, 2)
        check("references response received", resp is not None)

        if resp and resp.get("result"):
            refs = resp["result"]
            ref_lines = sorted([r["range"]["start"]["line"] for r in refs])
            check("found 4 references to WORK",
                  len(refs) == 4,
                  f"got {len(refs)}: lines {ref_lines}")
            check("includes declaration (line 8)",
                  8 in ref_lines, f"lines: {ref_lines}")
            check("includes LR usage (line 17)",
                  17 in ref_lines, f"lines: {ref_lines}")
            check("includes LE usage (line 22)",
                  22 in ref_lines, f"lines: {ref_lines}")
            check("includes BCT usage (line 32)",
                  32 in ref_lines, f"lines: {ref_lines}")
        else:
            check("references returned results", False, f"got: {resp}")

        # ---- References: WORK (without declaration) ----
        print("\n=== References (WORK, includeDeclaration=false) ===")
        send_request(proc, 3, "textDocument/references", {
            "textDocument": {"uri": TEST_URI},
            "position": {"line": 8, "character": 0},
            "context": {"includeDeclaration": False},
        })
        resp = read_response(proc, 3)
        check("references response received", resp is not None)

        if resp and resp.get("result"):
            refs = resp["result"]
            ref_lines = sorted([r["range"]["start"]["line"] for r in refs])
            check("found 3 references (no declaration)",
                  len(refs) == 3,
                  f"got {len(refs)}: lines {ref_lines}")
            check("declaration NOT included",
                  8 not in ref_lines, f"lines: {ref_lines}")
        else:
            check("references returned results", False, f"got: {resp}")

        # ---- References: LOOP label ----
        # Line 31: "LOOP     DS    0H"
        # Line 32: "         BCT   WORK,LOOP"
        print("\n=== References (LOOP label) ===")
        send_request(proc, 4, "textDocument/references", {
            "textDocument": {"uri": TEST_URI},
            "position": {"line": 31, "character": 0},
            "context": {"includeDeclaration": True},
        })
        resp = read_response(proc, 4)
        check("references response received", resp is not None)

        if resp and resp.get("result"):
            refs = resp["result"]
            ref_lines = sorted([r["range"]["start"]["line"] for r in refs])
            check("found 2 references to LOOP (decl + BCT operand)",
                  len(refs) == 2,
                  f"got {len(refs)}: lines {ref_lines}")
        else:
            check("references returned results", False, f"got: {resp}")

        # ---- References: EXIT label ----
        # Line 33: "         B     EXIT"
        # Line 34: "EXIT     DS    0H"
        print("\n=== References (EXIT label) ===")
        send_request(proc, 5, "textDocument/references", {
            "textDocument": {"uri": TEST_URI},
            "position": {"line": 34, "character": 0},
            "context": {"includeDeclaration": True},
        })
        resp = read_response(proc, 5)
        check("references response received", resp is not None)

        if resp and resp.get("result"):
            refs = resp["result"]
            ref_lines = sorted([r["range"]["start"]["line"] for r in refs])
            check("found 2 references to EXIT (B + decl)",
                  len(refs) == 2,
                  f"got {len(refs)}: lines {ref_lines}")
        else:
            check("references returned results", False, f"got: {resp}")

        # ---- Definition: EQUREG macro ----
        # Line 8, char 9: "WORK     EQUREG R3,G"
        #                           ^ char 9
        print("\n=== Definition (EQUREG macro -> .mac file) ===")
        send_request(proc, 6, "textDocument/definition", {
            "textDocument": {"uri": TEST_URI},
            "position": {"line": 8, "character": 9},
        })
        resp = read_response(proc, 6)
        check("definition response received", resp is not None)

        if resp and resp.get("result"):
            locs = resp["result"]
            if isinstance(locs, list) and len(locs) > 0:
                loc_uri = locs[0]["uri"]
                check("definition points to EQUREG.mac",
                      "EQUREG" in loc_uri and ".mac" in loc_uri,
                      f"got uri: {loc_uri}")
            else:
                check("definition returned a location", False, f"got: {locs}")
        else:
            check("definition returned results", False, f"got: {resp}")

        # ---- Definition: label (existing feature, regression test) ----
        # Line 32, char 20: "         BCT   WORK,LOOP"
        #                                        ^ char 20
        print("\n=== Definition (LOOP label, regression) ===")
        send_request(proc, 7, "textDocument/definition", {
            "textDocument": {"uri": TEST_URI},
            "position": {"line": 32, "character": 20},
        })
        resp = read_response(proc, 7)
        check("definition response received", resp is not None)

        if resp and resp.get("result"):
            locs = resp["result"]
            if isinstance(locs, list) and len(locs) > 0:
                def_line = locs[0]["range"]["start"]["line"]
                check("definition points to LOOP label (line 31)",
                      def_line == 31,
                      f"got line: {def_line}")
            else:
                check("definition returned a location", False, f"got: {locs}")
        else:
            check("definition returned results", False, f"got: {resp}")

        # ---- Definition: EQUREG register (existing feature, regression) ----
        # Line 16, char 15: "         LA    BASE,0"
        #                                 ^ char 15 (B of BASE)
        # Wait, line 16 is "         LA    BASE,0"
        # 0-8: spaces, 9:L, 10:A, 11-14: spaces, 15:B
        print("\n=== Definition (BASE register, regression) ===")
        send_request(proc, 8, "textDocument/definition", {
            "textDocument": {"uri": TEST_URI},
            "position": {"line": 16, "character": 15},
        })
        resp = read_response(proc, 8)
        check("definition response received", resp is not None)

        if resp and resp.get("result"):
            locs = resp["result"]
            if isinstance(locs, list) and len(locs) > 0:
                def_line = locs[0]["range"]["start"]["line"]
                check("definition points to BASE EQUREG (line 7)",
                      def_line == 7,
                      f"got line: {def_line}")
            else:
                check("definition returned a location", False, f"got: {locs}")
        else:
            check("definition returned results", False, f"got: {resp}")

        # ---- Shutdown ----
        print("\n=== Shutdown ===")
        send_request(proc, 9, "shutdown", None)
        resp = read_response(proc, 9)
        check("shutdown acknowledged", resp is not None)

        send_notification(proc, "exit", None)
        proc.wait(timeout=5)
        check("server exited cleanly", proc.returncode == 0,
              f"exit code: {proc.returncode}")

    except Exception as e:
        print(f"\n  ERROR: {e}")
        import traceback
        traceback.print_exc()
        failed += 1
        proc.kill()

    print(f"\n{'='*50}")
    print(f"Results: {passed} passed, {failed} failed")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())

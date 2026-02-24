#!/usr/bin/env python3
"""Headless test harness for hlasm-lsp."""

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
next_id = 1


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


def req_id():
    global next_id
    rid = next_id
    next_id += 1
    return rid


def hover_at(proc, uri, line, char):
    """Send hover request, return markdown value or None."""
    rid = req_id()
    send_request(proc, rid, "textDocument/hover", {
        "textDocument": {"uri": uri},
        "position": {"line": line, "character": char},
    })
    resp = read_response(proc, rid)
    if resp and resp.get("result"):
        return resp["result"]["contents"]["value"]
    return None


def complete_at(proc, uri, line, char):
    """Send completion request, return list of item labels."""
    rid = req_id()
    send_request(proc, rid, "textDocument/completion", {
        "textDocument": {"uri": uri},
        "position": {"line": line, "character": char},
    })
    resp = read_response(proc, rid)
    if resp and resp.get("result") and "items" in resp["result"]:
        return [it["label"] for it in resp["result"]["items"]]
    return []


def refs_at(proc, uri, line, char, include_decl=True):
    """Send references request, return list of line numbers."""
    rid = req_id()
    send_request(proc, rid, "textDocument/references", {
        "textDocument": {"uri": uri},
        "position": {"line": line, "character": char},
        "context": {"includeDeclaration": include_decl},
    })
    resp = read_response(proc, rid)
    if resp and resp.get("result"):
        return sorted([r["range"]["start"]["line"] for r in resp["result"]])
    return []


def defn_at(proc, uri, line, char):
    """Send definition request, return (uri, line) or None."""
    rid = req_id()
    send_request(proc, rid, "textDocument/definition", {
        "textDocument": {"uri": uri},
        "position": {"line": line, "character": char},
    })
    resp = read_response(proc, rid)
    if resp and resp.get("result"):
        locs = resp["result"]
        if isinstance(locs, list) and len(locs) > 0:
            return (locs[0]["uri"], locs[0]["range"]["start"]["line"])
    return None


def open_doc(proc, uri, text):
    """Open a document and consume the diagnostics notification."""
    send_notification(proc, "textDocument/didOpen", {
        "textDocument": {
            "uri": uri,
            "languageId": "hlasm",
            "version": 1,
            "text": text,
        }
    })
    return read_message(proc)  # diagnostics


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
        # ============================================================
        print("=== Initialize ===")
        # ============================================================
        rid = req_id()
        send_request(proc, rid, "initialize", {
            "processId": os.getpid(),
            "capabilities": {},
            "rootUri": "file:///test",
        })
        resp = read_response(proc, rid)
        check("initialize response received", resp is not None)

        caps = resp["result"]["capabilities"]
        check("hoverProvider advertised", caps.get("hoverProvider") is True)
        check("completionProvider advertised", caps.get("completionProvider") is not None)
        check("definitionProvider advertised", caps.get("definitionProvider") is True)
        check("referencesProvider advertised", caps.get("referencesProvider") is True)

        send_notification(proc, "initialized", {})

        # ============================================================
        print("\n=== Open Document ===")
        # ============================================================
        diag_msg = open_doc(proc, TEST_URI, test_text)
        check("diagnostics published",
              diag_msg is not None
              and diag_msg.get("method") == "textDocument/publishDiagnostics")

        # ============================================================
        print("\n=== Diagnostics ===")
        # ============================================================
        # test_register.asm lines (0-indexed):
        #   22: "         LE    WORK,=E'1.0'"  -> WORK is general, LE wants float
        #   23: "         LA    FPR,0"          -> FPR is float, LA wants general/address
        diags = diag_msg["params"]["diagnostics"]
        check("exactly 2 diagnostics", len(diags) == 2,
              f"got {len(diags)}")

        diag_lines = sorted([d["range"]["start"]["line"] for d in diags])
        check("diagnostic on line 22 (LE WORK)", 22 in diag_lines,
              f"lines: {diag_lines}")
        check("diagnostic on line 23 (LA FPR)", 23 in diag_lines,
              f"lines: {diag_lines}")

        # Check messages
        for d in diags:
            msg = d["message"]
            if d["range"]["start"]["line"] == 22:
                check("line 22: warns about general in float instr",
                      "general" in msg.lower() and "float" in msg.lower(),
                      f"msg: {msg}")
            elif d["range"]["start"]["line"] == 23:
                check("line 23: warns about float in address instr",
                      "float" in msg.lower(),
                      f"msg: {msg}")

        # Check severity (should be warnings, not errors)
        for d in diags:
            check(f"line {d['range']['start']['line']} is a warning",
                  d["severity"] == 2,  # 2 = Warning in LSP
                  f"got severity: {d['severity']}")

        # ============================================================
        print("\n=== Hover: macro (EQUREG) ===")
        # ============================================================
        # Line 8, char 9: "WORK     EQUREG R3,G"
        md = hover_at(proc, TEST_URI, 8, 9)
        check("hover returns content", md is not None)
        check("hover mentions EQUREG", md is not None and "EQUREG" in md)
        check("hover has description",
              md is not None and "type" in md.lower())

        # ============================================================
        print("\n=== Hover: bare register (R12) ===")
        # ============================================================
        # Line 7, char 16: "BASE     EQUREG R12,A"
        md = hover_at(proc, TEST_URI, 7, 16)
        check("hover returns content", md is not None)
        check("hover shows R12 info",
              md is not None and "R12" in md)
        check("hover mentions base register",
              md is not None and "Base register" in md)

        # ============================================================
        print("\n=== Hover: EQUREG register (BASE) ===")
        # ============================================================
        # Line 16, char 15: "         LA    BASE,0"
        md = hover_at(proc, TEST_URI, 16, 15)
        check("hover returns content", md is not None)
        check("hover shows EQUREG info",
              md is not None and "EQUREG" in md)
        check("hover shows Address type",
              md is not None and "Address" in md)
        check("hover shows register number",
              md is not None and "R12" in md)

        # ============================================================
        print("\n=== Hover: control block field (TCBTID) ===")
        # ============================================================
        cb_uri = "file:///test/cb_test.asm"
        cb_text = "         L     R5,TCBTID\n"
        open_doc(proc, cb_uri, cb_text)
        # TCBTID starts at char 18
        md = hover_at(proc, cb_uri, 0, 18)
        check("hover returns content", md is not None)
        check("hover shows field name",
              md is not None and "TCBTID" in md)
        check("hover shows control block (TCB)",
              md is not None and "TCB" in md)

        # ============================================================
        print("\n=== Hover: no result on whitespace ===")
        # ============================================================
        md = hover_at(proc, TEST_URI, 0, 0)
        check("hover on comment returns nothing", md is None)

        # ============================================================
        print("\n=== Completion: at instruction position ===")
        # ============================================================
        # Line 17, char 15: "         LR    WORK,R2"
        #                                 ^ on WORK, should get completions
        items = complete_at(proc, TEST_URI, 17, 15)
        check("completion returns items", len(items) > 0,
              f"got {len(items)}")
        check("completion includes WORK label",
              "WORK" in items, f"not in {items[:10]}")

        # ============================================================
        print("\n=== Completion: prefix filtering ===")
        # ============================================================
        # Open a doc with partial text "EQU" to test prefix matching
        pfx_uri = "file:///test/pfx_test.asm"
        pfx_text = "         EQU\n"
        open_doc(proc, pfx_uri, pfx_text)
        # char 11 = 'U' in EQU
        items = complete_at(proc, pfx_uri, 0, 11)
        check("prefix 'EQU' returns results", len(items) > 0)
        check("EQUREG in prefix results",
              "EQUREG" in items, f"items: {items[:10]}")
        check("EQU in prefix results",
              "EQU" in items, f"items: {items[:10]}")
        # Make sure non-matching items are filtered
        check("non-matching items filtered out",
              "LA" not in items and "LR" not in items,
              f"found LA or LR in: {items[:10]}")

        # ============================================================
        print("\n=== Completion: includes macros ===")
        # ============================================================
        mac_uri = "file:///test/mac_test.asm"
        mac_text = "         IF\n"
        open_doc(proc, mac_uri, mac_text)
        items = complete_at(proc, mac_uri, 0, 10)
        check("IF prefix returns results", len(items) > 0)
        check("IF macro in results",
              "IF" in items, f"items: {items[:10]}")

        # ============================================================
        print("\n=== References: WORK (with declaration) ===")
        # ============================================================
        ref_lines = refs_at(proc, TEST_URI, 8, 0, include_decl=True)
        check("found 4 references to WORK",
              len(ref_lines) == 4,
              f"got {len(ref_lines)}: {ref_lines}")
        check("includes declaration (line 8)", 8 in ref_lines)
        check("includes LR usage (line 17)", 17 in ref_lines)
        check("includes LE usage (line 22)", 22 in ref_lines)
        check("includes BCT usage (line 32)", 32 in ref_lines)

        # ============================================================
        print("\n=== References: WORK (without declaration) ===")
        # ============================================================
        ref_lines = refs_at(proc, TEST_URI, 8, 0, include_decl=False)
        check("found 3 references (no declaration)",
              len(ref_lines) == 3,
              f"got {len(ref_lines)}: {ref_lines}")
        check("declaration NOT included", 8 not in ref_lines)

        # ============================================================
        print("\n=== References: LOOP label ===")
        # ============================================================
        ref_lines = refs_at(proc, TEST_URI, 31, 0, include_decl=True)
        check("found 2 references to LOOP",
              len(ref_lines) == 2,
              f"got {len(ref_lines)}: {ref_lines}")

        # ============================================================
        print("\n=== References: EXIT label ===")
        # ============================================================
        ref_lines = refs_at(proc, TEST_URI, 34, 0, include_decl=True)
        check("found 2 references to EXIT",
              len(ref_lines) == 2,
              f"got {len(ref_lines)}: {ref_lines}")

        # ============================================================
        print("\n=== Definition: EQUREG macro -> .mac file ===")
        # ============================================================
        result = defn_at(proc, TEST_URI, 8, 9)
        check("definition returned", result is not None)
        if result:
            check("points to EQUREG.mac",
                  "EQUREG" in result[0] and ".mac" in result[0],
                  f"got: {result[0]}")

        # ============================================================
        print("\n=== Definition: LOOP label ===")
        # ============================================================
        # char 20 in "         BCT   WORK,LOOP"
        result = defn_at(proc, TEST_URI, 32, 20)
        check("definition returned", result is not None)
        if result:
            check("points to line 31", result[1] == 31,
                  f"got line: {result[1]}")

        # ============================================================
        print("\n=== Definition: BASE register ===")
        # ============================================================
        result = defn_at(proc, TEST_URI, 16, 15)
        check("definition returned", result is not None)
        if result:
            check("points to line 7", result[1] == 7,
                  f"got line: {result[1]}")

        # ============================================================
        print("\n=== Definition: unknown symbol returns null ===")
        # ============================================================
        result = defn_at(proc, TEST_URI, 27, 15)
        # Line 27: "         LR    MYSTERY,R5" -> MYSTERY is undeclared
        check("no definition for unknown symbol", result is None,
              f"got: {result}")

        # ============================================================
        print("\n=== Shutdown ===")
        # ============================================================
        rid = req_id()
        send_request(proc, rid, "shutdown")
        resp = read_response(proc, rid)
        check("shutdown acknowledged", resp is not None)

        send_notification(proc, "exit")
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

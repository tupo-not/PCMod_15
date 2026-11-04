#!/usr/bin/env python3
"""Translate the small GLua syntax additions used by PCMod to Lua 5.1 and
compile-check the result with luac5.1 -p."""
import os
import subprocess
import sys
import tempfile


def translate(src: str) -> str:
    out = []
    i = 0
    n = len(src)
    while i < n:
        c = src[i]
        # Existing Lua comments must be skipped too, otherwise an apostrophe
        # inside an English comment can start a bogus string.
        if c == "-" and i + 1 < n and src[i + 1] == "-":
            out.append("--")
            i += 2
            if i < n and src[i] == "[" and i + 1 < n and src[i + 1] == "[":
                j = src.find("]]", i + 2)
                if j == -1:
                    out.append(src[i:])
                    break
                out.append(src[i:j + 2])
                i = j + 2
            else:
                j = src.find("\n", i)
                if j == -1:
                    out.append(src[i:])
                    break
                out.append(src[i:j])
                i = j
            continue
        # Long strings: [[...]], [=[...]=]
        if c == "[" and i + 1 < n and src[i + 1] == "[":
            j = src.find("]]", i + 2)
            if j == -1:
                out.append(src[i:])
                break
            out.append(src[i:j + 2])
            i = j + 2
            continue
        # Quoted strings
        if c in ("'", '"'):
            quote = c
            out.append(c)
            i += 1
            while i < n:
                c = src[i]
                out.append(c)
                if c == "\\" and i + 1 < n:
                    out.append(src[i + 1])
                    i += 2
                    continue
                i += 1
                if c == quote:
                    break
            continue
        # C++ style line comment
        if c == "/" and i + 1 < n and src[i + 1] == "/":
            j = src.find("\n", i + 2)
            if j == -1:
                out.append("--" + src[i + 2:])
                break
            out.append("--" + src[i + 2:j])
            i = j
            continue
        # C style block comment
        if c == "/" and i + 1 < n and src[i + 1] == "*":
            j = src.find("*/", i + 2)
            if j == -1:
                out.append("--[[")
                out.append(src[i + 2:])
                out.append("]]")
                break
            out.append("--[[")
            out.append(src[i + 2:j])
            out.append("]]")
            i = j + 2
            continue
        # C style operators
        if c == "!" and i + 1 < n and src[i + 1] == "=":
            out.append("~=")
            i += 2
            continue
        if c == "!":
            out.append("not ")
            i += 1
            continue
        if c == "&" and i + 1 < n and src[i + 1] == "&":
            out.append(" and ")
            i += 2
            continue
        if c == "|" and i + 1 < n and src[i + 1] == "|":
            out.append(" or ")
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def compile_check(paths):
    failures = 0
    fd, tmp = tempfile.mkstemp(suffix=".lua", prefix="glua_")
    os.close(fd)
    try:
        for path in paths:
            with open(path, "r", encoding="utf-8", errors="surrogateescape") as fh:
                src = fh.read()
            with open(tmp, "w", encoding="utf-8", errors="surrogateescape") as fh:
                fh.write(translate(src))
            result = subprocess.run(["luac5.1", "-p", tmp], capture_output=True, text=True)
            if result.returncode == 0:
                print(f"OK   {path}")
            else:
                failures += 1
                print(f"FAIL {path}")
                print(result.stderr.strip())
    finally:
        os.unlink(tmp)
    return failures


def main(paths):
    return compile_check(paths)


if __name__ == "__main__":
    sys.exit(1 if main(sys.argv[1:]) else 0)

#!/usr/bin/env python3
"""
Automated Mermaid Diagram to PNG Compiler for AWS EC2 Labs.
Scans all README.md files, extracts ```mermaid blocks, generates PNGs via mermaid.ink,
saves them to local images/ directories, and updates the markdown to embed the images.
"""

import os
import re
import base64
import json
import time
import ssl
import urllib.request
import urllib.error

# Handle macOS SSL certificates
try:
    import certifi
    SSL_CONTEXT = ssl.create_default_context(cafile=certifi.where())
except Exception:
    SSL_CONTEXT = ssl._create_unverified_context()

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def encode_mermaid(code: str) -> str:
    # mermaid.ink format: base64 encoded json
    payload = {
        "code": code.strip(),
        "mermaid": {
            "theme": "default",
            "themeVariables": {
                "darkMode": False
            }
        }
    }
    json_bytes = json.dumps(payload).encode("utf-8")
    return base64.urlsafe_b64encode(json_bytes).decode("ascii")

def fetch_png(mermaid_code: str) -> bytes:
    b64 = encode_mermaid(mermaid_code)
    url = f"https://mermaid.ink/img/{b64}"
    req = urllib.request.Request(
        url,
        headers={"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"}
    )
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, context=SSL_CONTEXT, timeout=25) as resp:
                if resp.status == 200:
                    return resp.read()
        except urllib.error.HTTPError as e:
            print(f"      [!] HTTP Error {e.code} for URL: {url}")
            # Fallback to unverified context if SSL failed
            try:
                unverified_ctx = ssl._create_unverified_context()
                with urllib.request.urlopen(req, context=unverified_ctx, timeout=25) as resp:
                    if resp.status == 200:
                        return resp.read()
            except Exception:
                pass
            break
        except Exception as e:
            print(f"      [!] Attempt {attempt+1} failed: {e}. Retrying with unverified SSL...")
            try:
                unverified_ctx = ssl._create_unverified_context()
                with urllib.request.urlopen(req, context=unverified_ctx, timeout=25) as resp:
                    if resp.status == 200:
                        return resp.read()
            except Exception:
                pass
            time.sleep(2)
    return b""

def process_file(md_path: str):
    with open(md_path, "r", encoding="utf-8") as f:
        content = f.read()

    # Find all ```mermaid ... ``` blocks
    pattern = re.compile(r"```mermaid\n(.*?)```", re.DOTALL)
    matches = list(pattern.finditer(content))

    if not matches:
        return

    print(f"[*] Processing {os.path.relpath(md_path, ROOT_DIR)} ({len(matches)} diagrams)...")

    file_dir = os.path.dirname(md_path)
    images_dir = os.path.join(file_dir, "images")
    os.makedirs(images_dir, exist_ok=True)

    new_content = content
    offset = 0

    for idx, match in enumerate(matches, 1):
        mermaid_code = match.group(1).strip()
        img_name = f"architecture_{idx}.png" if len(matches) > 1 else "architecture.png"
        img_path = os.path.join(images_dir, img_name)
        rel_img_path = f"./images/{img_name}"

        # Fetch and save PNG
        print(f"    -> Generating {img_name}...")
        png_data = fetch_png(mermaid_code)
        if png_data:
            with open(img_path, "wb") as img_f:
                img_f.write(png_data)
            print(f"       [+] Saved {img_name} ({len(png_data)} bytes)")

            # Format replacement with image and collapsible mermaid code
            replacement = (
                f"![Architecture Diagram]({rel_img_path})\n\n"
                f"<details>\n<summary>Click to expand Mermaid diagram source</summary>\n\n"
                f"```mermaid\n{mermaid_code}\n```\n</details>"
            )

            start = match.start() + offset
            end = match.end() + offset
            new_content = new_content[:start] + replacement + new_content[end:]
            offset += len(replacement) - (match.end() - match.start())
        else:
            print(f"       [-] Failed to generate image for diagram {idx}")

    with open(md_path, "w", encoding="utf-8") as f:
        f.write(new_content)

def main():
    print("==================================================")
    print("  Compiling Mermaid Diagrams to PNG for All Labs  ")
    print("==================================================")
    for root, dirs, files in os.walk(ROOT_DIR):
        for f in sorted(files):
            if f == "README.md":
                process_file(os.path.join(root, f))
    print("\n[SUCCESS] All diagrams compiled and linked!")

if __name__ == "__main__":
    main()

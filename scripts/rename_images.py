#!/usr/bin/env python3
"""
Renames all architecture diagram images by appending lab names and counters.
Example: architecture.png in lab-01 -> architecture-lab-01.png
Updates all README.md files accordingly.
"""

import os
import re

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def rename_and_update():
    print("==================================================")
    print("  Renaming Diagram Images with Lab Names & Numbers")
    print("==================================================")

    # 1. Handle root README.md and root images/architecture.png
    root_img_old = os.path.join(ROOT_DIR, "images", "architecture.png")
    root_img_new = os.path.join(ROOT_DIR, "images", "architecture-overview.png")
    if os.path.exists(root_img_old):
        os.rename(root_img_old, root_img_new)
        print(f"[+] Renamed root image -> images/architecture-overview.png")
        root_md = os.path.join(ROOT_DIR, "README.md")
        if os.path.exists(root_md):
            with open(root_md, "r", encoding="utf-8") as f:
                c = f.read()
            c = c.replace("./images/architecture.png", "./images/architecture-overview.png")
            with open(root_md, "w", encoding="utf-8") as f:
                f.write(c)

    # 2. Iterate through modules and labs
    for dirpath, dirnames, filenames in os.walk(ROOT_DIR):
        if os.path.basename(dirpath) == "images":
            lab_dir = os.path.dirname(dirpath)
            lab_name = os.path.basename(lab_dir)

            # Match lab-XX from directory name
            match = re.search(r"(lab-\d+)", lab_name)
            if not match:
                continue

            lab_tag = match.group(1) # e.g. "lab-01"
            readme_path = os.path.join(lab_dir, "README.md")
            readme_content = ""
            if os.path.exists(readme_path):
                with open(readme_path, "r", encoding="utf-8") as f:
                    readme_content = f.read()

            # Single image case: architecture.png -> architecture-lab-XX.png
            if "architecture.png" in filenames:
                old_file = os.path.join(dirpath, "architecture.png")
                new_file_name = f"architecture-{lab_tag}.png"
                new_file = os.path.join(dirpath, new_file_name)
                os.rename(old_file, new_file)
                print(f"[+] {lab_name}: architecture.png -> {new_file_name}")

                if readme_content:
                    readme_content = readme_content.replace(
                        "./images/architecture.png", f"./images/{new_file_name}"
                    )

            # Multiple images case: architecture_1.png, architecture_2.png, ...
            multi_files = sorted([f for f in filenames if re.match(r"architecture_\d+\.png", f)])
            for f_name in multi_files:
                sub_idx = re.search(r"architecture_(\d+)\.png", f_name).group(1)
                old_file = os.path.join(dirpath, f_name)
                new_file_name = f"architecture-{lab_tag}-{sub_idx}.png"
                new_file = os.path.join(dirpath, new_file_name)
                os.rename(old_file, new_file)
                print(f"[+] {lab_name}: {f_name} -> {new_file_name}")

                if readme_content:
                    readme_content = readme_content.replace(
                        f"./images/{f_name}", f"./images/{new_file_name}"
                    )

            if readme_content:
                with open(readme_path, "w", encoding="utf-8") as f:
                    f.write(readme_content)

    print("\n[SUCCESS] Local image renaming and markdown updates complete!")

if __name__ == "__main__":
    rename_and_update()

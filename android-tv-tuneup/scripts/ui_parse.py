"""Summarise a uiautomator XML dump: visible texts, focused row, toggle states.

Usage: python3 -I ui_parse.py ui.xml
"""
import sys
import xml.etree.ElementTree as ET


def texts(node):
    return [n.get("text") for n in node.iter("node") if n.get("text")]


def main(path):
    root = ET.parse(path).getroot()
    activity_pkgs = {n.get("package") for n in root.iter("node") if n.get("package")}
    print("packages on screen:", ", ".join(sorted(activity_pkgs)))
    for n in root.iter("node"):
        t = n.get("text") or ""
        desc = n.get("content-desc") or ""
        rid = (n.get("resource-id") or "").split("/")[-1]
        if n.get("focused") == "true":
            print(f">> FOCUSED: {texts(n)[:3]} {n.get('bounds')}")
        if t or desc:
            label = t or f"[desc] {desc}"
            print(f"{label[:90]!r} id={rid} {n.get('bounds')}")
        if n.get("checkable") == "true":
            print(f"   toggle checked={n.get('checked')} {n.get('bounds')}")


if __name__ == "__main__":
    main(sys.argv[1])

#!/usr/bin/env python3
"""
Post-xcodegen fix: link local Swift package product dependencies to their
XCLocalSwiftPackageReference objects.

xcodegen (2.45.x) emits XCSwiftPackageProductDependency entries for LOCAL
packages WITHOUT the `package = <ref>` line. The command-line build tolerates
this, but Xcode's IDE reports "Missing package product 'MoonlitCore' / 'MPVKit'".

Run this after every `xcodegen generate`:
    xcodegen generate && python3 Scripts/fix-local-package-refs.py

It is idempotent and only touches product dependencies whose productName maps
to a known local package reference.
"""
import re
import sys
from pathlib import Path

PBXPROJ = Path(__file__).resolve().parent.parent / "MoonlitMac.xcodeproj" / "project.pbxproj"

def main() -> int:
    text = PBXPROJ.read_text()

    # Map: local package productName -> its XCLocalSwiftPackageReference object id
    # Discover ids from the XCLocalSwiftPackageReference section by relativePath.
    local_refs = {}
    for m in re.finditer(
        r'([0-9A-F]{24}) /\* XCLocalSwiftPackageReference "([^"]+)" \*/ = \{',
        text,
    ):
        ref_id, rel = m.group(1), m.group(2)
        # productName is the last path component (MoonlitCore, MPVKit)
        product = rel.rstrip("/").split("/")[-1]
        local_refs[product] = ref_id

    if not local_refs:
        print("fix-local-package-refs: no local package references found; nothing to do")
        return 0

    changed = 0

    def add_package(match: "re.Match[str]") -> str:
        nonlocal changed
        block = match.group(0)
        product = match.group("product")
        if product not in local_refs:
            return block
        if "package = " in block:
            return block  # already linked (idempotent)
        ref_id = local_refs[product]
        insert = f"\t\t\tpackage = {ref_id} /* XCLocalSwiftPackageReference */;\n"
        # insert the package line right after the isa line
        new_block = block.replace(
            "isa = XCSwiftPackageProductDependency;\n",
            "isa = XCSwiftPackageProductDependency;\n" + insert,
            1,
        )
        changed += 1
        return new_block

    pattern = re.compile(
        r"[0-9A-F]{24} /\* [^*]+ \*/ = \{\s*"
        r"isa = XCSwiftPackageProductDependency;\s*"
        r"(?:package = [^;]+;\s*)?"
        r"productName = (?P<product>[A-Za-z0-9_]+);\s*\};",
    )
    text = pattern.sub(add_package, text)

    if changed:
        PBXPROJ.write_text(text)
        print(f"fix-local-package-refs: linked {changed} local package product(s): "
              + ", ".join(sorted(local_refs)))
    else:
        print("fix-local-package-refs: local package products already linked")
    return 0

if __name__ == "__main__":
    sys.exit(main())

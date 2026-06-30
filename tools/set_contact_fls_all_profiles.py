from pathlib import Path
import json
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
PROFILES_DIR = ROOT / "force-app/main/default/profiles"
FIELD_LIST = ROOT / "tools/contact_fields_from_org.json"
NS = "http://soap.sforce.com/2006/04/metadata"
ET.register_namespace("", NS)


def qname(name):
    return f"{{{NS}}}{name}"


def contact_fields():
    records = json.loads(FIELD_LIST.read_text(encoding="utf-8"))["result"]["records"]
    fields = []
    for record in records:
        data_type = record.get("DataType") or ""
        editable = not data_type.startswith("Formula")
        fields.append((f'Contact.{record["QualifiedApiName"]}', editable))
    return sorted(set(fields))


def field_permission_element(field_name, editable):
    element = ET.Element(qname("fieldPermissions"))
    editable_el = ET.SubElement(element, qname("editable"))
    editable_el.text = "true" if editable else "false"
    field_el = ET.SubElement(element, qname("field"))
    field_el.text = field_name
    readable_el = ET.SubElement(element, qname("readable"))
    readable_el.text = "true"
    return element


def indent(element, level=0):
    pad = "\n" + level * "    "
    child_pad = "\n" + (level + 1) * "    "
    if len(element):
        if not element.text or not element.text.strip():
            element.text = child_pad
        for child in element:
            indent(child, level + 1)
        if not element[-1].tail or not element[-1].tail.strip():
            element[-1].tail = pad
    if level and (not element.tail or not element.tail.strip()):
        element.tail = pad


def update_profile(path, fields):
    tree = ET.parse(path)
    root = tree.getroot()
    for node in list(root.findall(qname("fieldPermissions"))):
        field_name = node.findtext(qname("field")) or ""
        if field_name.startswith("Contact."):
            root.remove(node)

    for field_name, editable in fields:
        root.insert(0, field_permission_element(field_name, editable))

    indent(root)
    tree.write(path, encoding="UTF-8", xml_declaration=True)


def main():
    fields = contact_fields()
    profiles = sorted(PROFILES_DIR.glob("*.profile-meta.xml"))
    for profile in profiles:
        update_profile(profile, fields)
    print(f"Updated {len(profiles)} profiles with {len(fields)} Contact field permissions")


if __name__ == "__main__":
    main()

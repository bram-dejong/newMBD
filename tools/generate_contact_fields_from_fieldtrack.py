from pathlib import Path
from xml.sax.saxutils import escape

from pyxlsb import open_workbook


ROOT = Path(__file__).resolve().parents[1]
BOOK = Path(r"C:\Users\JONGB\Downloads\Contacts fieldtrack6_26_2026.xlsb")
FIELDS_DIR = ROOT / "force-app/main/default/objects/Contact/fields"
MANAGED_NAMESPACES = {"ShowpadForSF", "BRNSHRK", "kfsell"}


def read_deployable_rows():
    rows = []
    with open_workbook(str(BOOK)) as workbook:
        with workbook.get_sheet("Field Track Report") as sheet:
            for index, row in enumerate(sheet.rows()):
                if index == 0:
                    continue
                values = [cell.v for cell in row]
                if len(values) < 20 or values[0] != "Contact":
                    continue

                api_name = str(values[3] or "").strip()
                field_type = str(values[9] or "").strip()
                is_custom = str(values[12]).lower() == "true"
                populated = int(float(values[16] or 0)) if values[16] not in (None, "") else 0

                if not is_custom or not api_name.endswith("__c") or populated <= 0:
                    continue
                if "(" in field_type or field_type == "ID":
                    continue
                if api_name.split("__", 1)[0] in MANAGED_NAMESPACES:
                    continue

                rows.append(
                    {
                        "api": api_name,
                        "label": str(values[6] or "").strip(),
                        "type": field_type,
                        "populated": populated,
                    }
                )
    return rows


def build_field_xml(row):
    label = escape(row["label"])
    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">',
        f'    <fullName>{row["api"]}</fullName>',
    ]

    if row["type"] == "BOOLEAN":
        lines.extend(
            [
                "    <defaultValue>false</defaultValue>",
                f"    <label>{label}</label>",
                "    <type>Checkbox</type>",
            ]
        )
    elif row["type"] == "DATE":
        lines.extend([f"    <label>{label}</label>", "    <type>Date</type>"])
    elif row["type"] == "DATETIME":
        lines.extend([f"    <label>{label}</label>", "    <type>DateTime</type>"])
    elif row["type"] == "DOUBLE":
        lines.extend(
            [
                f"    <label>{label}</label>",
                "    <precision>18</precision>",
                "    <scale>2</scale>",
                "    <type>Number</type>",
            ]
        )
    else:
        lines.extend(
            [
                f"    <label>{label}</label>",
                "    <length>255</length>",
                "    <type>Text</type>",
            ]
        )

    lines.append("</CustomField>")
    return "\n".join(lines) + "\n"


def write_manifest(rows):
    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<Package xmlns="http://soap.sforce.com/2006/04/metadata">',
        "    <types>",
    ]
    for row in rows:
        lines.append(f'        <members>Contact.{row["api"]}</members>')
    lines.extend(
        [
            "        <name>CustomField</name>",
            "    </types>",
            "    <types>",
            "        <members>newMBD_Import_Access</members>",
            "        <name>PermissionSet</name>",
            "    </types>",
            "    <version>65.0</version>",
            "</Package>",
            "",
        ]
    )
    (ROOT / "manifest/contact-custom-fields-package.xml").write_text(
        "\n".join(lines), encoding="utf-8"
    )


def update_permission_set(rows):
    path = ROOT / "force-app/main/default/permissionsets/newMBD_Import_Access.permissionset-meta.xml"
    text = path.read_text(encoding="utf-8")

    for row in rows:
        field_ref = f'Contact.{row["api"]}'
        if f"<field>{field_ref}</field>" in text:
            continue
        block = (
            "    <fieldPermissions>\n"
            "        <editable>true</editable>\n"
            f"        <field>{field_ref}</field>\n"
            "        <readable>true</readable>\n"
            "    </fieldPermissions>\n"
        )
        text = text.replace(
            "    <hasActivationRequired>false</hasActivationRequired>",
            block + "    <hasActivationRequired>false</hasActivationRequired>",
        )

    if "<object>Contact</object>" not in text:
        object_block = (
            "    <objectPermissions>\n"
            "        <allowCreate>true</allowCreate>\n"
            "        <allowDelete>false</allowDelete>\n"
            "        <allowEdit>true</allowEdit>\n"
            "        <allowRead>true</allowRead>\n"
            "        <modifyAllRecords>false</modifyAllRecords>\n"
            "        <object>Contact</object>\n"
            "        <viewAllRecords>false</viewAllRecords>\n"
            "    </objectPermissions>\n"
        )
        text = text.replace("</PermissionSet>", object_block + "</PermissionSet>")

    path.write_text(text, encoding="utf-8")


def main():
    rows = read_deployable_rows()
    FIELDS_DIR.mkdir(parents=True, exist_ok=True)
    for row in rows:
        (FIELDS_DIR / f'{row["api"]}.field-meta.xml').write_text(
            build_field_xml(row), encoding="utf-8"
        )
    write_manifest(rows)
    update_permission_set(rows)
    print(f"Generated {len(rows)} deployable Contact fields")
    for row in rows[:20]:
        print(f'{row["api"]}|{row["type"]}|{row["populated"]}')


if __name__ == "__main__":
    main()

"""Synthetic macro-enabled workbook bytes, with optional inert binary padding."""

import io
import zipfile

from openpyxl import Workbook


def xlsm_bytes(*, binary_bytes: int = 0) -> bytes:
    workbook = Workbook()
    workbook.active.title = "Consumption"
    workbook.active.append(["Month", "kWh"])
    workbook.active.append(["January", 125])
    workbook.create_sheet("Solar").append(["Generation", 90])
    original = io.BytesIO()
    workbook.save(original)
    workbook.close()
    output = io.BytesIO()
    with zipfile.ZipFile(original) as source, zipfile.ZipFile(output, "w") as target:
        for name in source.namelist():
            value = source.read(name)
            if name == "[Content_Types].xml":
                value = value.replace(
                    b"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml",
                    b"application/vnd.ms-excel.sheet.macroEnabled.main+xml",
                )
            target.writestr(name, value)
        # VBA is deliberately inert and stored uncompressed to exercise the
        # input byte limit independently of worksheet size/parser complexity.
        target.writestr("xl/vbaProject.bin", b"x" * binary_bytes)
    return output.getvalue()

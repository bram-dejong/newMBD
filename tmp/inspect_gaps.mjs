import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const source = "C:/Users/JONGB/OneDrive - Thermo Fisher Scientific/Documents/NewMBD/Copy of CPQ functionality gaps.xlsx";
const input = await FileBlob.load(source);
const workbook = await SpreadsheetFile.importXlsx(input);

const overview = await workbook.inspect({
  kind: "table",
  sheetId: "Sheet1",
  range: "A1:G37",
  maxChars: 40000,
  tableMaxRows: 50,
  tableMaxCols: 7,
  tableMaxCellChars: 500,
});

process.stdout.write(overview.ndjson);
